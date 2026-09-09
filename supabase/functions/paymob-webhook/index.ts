import { adminClient, json, publicError } from '../_shared/http.ts'
import { verifyPaymobSubscriptionHmac, verifyPaymobTransactionHmac } from '../_shared/paymob.ts'

type JsonRecord = Record<string, unknown>
interface PaymobCallback { type?: string, obj?: JsonRecord }
interface PaymobSubscriptionCallback {
  paymob_request_id?: string
  subscription_data?: JsonRecord
  trigger_type?: string
  hmac?: string
}

function record(value: unknown): JsonRecord {
  return value && typeof value === 'object' ? value as JsonRecord : {}
}

function text(value: unknown): string | null {
  return typeof value === 'string' && value.length ? value : typeof value === 'number' ? String(value) : null
}

function checkoutMetadata(object: JsonRecord): { organizationId: string | null, interval: 'monthly' | 'yearly' } {
  const claims = record(object.payment_key_claims)
  const extra = record(claims.extra)
  let organizationId = text(extra.organization_id)
  let billingInterval = text(extra.billing_interval)
  if (!organizationId) {
    const reference = text(record(object.order).merchant_order_id)
    const match = reference?.match(/^ledger_suit:([0-9a-f-]{36}):(monthly|yearly):/i)
    organizationId = match?.[1] ?? null
    billingInterval = match?.[2] ?? billingInterval
  }
  return { organizationId, interval: billingInterval === 'yearly' ? 'yearly' : 'monthly' }
}

function addInterval(date: Date, interval: 'monthly' | 'yearly'): string {
  if (interval === 'yearly') date.setUTCFullYear(date.getUTCFullYear() + 1)
  else date.setUTCMonth(date.getUTCMonth() + 1)
  return date.toISOString()
}

async function processSubscriptionCallback(callback: PaymobSubscriptionCallback): Promise<Response> {
  const subscription = callback.subscription_data
  const subscriptionId = text(subscription?.id)
  const triggerType = callback.trigger_type
  if (!subscription || !subscriptionId || !triggerType || !callback.paymob_request_id) {
    throw new Error('Invalid Paymob subscription callback')
  }
  if (!await verifyPaymobSubscriptionHmac(subscriptionId, triggerType, callback.hmac ?? null)) {
    return json({ error: 'Invalid Paymob HMAC' }, 401)
  }

  const admin = adminClient()
  const initialTransaction = text(subscription.initial_transaction)
  const { data: initialEvent } = initialTransaction
    ? await admin.from('billing_events').select('organization_id').eq('provider', 'paymob')
        .eq('provider_event_id', initialTransaction).maybeSingle()
    : { data: null }
  let organizationId = initialEvent?.organization_id ?? null
  if (!organizationId) {
    const { data: existing } = await admin.from('subscriptions').select('organization_id')
      .eq('provider', 'paymob').eq('provider_subscription_id', subscriptionId).maybeSingle()
    organizationId = existing?.organization_id ?? null
  }
  if (!organizationId) throw new Error('Paymob subscription is not linked to an organization')

  const state = text(subscription.state)?.toLowerCase() ?? ''
  const normalizedTrigger = triggerType.toLowerCase()
  const providerStatus = state === 'active' || normalizedTrigger === 'resumed' || normalizedTrigger === 'successful transaction'
    ? 'active'
    : state === 'canceled' || state === 'cancelled' || normalizedTrigger === 'canceled'
      ? 'cancelled'
      : normalizedTrigger.includes('failed') ? 'past_due' : 'suspended'
  const interval = Number(subscription.frequency) >= 360 ? 'yearly' : 'monthly'
  const { data: processed, error } = await admin.rpc('apply_paymob_subscription_event', {
    p_event_id: callback.paymob_request_id,
    p_event_type: `subscription.${normalizedTrigger.replaceAll(' ', '_')}`,
    p_payload: callback,
    p_organization_id: organizationId,
    p_subscription_id: subscriptionId,
    p_provider_status: providerStatus,
    p_interval: interval,
    p_period_start: null,
    p_period_end: text(subscription.next_billing),
    p_last_payment_at: normalizedTrigger === 'successful transaction' ? new Date().toISOString() : null,
    p_payment_failed_at: normalizedTrigger.includes('failed') ? new Date().toISOString() : null,
  })
  if (error) throw error
  return json({ received: true, processed: Boolean(processed) })
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405)
  try {
    const callback = JSON.parse(await request.text()) as PaymobCallback & PaymobSubscriptionCallback
    if (callback.subscription_data) return await processSubscriptionCallback(callback)
    if (callback.type !== 'TRANSACTION' || !callback.obj) return json({ received: true, ignored: true })
    const requestUrl = new URL(request.url)
    if (!await verifyPaymobTransactionHmac(callback.obj, requestUrl.searchParams.get('hmac'))) {
      return json({ error: 'Invalid Paymob HMAC' }, 401)
    }

    const object = callback.obj
    const eventId = text(object.id)
    const orderId = text(record(object.order).id)
    const { organizationId, interval } = checkoutMetadata(object)
    if (!eventId || !orderId || !organizationId) throw new Error('Paymob callback is missing checkout metadata')

    const succeeded = object.success === true && object.pending === false
    const occurredAt = text(object.created_at) ?? new Date().toISOString()
    const subscriptionId = text(object.subscription_id)
      ?? text(record(object.subscription).id)
      ?? `order_${orderId}`
    const admin = adminClient()
    const { data: processed, error } = await admin.rpc('apply_paymob_subscription_event', {
      p_event_id: eventId,
      p_event_type: succeeded ? 'transaction.succeeded' : 'transaction.failed',
      p_payload: callback,
      p_organization_id: organizationId,
      p_subscription_id: subscriptionId,
      p_provider_status: succeeded ? 'active' : 'past_due',
      p_interval: interval,
      p_period_start: succeeded ? occurredAt : null,
      p_period_end: succeeded ? addInterval(new Date(occurredAt), interval) : null,
      p_last_payment_at: succeeded ? occurredAt : null,
      p_payment_failed_at: succeeded ? null : occurredAt,
    })
    if (error) throw error

    if (!processed) {
      const { data: storedEvent } = await admin
        .from('billing_events')
        .select('processing_error')
        .eq('provider', 'paymob')
        .eq('provider_event_id', eventId)
        .maybeSingle()
      if (storedEvent?.processing_error) throw new Error(storedEvent.processing_error)
    }
    return json({ received: true, processed: Boolean(processed) })
  }
  catch (error) {
    return json({ error: publicError(error) }, 400)
  }
})

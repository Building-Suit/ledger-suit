import { adminClient, json, publicError } from '../_shared/http.ts'
import { stripeRequest, verifyStripeSignature } from '../_shared/stripe.ts'

type StripeRecord = Record<string, unknown>
interface StripeEvent { id: string, type: string, data: { object: StripeRecord } }

function stringId(value: unknown): string | null {
  if (typeof value === 'string') return value
  if (value && typeof value === 'object' && typeof (value as StripeRecord).id === 'string') {
    return (value as StripeRecord).id as string
  }
  return null
}

function timestamp(value: unknown): string | null {
  return typeof value === 'number' ? new Date(value * 1000).toISOString() : null
}

function metadata(object: StripeRecord): StripeRecord {
  return object.metadata && typeof object.metadata === 'object' ? object.metadata as StripeRecord : {}
}

function interval(subscription: StripeRecord): 'monthly' | 'yearly' {
  const items = subscription.items as StripeRecord | undefined
  const data = Array.isArray(items?.data) ? items.data as StripeRecord[] : []
  const price = data[0]?.price as StripeRecord | undefined
  const recurring = price?.recurring as StripeRecord | undefined
  return recurring?.interval === 'year' ? 'yearly' : 'monthly'
}

async function loadSubscription(id: string): Promise<StripeRecord> {
  return await stripeRequest<StripeRecord>(`/subscriptions/${encodeURIComponent(id)}?expand[]=items.data.price`)
}

async function billingNotification(
  organizationId: string,
  eventType: string,
): Promise<void> {
  const admin = adminClient()
  const { data: owners } = await admin
    .from('organization_members')
    .select('user_id')
    .eq('organization_id', organizationId)
    .eq('role', 'owner')
    .eq('status', 'active')

  const copy = eventType === 'invoice.payment_failed'
    ? {
        type: 'billing.payment_failed',
        title: 'Subscription payment failed',
        body: 'Please update your payment method to keep Ledger Suit writable.',
        severity: 'error',
      }
    : {
        type: 'billing.trial_ending',
        title: 'Your Ledger Suit trial is ending soon',
        body: 'Your saved payment method will be charged when the 14-day trial ends.',
        severity: 'warning',
      }

  if (!owners?.length) return
  await admin.from('notifications').insert(owners.map(owner => ({
    organization_id: organizationId,
    user_id: owner.user_id,
    ...copy,
    action_url: '/billing',
    metadata: { stripe_event_type: eventType },
  })))
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405)
  const rawBody = await request.text()
  try {
    const verified = await verifyStripeSignature(rawBody, request.headers.get('Stripe-Signature'))
    if (!verified) return json({ error: 'Invalid Stripe signature' }, 400)

    const event = JSON.parse(rawBody) as StripeEvent
    let source = event.data.object
    let subscription = source
    let subscriptionId = event.type.startsWith('customer.subscription.') ? stringId(source.id) : null

    if (event.type === 'checkout.session.completed') {
      subscriptionId = stringId(source.subscription)
      if (!subscriptionId) throw new Error('Checkout completed without a subscription')
      subscription = await loadSubscription(subscriptionId)
    }
    else if (event.type.startsWith('invoice.')) {
      subscriptionId = stringId(source.subscription)
        ?? stringId((source.parent as StripeRecord | undefined)?.subscription_details
          && ((source.parent as StripeRecord).subscription_details as StripeRecord).subscription)
      if (!subscriptionId) return json({ received: true, ignored: true })
      subscription = await loadSubscription(subscriptionId)
    }

    if (!subscriptionId || ![
      'checkout.session.completed',
      'customer.subscription.created',
      'customer.subscription.updated',
      'customer.subscription.deleted',
      'customer.subscription.trial_will_end',
      'invoice.paid',
      'invoice.payment_failed',
    ].includes(event.type)) return json({ received: true, ignored: true })

    const organizationId = String(
      metadata(subscription).organization_id
      ?? metadata(source).organization_id
      ?? '',
    )
    if (!organizationId) throw new Error('Stripe subscription is missing organization metadata')

    const providerStatus = event.type === 'customer.subscription.deleted'
      ? 'canceled'
      : String(subscription.status ?? 'incomplete')
    const customerId = stringId(subscription.customer) ?? stringId(source.customer)
    const admin = adminClient()
    const { data: processed, error } = await admin.rpc('apply_stripe_subscription_event', {
      p_event_id: event.id,
      p_event_type: event.type,
      p_payload: event,
      p_organization_id: organizationId,
      p_customer_id: customerId,
      p_subscription_id: subscriptionId,
      p_provider_status: providerStatus,
      p_interval: interval(subscription),
      p_trial_start: timestamp(subscription.trial_start),
      p_trial_end: timestamp(subscription.trial_end),
      p_period_start: timestamp(subscription.current_period_start),
      p_period_end: timestamp(subscription.current_period_end),
      p_cancel_at_period_end: Boolean(subscription.cancel_at_period_end),
      p_last_payment_at: event.type === 'invoice.paid' ? new Date().toISOString() : null,
      p_payment_failed_at: event.type === 'invoice.payment_failed' ? new Date().toISOString() : null,
    })
    if (error) throw error

    if (!processed) {
      const { data: storedEvent } = await admin
        .from('billing_events')
        .select('processing_error')
        .eq('provider', 'stripe')
        .eq('provider_event_id', event.id)
        .maybeSingle()
      if (storedEvent?.processing_error) throw new Error(storedEvent.processing_error)
    }

    if (processed && ['invoice.payment_failed', 'customer.subscription.trial_will_end'].includes(event.type)) {
      await billingNotification(organizationId, event.type)
    }
    return json({ received: true, processed: Boolean(processed) })
  }
  catch (error) {
    return json({ error: publicError(error) }, 400)
  }
})

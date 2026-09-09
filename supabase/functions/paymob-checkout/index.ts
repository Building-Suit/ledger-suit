import { authenticatedClient, handleOptions, json, publicError, readJson, requiredEnv } from '../_shared/http.ts'
import { paymobCheckoutUrl, paymobRequest } from '../_shared/paymob.ts'

interface CheckoutBody { organizationId: string, interval: 'monthly' | 'yearly' }
interface CheckoutContext {
  organization_id: string
  organization_name: string
  billing_email: string
  billing_name: string | null
  billing_phone: string | null
  access_state: string
}
interface PaymobIntention { id: string, intention_order_id: number, client_secret: string }

function customerName(fullName: string | null): { firstName: string, lastName: string } {
  const parts = fullName?.trim().split(/\s+/).filter(Boolean) ?? []
  return {
    firstName: parts[0] ?? 'Ledger',
    lastName: parts.slice(1).join(' ') || 'Suit Customer',
  }
}

Deno.serve(async (request) => {
  const preflight = handleOptions(request)
  if (preflight) return preflight
  try {
    const { organizationId, interval } = await readJson<CheckoutBody>(request)
    if (!organizationId || !['monthly', 'yearly'].includes(interval)) throw new Error('Invalid checkout request')

    const supabase = await authenticatedClient(request)
    const { data, error } = await supabase.rpc('billing_checkout_context', {
      p_organization_id: organizationId,
      p_interval: interval,
    })
    if (error) throw error
    const context = (data as CheckoutContext[] | null)?.[0]
    if (!context) throw new Error('Organization not found')
    if (!['trialing', 'checkout_required', 'read_only'].includes(context.access_state)) {
      throw new Error('Subscription is already active')
    }
    if (!context.billing_phone) throw new Error('A billing phone number is required before checkout.')

    const prefix = interval === 'monthly' ? 'PAYMOB_MONTHLY' : 'PAYMOB_YEARLY'
    const amount = Number(requiredEnv(`${prefix}_AMOUNT_CENTS`))
    const planId = Number(requiredEnv(`${prefix}_PLAN_ID`))
    const integrationId = Number(requiredEnv('PAYMOB_CARD_INTEGRATION_ID'))
    if (![amount, planId, integrationId].every(Number.isSafeInteger) || amount <= 0) {
      throw new Error('Paymob billing configuration is invalid')
    }

    const appUrl = requiredEnv('APP_BASE_URL').replace(/\/$/, '')
    const functionUrl = requiredEnv('SUPABASE_URL').replace(/\/$/, '')
    const { firstName, lastName } = customerName(context.billing_name)
    const reference = `ledger_suit:${organizationId}:${interval}:${crypto.randomUUID()}`
    const intention = await paymobRequest<PaymobIntention>('/v1/intention/', {
      amount,
      currency: 'EGP',
      payment_methods: [integrationId],
      subscription_plan_id: planId,
      items: [{
        name: `Ledger Suit ${interval} subscription`,
        amount,
        description: `Ledger Suit subscription for ${context.organization_name}`,
        quantity: 1,
      }],
      billing_data: {
        first_name: firstName,
        last_name: lastName,
        email: context.billing_email,
        phone_number: context.billing_phone,
        apartment: 'NA',
        floor: 'NA',
        street: 'NA',
        building: 'NA',
        shipping_method: 'NA',
        postal_code: 'NA',
        city: 'Cairo',
        state: 'Cairo',
        country: 'EGY',
      },
      customer: { first_name: firstName, last_name: lastName, email: context.billing_email },
      extras: { organization_id: organizationId, billing_interval: interval },
      special_reference: reference,
      expiration: 1800,
      notification_url: `${functionUrl}/functions/v1/paymob-webhook`,
      redirection_url: `${appUrl}/subscribe?checkout=success`,
    })
    if (!intention.client_secret) throw new Error('Paymob did not return a checkout client secret')
    return json({ id: intention.id, orderId: intention.intention_order_id, url: paymobCheckoutUrl(intention.client_secret) })
  }
  catch (error) {
    return json({ error: publicError(error) }, 400)
  }
})

import { authenticatedClient, handleOptions, json, publicError, readJson, requiredEnv } from '../_shared/http.ts'
import { stripeRequest } from '../_shared/stripe.ts'

interface CheckoutBody { organizationId: string, interval: 'monthly' | 'yearly' }
interface CheckoutContext {
  organization_id: string
  organization_name: string
  billing_email: string
  provider_customer_id: string | null
  access_state: string
}

async function integrationIdentifier(seed: string): Promise<string> {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz'
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(seed)))
  const suffix = [...digest.slice(0, 8)].map(byte => alphabet[byte % alphabet.length]).join('')
  return `ledger_suit_org_${suffix}`
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

    const priceId = requiredEnv(interval === 'monthly' ? 'STRIPE_MONTHLY_PRICE_ID' : 'STRIPE_YEARLY_PRICE_ID')
    const appUrl = requiredEnv('APP_BASE_URL').replace(/\/$/, '')
    // Repeated clicks inside the same half-hour return the same Stripe session,
    // preventing accidental duplicate subscriptions without storing checkout
    // session secrets in the browser. Every request parameter, including the
    // tracking label, must stay stable while this idempotency key is reused.
    const bucket = Math.floor(Date.now() / (30 * 60 * 1000))
    const body = new URLSearchParams({
      mode: 'subscription',
      integration_identifier: await integrationIdentifier(`${organizationId}/${interval}/${bucket}`),
      'line_items[0][price]': priceId,
      'line_items[0][quantity]': '1',
      'subscription_data[metadata][organization_id]': organizationId,
      'metadata[organization_id]': organizationId,
      'metadata[billing_interval]': interval,
      client_reference_id: organizationId,
      customer_email: context.provider_customer_id ? '' : context.billing_email,
      // Checkout can return before Stripe's webhook reaches the database. The
      // subscription route has a bounded confirmation state for that window.
      success_url: `${appUrl}/subscribe?checkout=success&session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${appUrl}/subscribe?checkout=cancelled`,
    })
    if (context.provider_customer_id) {
      body.delete('customer_email')
      body.set('customer', context.provider_customer_id)
    }
    const session = await stripeRequest<{ id: string, url: string }>('/checkout/sessions', {
      method: 'POST',
      body,
      idempotencyKey: `checkout/${organizationId}/${interval}/${bucket}`,
    })
    return json({ id: session.id, url: session.url })
  }
  catch (error) {
    return json({ error: publicError(error) }, 400)
  }
})

import { authenticatedClient, handleOptions, json, publicError, readJson, requiredEnv } from '../_shared/http.ts'
import { stripeRequest } from '../_shared/stripe.ts'

Deno.serve(async (request) => {
  const preflight = handleOptions(request)
  if (preflight) return preflight
  try {
    const { organizationId } = await readJson<{ organizationId: string }>(request)
    const supabase = await authenticatedClient(request)
    const { data, error } = await supabase.rpc('billing_checkout_context', {
      p_organization_id: organizationId,
      p_interval: 'monthly',
    })
    if (error) throw error
    const customerId = (data as Array<{ provider_customer_id: string | null }> | null)?.[0]?.provider_customer_id
    if (!customerId) throw new Error('Complete checkout before opening the billing portal.')

    const body = new URLSearchParams({
      customer: customerId,
      return_url: `${requiredEnv('APP_BASE_URL').replace(/\/$/, '')}/billing`,
    })
    const session = await stripeRequest<{ url: string }>('/billing_portal/sessions', { method: 'POST', body })
    return json({ url: session.url })
  }
  catch (error) {
    return json({ error: publicError(error) }, 400)
  }
})

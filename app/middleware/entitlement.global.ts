const PUBLIC_PATHS = new Set(['/', '/login', '/signup', '/verify-email', '/accept-invitation'])

/**
 * Keep unpaid workspaces out of the product shell entirely. Database write
 * gates remain the authority; this route gate prevents accidental UI exposure
 * through direct links and bookmarked finance pages.
 */
export default defineNuxtRouteMiddleware(async (to) => {
  if (PUBLIC_PATHS.has(to.path)) return

  // Browser sessions are persisted in storage by the Nuxt Supabase client.
  // During SSR there is no browser session to inspect, so leave the route
  // blank until the client can make the authoritative entitlement decision.
  if (import.meta.server) return

  const supabase = useSupabaseClient()
  // Immediately after sign-in, Nuxt's reactive auth user can trail the SDK by
  // one navigation. Ask Supabase for the verified user instead of racing local
  // storage with a fixed timeout.
  let user = useSupabaseUser().value
  if (!user) user = (await supabase.auth.getUser()).data.user
  if (!user) return navigateTo('/login')

  const tenant = useTenant()
  await tenant.loadOrganizations(user.id)

  // A confirmed user who has not completed organization setup is sent to the
  // setup flow by the normal product route. There is no subscription yet to
  // pay for, so do not manufacture a billing decision here.
  if (!tenant.currentId.value) return

  const billing = useBilling()
  const isCheckoutReturn = to.query.checkout === 'success'
  await billing.load({ force: isCheckoutReturn })

  if (billing.checkoutRequired.value && to.path !== '/subscribe') {
    // Older Checkout Sessions return to /billing. Preserve their success
    // marker so the subscribe page can wait for the webhook to arrive.
    return navigateTo({
      path: '/subscribe',
      query: isCheckoutReturn ? to.query : undefined,
    }, { replace: true })
  }

  if (!billing.checkoutRequired.value && to.path === '/subscribe') {
    return navigateTo('/dashboard')
  }
})

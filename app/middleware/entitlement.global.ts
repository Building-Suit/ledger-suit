const PUBLIC_PATHS = new Set(['/', '/login', '/signup', '/verify-email'])

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
  // Let the auth state listener consume the successful sign-in response before
  // checking the persisted session on the next navigation.
  await nextTick()
  let { data: { session } } = await supabase.auth.getSession()
  if (!session) {
    await new Promise(resolve => setTimeout(resolve, 100))
    session = (await supabase.auth.getSession()).data.session
  }
  const transitionUserId = useState<string | null>('auth:transition-user', () => null)
  const user = useSupabaseUser().value ?? session?.user ?? (transitionUserId.value ? { id: transitionUserId.value } : null)
  if (!user) return navigateTo('/login')

  const tenant = useTenant()
  await tenant.loadOrganizations(user.id)

  // A confirmed user who has not completed organization setup is sent to the
  // setup flow by the normal product route. There is no subscription yet to
  // pay for, so do not manufacture a billing decision here.
  if (!tenant.currentId.value) return

  const billing = useBilling()
  await billing.load()

  if (billing.checkoutRequired.value && to.path !== '/subscribe') {
    return navigateTo('/subscribe')
  }

  if (!billing.checkoutRequired.value && to.path === '/subscribe') {
    return navigateTo('/dashboard')
  }
})

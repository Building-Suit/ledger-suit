import type { Database } from '~~/types/database.types'

export type SubscriptionAccessState = 'loading' | 'checkout_required' | 'trialing' | 'active' | 'grace_period' | 'read_only'

export interface SubscriptionSummary {
  status: Database['public']['Enums']['billing_status']
  billing_interval: Database['public']['Enums']['billing_interval'] | null
  trial_ends_at: string | null
  current_period_end: string | null
  grace_period_ends_at: string | null
  cancel_at_period_end: boolean
  provider_status: string | null
}

// Composables are instantiated by middleware, layouts, and pages. Keep the
// in-flight request on the Nuxt app instance so those callers await the same
// work without sharing authenticated data between SSR requests.
const pendingLoads = new WeakMap<object, Map<string, Promise<void>>>()

export function useBilling() {
  const nuxtApp = useNuxtApp()
  const supabase = useSupabaseClient<Database>()
  const { currentId } = useTenant()
  const accessState = useState<SubscriptionAccessState>('billing:access', () => 'loading')
  const subscription = useState<SubscriptionSummary | null>('billing:subscription', () => null)
  const loading = useState<boolean>('billing:loading', () => false)
  const loadedOrganizationId = useState<string | null>('billing:loadedOrganizationId', () => null)

  const writesAllowed = computed(() => ['trialing', 'active', 'grace_period'].includes(accessState.value))
  const checkoutRequired = computed(() => accessState.value === 'checkout_required')
  const readOnly = computed(() => accessState.value === 'read_only')

  async function load(options: { force?: boolean } = {}) {
    if (!currentId.value) {
      accessState.value = 'loading'
      subscription.value = null
      loadedOrganizationId.value = null
      return
    }

    const organizationId = currentId.value
    if (!options.force && loadedOrganizationId.value === organizationId) return

    let appLoads = pendingLoads.get(nuxtApp)
    if (!appLoads) {
      appLoads = new Map()
      pendingLoads.set(nuxtApp, appLoads)
    }

    const pending = appLoads.get(organizationId)
    if (pending) return pending

    const request = (async () => {
      loading.value = true
      try {
        const [stateResult, subscriptionResult] = await Promise.all([
          supabase.rpc('subscription_access_state', { p_organization_id: organizationId }),
          supabase
            .from('subscriptions')
            .select('status,billing_interval,trial_ends_at,current_period_end,grace_period_ends_at,cancel_at_period_end,provider_status')
            .eq('organization_id', organizationId)
            .maybeSingle(),
        ])
        if (stateResult.error) throw stateResult.error
        if (subscriptionResult.error) throw subscriptionResult.error

        // A tenant switch may finish while this request is in flight. Never
        // publish the previous organization's billing state under the new one.
        if (currentId.value !== organizationId) return
        accessState.value = stateResult.data as SubscriptionAccessState
        subscription.value = subscriptionResult.data as SubscriptionSummary | null
        loadedOrganizationId.value = organizationId
      }
      finally {
        appLoads.delete(organizationId)
        if (currentId.value === organizationId) loading.value = false
      }
    })()

    appLoads.set(organizationId, request)
    return request
  }

  return { accessState, subscription, loading, writesAllowed, checkoutRequired, readOnly, load }
}

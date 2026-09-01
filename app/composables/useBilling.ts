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

export function useBilling() {
  const supabase = useSupabaseClient<Database>()
  const { currentId } = useTenant()
  const accessState = useState<SubscriptionAccessState>('billing:access', () => 'loading')
  const subscription = useState<SubscriptionSummary | null>('billing:subscription', () => null)
  const loading = useState<boolean>('billing:loading', () => false)

  const writesAllowed = computed(() => ['trialing', 'active', 'grace_period'].includes(accessState.value))
  const checkoutRequired = computed(() => accessState.value === 'checkout_required')
  const readOnly = computed(() => accessState.value === 'read_only')

  async function load() {
    if (!currentId.value) {
      accessState.value = 'loading'
      subscription.value = null
      return
    }

    loading.value = true
    try {
      const [stateResult, subscriptionResult] = await Promise.all([
        supabase.rpc('subscription_access_state', { p_organization_id: currentId.value }),
        supabase
          .from('subscriptions')
          .select('status,billing_interval,trial_ends_at,current_period_end,grace_period_ends_at,cancel_at_period_end,provider_status')
          .eq('organization_id', currentId.value)
          .maybeSingle(),
      ])
      if (stateResult.error) throw stateResult.error
      if (subscriptionResult.error) throw subscriptionResult.error
      accessState.value = stateResult.data as SubscriptionAccessState
      subscription.value = subscriptionResult.data as SubscriptionSummary | null
    }
    finally {
      loading.value = false
    }
  }

  return { accessState, subscription, loading, writesAllowed, checkoutRequired, readOnly, load }
}

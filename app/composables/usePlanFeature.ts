import type { Database } from '~~/types/database.types'

export function usePlanFeature(featureKey: string) {
  const supabase = useSupabaseClient<Database>()
  const { currentId } = useTenant()

  return useLazyAsyncData<boolean>(`org:feature:${featureKey}`, async () => {
    if (!currentId.value) return false
    const { data, error } = await supabase.rpc('can_use_feature', {
      p_organization_id: currentId.value,
      p_feature_key: featureKey,
    })
    if (error) throw error
    return data === true
  // Plan gates are advisory UI state; the database remains authoritative.
  // Resolve them in the authenticated browser session to avoid rendering a
  // stale entitlement from an SSR request without the persisted client token.
  }, { watch: [currentId], default: () => false, server: false })
}

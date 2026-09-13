import type { Database, Json } from '~~/types/database.types'

export type QuotaKey = 'max_members' | 'max_monthly_transactions' | 'max_storage_bytes' | 'max_accounts' | 'max_counterparties' | 'max_recurring_rules' | 'max_custom_roles'
type RawUsageRow = Database['public']['Functions']['subscription_usage_summary']['Returns'][number]
export type UsageRow = Omit<RawUsageRow, 'limit_value' | 'remaining_value'> & {
  limit_value: number | null
  remaining_value: number | null
}
type CatalogPlan = Database['public']['Functions']['subscription_plan_catalog']['Returns'][number]
type JsonObject = Record<string, Json | undefined>
const USAGE_TTL_MS = 30_000

const pendingLoads = new WeakMap<object, Map<string, Promise<void>>>()

function object(value: Json | undefined): JsonObject {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as JsonObject : {}
}

export function usePlanUsage() {
  const nuxtApp = useNuxtApp()
  const supabase = useSupabaseClient<Database>()
  const { currentId } = useTenant()
  const rows = useState<UsageRow[]>('plan-usage:rows', () => [])
  const catalog = useState<CatalogPlan[]>('plan-usage:catalog', () => [])
  const loadedOrganizationId = useState<string | null>('plan-usage:organization', () => null)
  const loadedAt = useState('plan-usage:loaded-at', () => 0)
  const loading = useState('plan-usage:loading', () => false)
  const loadError = useState('plan-usage:error', () => false)

  async function load(force = false) {
    const organizationId = currentId.value
    if (!organizationId) return
    if (!force && loadedOrganizationId.value === organizationId && Date.now() - loadedAt.value < USAGE_TTL_MS) return
    let appLoads = pendingLoads.get(nuxtApp)
    if (!appLoads) {
      appLoads = new Map()
      pendingLoads.set(nuxtApp, appLoads)
    }
    const existing = appLoads.get(organizationId)
    if (existing) return existing
    if (loadedOrganizationId.value !== organizationId) {
      rows.value = []
      loadedAt.value = 0
    }

    const request = (async () => {
      loading.value = true
      loadError.value = false
      try {
        const [usageResult, catalogResult] = await Promise.all([
          supabase.rpc('subscription_usage_summary', { p_organization_id: organizationId }),
          supabase.rpc('subscription_plan_catalog'),
        ])
        if (usageResult.error) throw usageResult.error
        if (catalogResult.error) throw catalogResult.error
        if (currentId.value !== organizationId) return
        rows.value = (usageResult.data ?? []) as UsageRow[]
        catalog.value = catalogResult.data ?? []
        loadedOrganizationId.value = organizationId
        loadedAt.value = Date.now()
      }
      catch (error) {
        loadError.value = true
        if (import.meta.dev) console.error(error)
      }
      finally {
        appLoads.delete(organizationId)
        if (currentId.value === organizationId) loading.value = false
      }
    })()
    appLoads.set(organizationId, request)
    return request
  }

  function rowFor(quotaKey: QuotaKey) {
    return rows.value.find(row => row.quota_key === quotaKey) ?? null
  }

  function nextPlanFor(quotaKey: QuotaKey) {
    const currentKey = rows.value[0]?.plan_key
    const purchasable = catalog.value.filter(plan => plan.is_purchasable).sort((a, b) => a.sort_order - b.sort_order)
    const currentIndex = purchasable.findIndex(plan => plan.plan_key === currentKey)
    const plan = currentIndex >= 0 ? purchasable[currentIndex + 1] : undefined
    if (!plan) return null
    const entitlement = object(object(plan.entitlements)[quotaKey])
    const monthlyPrice = object(object(plan.prices).monthly)
    return {
      key: plan.plan_key,
      name: plan.name,
      limit: typeof entitlement.limit_value === 'number' ? entitlement.limit_value : null,
      monthlyPriceMinor: typeof monthlyPrice.amount_minor === 'number' ? monthlyPrice.amount_minor : null,
    }
  }

  watch(currentId, () => void load(), { immediate: true })

  return { rows, catalog, loading, loadError, load, refresh: () => load(true), rowFor, nextPlanFor }
}

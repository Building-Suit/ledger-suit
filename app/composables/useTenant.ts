import type { Database } from '~~/types/database.types'

/**
 * Tenant context.
 *
 * Every page reads the current organization from here rather than passing an
 * organization id down through props. Switching organization clears the cached
 * payloads, so Organization A's data can never be rendered under Organization
 * B's heading.
 *
 * The capability list is advisory — it decides what the UI offers. The database
 * decides what actually happens; see docs/architecture.md.
 */

export type MembershipRole = Database['public']['Enums']['organization_role']

export interface TenantOrganization {
  id: string
  name: string
  legal_name: string | null
  slug: string
  base_currency: string
  timezone: string
  status: string
  role: MembershipRole
  role_id: string | null
}

const STORAGE_KEY = 'ledger-suit.organization'
const pendingLoads = new WeakMap<object, Map<string, Promise<void>>>()

export function useTenant() {
  const nuxtApp = useNuxtApp()
  const supabase = useSupabaseClient<Database>()
  const user = useSupabaseUser()
  const organizationCookie = useCookie<string | null>(STORAGE_KEY, { maxAge: 60 * 60 * 24 * 365, path: '/' })

  const organizations = useState<TenantOrganization[]>('tenant:organizations', () => [])
  const currentId = useState<string | null>('tenant:currentId', () => null)
  const capabilities = useState<string[]>('tenant:capabilities', () => [])
  const customRoleNames = useState<Map<string, { name_en: string, name_ar: string }>>('tenant:customRoleNames', () => new Map())
  const customRoleKeys = useState<Map<string, string>>('tenant:customRoleKeys', () => new Map())
  const loading = useState<boolean>('tenant:loading', () => false)
  const loadedUserId = useState<string | null>('tenant:loadedUserId', () => null)

  // These Nuxt data helpers resolve the active app internally. Tenant methods
  // can be called from event handlers or after Supabase promises settle, where
  // that implicit async context no longer exists. Re-enter the app captured
  // when this composable was created before touching the Nuxt data cache.
  function clearOrganizationData() {
    return nuxtApp.runWithContext(() => clearNuxtData(key => key.startsWith('org:')))
  }

  function refreshOrganizationData() {
    return nuxtApp.runWithContext(() => refreshNuxtData())
  }

  const current = computed(
    () => organizations.value.find(o => o.id === currentId.value) ?? null,
  )

  const baseCurrency = computed(() => current.value?.base_currency ?? 'EGP')

  /** Does the caller hold this capability in the current organization? */
  function can(capability: string): boolean {
    return capabilities.value.includes(capability)
  }

  /**
   * Readable role label. Custom roles resolve to their localized name
   * (Arabic under ar, English otherwise) with the key as a fallback; system
   * roles resolve through i18n.
   */
  function roleLabel(role: string | null | undefined, roleId?: string | null): string {
    const { t, locale } = useI18n()
    if (roleId) {
      const custom = customRoleNames.value.get(roleId)
      if (custom) return locale.value === 'ar' ? custom.name_ar : custom.name_en
      const fallback = customRoleKeys.value.get(roleId)
      if (fallback) return fallback
    }
    if (role) return t(`org.roles.${role}`)
    return ''
  }

  async function loadCapabilities() {
    if (!currentId.value) {
      capabilities.value = []
      customRoleNames.value = new Map()
      customRoleKeys.value = new Map()
      return
    }

    const [capabilityResult, roleResult] = await Promise.all([
      supabase.rpc('my_capabilities', { p_organization_id: currentId.value }),
      supabase
        .from('organization_roles')
        .select('id, key, name_en, name_ar')
        .eq('organization_id', currentId.value),
    ])

    if (capabilityResult.error) throw capabilityResult.error
    capabilities.value = (capabilityResult.data as string[] | null) ?? []

    if (roleResult.error) throw roleResult.error
    const names = new Map<string, { name_en: string, name_ar: string }>()
    const keys = new Map<string, string>()
    for (const role of roleResult.data ?? []) {
      names.set(role.id, { name_en: role.name_en, name_ar: role.name_ar })
      keys.set(role.id, role.key)
    }
    customRoleNames.value = names
    customRoleKeys.value = keys
  }

  async function loadOrganizations(authenticatedUserId?: string, options: { force?: boolean } = {}) {
    // Route middleware can run immediately after sign-in, before Nuxt's
    // reactive auth user has caught up. The verified user from getUser is
    // sufficient to continue; the database request still carries the user's
    // JWT and remains fully protected by RLS.
    const userId = authenticatedUserId ?? user.value?.id
    if (!userId) return
    if (!options.force && loadedUserId.value === userId) return

    if (loadedUserId.value && loadedUserId.value !== userId) {
      // A second sign-in can happen without a document reload. Remove every
      // payload belonging to the previous identity before loading the next.        // Drop the previous tenant's custom roles along with its payloads.
        clearOrganizationData()
        customRoleNames.value = new Map()
        customRoleKeys.value = new Map()
        organizations.value = []
      currentId.value = null
      capabilities.value = []
      loadedUserId.value = null
    }

    let appLoads = pendingLoads.get(nuxtApp)
    if (!appLoads) {
      appLoads = new Map()
      pendingLoads.set(nuxtApp, appLoads)
    }
    const pending = appLoads.get(userId)
    if (pending) return pending

    const request = (async () => {
      loading.value = true
      try {
        const { data, error } = await supabase
          .from('organization_members')
          .select('role, role_id, organizations(id, name, legal_name, slug, base_currency, timezone, status)')
          .eq('status', 'active')
          .eq('user_id', userId)

        if (error) throw error

        organizations.value = (data ?? [])
          .flatMap((row) => {
            const org = row.organizations as TenantOrganization | null
            return org ? [{ ...org, role: row.role as MembershipRole, role_id: row.role_id ?? null }] : []
          })
          .sort((a, b) => a.name.localeCompare(b.name))

        // Restore the last used organization, but only if the membership still
        // exists — a removed member must not keep a stale tenant selected.
        const remembered = organizationCookie.value
        const valid = organizations.value.some(o => o.id === remembered)

        const nextOrganizationId = valid ? remembered : (organizations.value[0]?.id ?? null)
        if (currentId.value !== nextOrganizationId) {
          clearOrganizationData()
          currentId.value = nextOrganizationId
          if (nextOrganizationId && nextOrganizationId !== remembered) {
            organizationCookie.value = nextOrganizationId
          }
        }
        await loadCapabilities()
        loadedUserId.value = userId
      }
      finally {
        appLoads.delete(userId)
        loading.value = false
      }
    })()

    appLoads.set(userId, request)
    return request
  }

  async function setOrganization(id: string) {
    if (id === currentId.value) return

    // Drop every tenant-scoped payload before the new organization renders.
    clearOrganizationData()
    
    // Fetch capabilities before changing currentId to prevent watchers from firing
    // and failing capability checks before they are ready.
    const { data } = await supabase.rpc('my_capabilities', {
      p_organization_id: id,
    })
    capabilities.value = (data as string[] | null) ?? []

    currentId.value = id
    organizationCookie.value = id

    await refreshOrganizationData()
  }

  return {
    organizations,
    current,
    currentId,
    capabilities,
    customRoleNames,
    customRoleKeys,
    baseCurrency,
    loading,
    can,
    roleLabel,
    loadOrganizations,
    setOrganization,
  }
}

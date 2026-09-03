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
  slug: string
  base_currency: string
  timezone: string
  status: string
  role: MembershipRole
}

const STORAGE_KEY = 'ledger-suit.organization'

export function useTenant() {
  const supabase = useSupabaseClient<Database>()
  const user = useSupabaseUser()

  const organizations = useState<TenantOrganization[]>('tenant:organizations', () => [])
  const currentId = useState<string | null>('tenant:currentId', () => null)
  const capabilities = useState<string[]>('tenant:capabilities', () => [])
  const loading = useState<boolean>('tenant:loading', () => false)

  const current = computed(
    () => organizations.value.find(o => o.id === currentId.value) ?? null,
  )

  const baseCurrency = computed(() => current.value?.base_currency ?? 'EGP')

  /** Does the caller hold this capability in the current organization? */
  function can(capability: string): boolean {
    return capabilities.value.includes(capability)
  }

  async function loadCapabilities() {
    if (!currentId.value) {
      capabilities.value = []
      return
    }

    const { data, error } = await supabase.rpc('my_capabilities', {
      p_organization_id: currentId.value,
    })

    if (error) throw error
    capabilities.value = (data as string[] | null) ?? []
  }

  async function loadOrganizations(authenticatedUserId?: string) {
    // Route middleware can run immediately after sign-in, before Nuxt's
    // reactive auth user has caught up. The verified user from getUser is
    // sufficient to continue; the database request still carries the user's
    // JWT and remains fully protected by RLS.
    if (!user.value && !authenticatedUserId) return

    loading.value = true
    try {
      const { data, error } = await supabase
        .from('organization_members')
        .select('role, organizations(id, name, slug, base_currency, timezone, status)')
        .eq('status', 'active')

      if (error) throw error

      organizations.value = (data ?? [])
        .flatMap((row) => {
          const org = row.organizations as TenantOrganization | null
          return org ? [{ ...org, role: row.role as MembershipRole }] : []
        })
        .sort((a, b) => a.name.localeCompare(b.name))

      // Restore the last used organization, but only if the membership still
      // exists — a removed member must not keep a stale tenant selected.
      const remembered = import.meta.client ? localStorage.getItem(STORAGE_KEY) : null
      const valid = organizations.value.some(o => o.id === remembered)

      currentId.value = valid ? remembered : (organizations.value[0]?.id ?? null)

      await loadCapabilities()
    }
    finally {
      loading.value = false
    }
  }

  async function setOrganization(id: string) {
    if (id === currentId.value) return

    currentId.value = id
    if (import.meta.client) localStorage.setItem(STORAGE_KEY, id)

    // Drop every tenant-scoped payload before the new organization renders.
    clearNuxtData(key => key.startsWith('org:'))
    capabilities.value = []

    await loadCapabilities()
    await refreshNuxtData()
  }

  return {
    organizations,
    current,
    currentId,
    capabilities,
    baseCurrency,
    loading,
    can,
    loadOrganizations,
    setOrganization,
  }
}

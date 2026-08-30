import type { Database } from '~~/types/database.types'

/**
 * Reference data for the current organization.
 *
 * All keys start with `org:` so useTenant().setOrganization can drop them in
 * one sweep — a switch must never leave Organization A's accounts on screen
 * under Organization B's name.
 */

export type AccountType = Database['public']['Enums']['account_type']

export interface AccountRow {
  id: string
  code: string | null
  name: string
  type: AccountType
  subtype: string
  currency: string
  is_liquid: boolean
  is_archived: boolean
  is_system: boolean
  system_key: string | null
  parent_account_id: string | null
}

export interface CategoryRow {
  id: string
  name: string
  kind: Database['public']['Enums']['category_kind']
  default_account_id: string | null
}

export interface CounterpartyRow {
  id: string
  name: string
  type: Database['public']['Enums']['counterparty_type']
}

export function useOrgAccounts() {
  const supabase = useSupabaseClient<Database>()
  const { currentId } = useTenant()

  return useAsyncData<AccountRow[]>('org:accounts', async () => {
    if (!currentId.value) return []

    const { data, error } = await supabase
      .from('accounts')
      .select('id, code, name, type, subtype, currency, is_liquid, is_archived, is_system, system_key, parent_account_id')
      .eq('organization_id', currentId.value)
      .order('code', { ascending: true, nullsFirst: false })

    if (error) throw error
    return (data ?? []) as AccountRow[]
  }, { watch: [currentId], default: () => [] })
}

export function useOrgCategories() {
  const supabase = useSupabaseClient<Database>()
  const { currentId } = useTenant()

  return useAsyncData<CategoryRow[]>('org:categories', async () => {
    if (!currentId.value) return []

    const { data, error } = await supabase
      .from('categories')
      .select('id, name, kind, default_account_id')
      .eq('organization_id', currentId.value)
      .eq('is_active', true)
      .order('name')

    if (error) throw error
    return (data ?? []) as CategoryRow[]
  }, { watch: [currentId], default: () => [] })
}

export function useOrgCounterparties() {
  const supabase = useSupabaseClient<Database>()
  const { currentId } = useTenant()

  return useAsyncData<CounterpartyRow[]>('org:counterparties', async () => {
    if (!currentId.value) return []

    const { data, error } = await supabase
      .from('counterparties')
      .select('id, name, type')
      .eq('organization_id', currentId.value)
      .eq('is_archived', false)
      .order('name')

    if (error) throw error
    return (data ?? []) as CounterpartyRow[]
  }, { watch: [currentId], default: () => [] })
}

/** Accounts a payment can come from or land in: cash, bank, wallet, cards. */
export function usePaymentAccounts(accounts: Ref<AccountRow[]>) {
  return computed(() =>
    accounts.value.filter(
      a => !a.is_archived
        && (a.is_liquid || ['credit_card', 'accounts_receivable', 'accounts_payable'].includes(a.subtype)),
    ),
  )
}

/** Leaf accounts of a given type — the ones it makes sense to post to. */
export function useAccountsOfType(accounts: Ref<AccountRow[]>, types: AccountType[]) {
  return computed(() => {
    const parents = new Set(
      accounts.value.map(a => a.parent_account_id).filter(Boolean) as string[],
    )
    return accounts.value.filter(
      a => types.includes(a.type) && !a.is_archived && !parents.has(a.id),
    )
  })
}

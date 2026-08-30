<script setup lang="ts">
import type { Database } from '~~/types/database.types'

definePageMeta({ layout: 'default' })
useHead({ title: 'Accounts · Ledger Suit' })

/**
 * Called "Accounts" for the user; internally this is the chart of accounts.
 * Balances come from public.account_balances, which derives them from posted
 * ledger entries — there is no stored balance to display.
 */

const supabase = useSupabaseClient<Database>()
const { currentId } = useTenant()

const showArchived = ref(false)

interface BalanceRow {
  account_id: string
  code: string | null
  name: string
  type: Database['public']['Enums']['account_type']
  subtype: string
  currency: string
  balance_minor: number
  entry_count: number
  is_archived: boolean
  is_liquid: boolean
  parent_account_id: string | null
}

const { data: balances } = await useAsyncData<BalanceRow[]>('org:account-balances', async () => {
  if (!currentId.value) return []

  const { data, error } = await supabase
    .from('account_balances')
    .select('account_id, code, name, type, subtype, currency, balance_minor, entry_count, is_archived, is_liquid, parent_account_id')
    .eq('organization_id', currentId.value)
    .order('code', { ascending: true, nullsFirst: false })

  if (error) throw error
  return (data ?? []) as BalanceRow[]
}, { watch: [currentId], default: () => [] })

const GROUPS: Array<{ type: BalanceRow['type'], label: string }> = [
  { type: 'asset', label: 'Assets' },
  { type: 'liability', label: 'Liabilities' },
  { type: 'equity', label: 'Equity' },
  { type: 'revenue', label: 'Revenue' },
  { type: 'expense', label: 'Expenses' },
]

const visible = computed(() =>
  (balances.value ?? []).filter(a => showArchived.value || !a.is_archived),
)

const groups = computed(() =>
  GROUPS.map((group) => {
    const rows = visible.value.filter(a => a.type === group.type)
    // Parents are headings; their own balance would double-count the children
    // beneath them, so the group total sums leaves only.
    const parentIds = new Set(rows.map(r => r.parent_account_id).filter(Boolean) as string[])
    const total = rows
      .filter(r => !parentIds.has(r.account_id))
      .reduce((sum, r) => sum + Number(r.balance_minor), 0)

    return { ...group, rows, parentIds, total }
  }),
)

const hasAccounts = computed(() => (balances.value?.length ?? 0) > 0)
</script>

<template>
  <div class="space-y-5">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h1 class="text-xl font-semibold">Accounts</h1>
      <label class="flex items-center gap-2 text-sm text-neutral-600 dark:text-neutral-400">
        <input v-model="showArchived" type="checkbox" class="rounded border-neutral-300">
        Show archived
      </label>
    </div>

    <EmptyState
      v-if="!hasAccounts"
      title="Your default chart of accounts is ready."
      description="Accounts appear here as soon as your organization is set up."
    />

    <div v-else class="space-y-5">
      <section
        v-for="group in groups"
        :key="group.type"
        class="ls-card overflow-hidden"
        :aria-labelledby="`group-${group.type}`"
      >
        <div class="flex items-center justify-between border-b border-neutral-200 px-5 py-3 dark:border-neutral-800">
          <h2 :id="`group-${group.type}`" class="text-sm font-semibold">{{ group.label }}</h2>
          <MoneyText class="text-sm font-semibold" :amount-minor="group.total" />
        </div>

        <div class="overflow-x-auto">
          <table class="ls-table">
            <caption class="sr-only">{{ group.label }} accounts and their balances</caption>
            <thead>
              <tr>
                <th scope="col">Code</th>
                <th scope="col">Account</th>
                <th scope="col">Currency</th>
                <th scope="col" class="text-right">Entries</th>
                <th scope="col" class="text-right">Balance</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="account in group.rows" :key="account.account_id">
                <td class="font-mono text-xs text-neutral-500">{{ account.code || '—' }}</td>
                <td>
                  <span :class="{ 'pl-4': account.parent_account_id, 'font-medium': group.parentIds.has(account.account_id) }">
                    {{ account.name }}
                  </span>
                  <span v-if="account.is_archived" class="ls-badge ml-2 bg-neutral-100 text-neutral-500 ring-neutral-500/20">
                    Archived
                  </span>
                  <span v-else-if="account.is_liquid" class="ls-badge ml-2 bg-blue-50 text-blue-700 ring-blue-600/20 dark:bg-blue-500/10 dark:text-blue-400">
                    Liquid
                  </span>
                </td>
                <td class="text-neutral-500">{{ account.currency }}</td>
                <td class="ls-num text-neutral-500">{{ account.entry_count }}</td>
                <td class="ls-num">
                  <MoneyText :amount-minor="account.balance_minor" />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
import type { Database } from '~~/types/database.types'

definePageMeta({ layout: 'default' })
/**
 * Called "Accounts" for the user; internally this is the chart of accounts.
 * Balances come from public.account_balances, which derives them from posted
 * ledger entries — there is no stored balance to display.
 */

const supabase = useSupabaseClient<Database>()
const { currentId } = useTenant()
const { t } = useI18n()

useHead({ title: () => `${t('accounts.title')} · ${t('app.name')}` })

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

const GROUP_TYPES: Array<BalanceRow['type']> = [
  'asset', 'liability', 'equity', 'revenue', 'expense',
]

const visible = computed(() =>
  (balances.value ?? []).filter(a => showArchived.value || !a.is_archived),
)

const groups = computed(() =>
  GROUP_TYPES.map((type) => {
    const rows = visible.value.filter(a => a.type === type)
    // Parents are headings; their own balance would double-count the children
    // beneath them, so the group total sums leaves only.
    const parentIds = new Set(rows.map(r => r.parent_account_id).filter(Boolean) as string[])
    const total = rows
      .filter(r => !parentIds.has(r.account_id))
      .reduce((sum, r) => sum + Number(r.balance_minor), 0)

    return { type, label: t(`accounts.groups.${type}`), rows, parentIds, total }
  }),
)

const hasAccounts = computed(() => (balances.value?.length ?? 0) > 0)
</script>

<template>
  <div class="space-y-5">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h1 class="text-2xl font-extrabold">{{ t('accounts.title') }}</h1>
      <label class="flex items-center gap-2 text-sm text-fg-muted">
        <input v-model="showArchived" type="checkbox" class="rounded-sm border-[var(--bs-border)]">
        {{ t('accounts.showArchived') }}
      </label>
    </div>

    <EmptyState
      v-if="!hasAccounts"
      :title="t('accounts.emptyTitle')"
      :description="t('accounts.emptyHint')"
    />

    <div v-else class="space-y-5">
      <section
        v-for="group in groups"
        :key="group.type"
        class="ls-card overflow-hidden"
        :aria-labelledby="`group-${group.type}`"
      >
        <div class="flex items-center justify-between border-b border-[var(--bs-border)] px-6 py-3">
          <h2 :id="`group-${group.type}`" class="text-sm font-bold">{{ group.label }}</h2>
          <MoneyText class="text-sm font-bold" :amount-minor="group.total" />
        </div>

        <div class="overflow-x-auto">
          <table class="ls-table">
            <caption class="sr-only">{{ t('accounts.caption', { group: group.label }) }}</caption>
            <thead>
              <tr>
                <th scope="col">{{ t('accounts.code') }}</th>
                <th scope="col">{{ t('accounts.account') }}</th>
                <th scope="col">{{ t('accounts.currency') }}</th>
                <th scope="col" class="text-end">{{ t('accounts.entries') }}</th>
                <th scope="col" class="text-end">{{ t('accounts.balance') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="account in group.rows" :key="account.account_id">
                <td class="font-mono text-xs text-fg-muted" dir="ltr">{{ account.code || t('common.dash') }}</td>
                <td>
                  <span :class="{ 'ps-4': account.parent_account_id, 'font-semibold': group.parentIds.has(account.account_id) }">
                    {{ account.name }}
                  </span>
                  <span v-if="account.is_archived" class="ls-badge ms-2 bg-[var(--bs-surface-muted)] text-fg-muted">
                    {{ t('accounts.archived') }}
                  </span>
                  <span v-else-if="account.is_liquid" class="ls-badge ms-2 bg-[var(--bs-info-bg)] text-[var(--bs-info)]">
                    {{ t('accounts.liquid') }}
                  </span>
                </td>
                <td class="text-fg-muted" dir="ltr">{{ account.currency }}</td>
                <td class="ls-num text-fg-muted">{{ account.entry_count }}</td>
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

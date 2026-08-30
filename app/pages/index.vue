<script setup lang="ts">
import type { Database } from '~~/types/database.types'
import type { SeriesPoint } from '~/components/RevenueExpenseChart.vue'

definePageMeta({ layout: 'default' })
useHead({ title: 'Dashboard · Ledger Suit' })

const supabase = useSupabaseClient<Database>()
const { currentId, can } = useTenant()
const { start } = useAddTransaction()

const months = ref(6)

interface Summary {
  base_currency: string
  total_assets_minor: number
  total_liabilities_minor: number
  net_worth_minor: number
  cash_and_bank_minor: number
  accounts_receivable_minor: number
  accounts_payable_minor: number
  revenue_this_month_minor: number
  expenses_this_month_minor: number
  net_profit_this_month_minor: number
  revenue_previous_month_minor: number
  expenses_previous_month_minor: number
  net_profit_previous_month_minor: number
}

// Every figure below is computed by the database. Nothing on this page
// recalculates a total from rows it fetched.
const { data: summary } = await useAsyncData<Summary | null>('org:dashboard', async () => {
  if (!currentId.value) return null
  const { data, error } = await supabase.rpc('dashboard_summary', {
    p_organization_id: currentId.value,
  })
  if (error) throw error
  return data as unknown as Summary
}, { watch: [currentId] })

const { data: series } = await useAsyncData<SeriesPoint[]>('org:dashboard-series', async () => {
  if (!currentId.value) return []
  const { data, error } = await supabase.rpc('report_monthly_series', {
    p_organization_id: currentId.value,
    p_months: months.value,
  })
  if (error) throw error
  return (data ?? []) as unknown as SeriesPoint[]
}, { watch: [currentId, months], default: () => [] })

const { data: liquid } = await useAsyncData('org:cash-position', async () => {
  if (!currentId.value) return []
  const { data, error } = await supabase
    .from('account_balances')
    .select('account_id, name, currency, balance_minor, subtype')
    .eq('organization_id', currentId.value)
    .eq('is_liquid', true)
    .eq('is_archived', false)
  if (error) throw error
  return data ?? []
}, { watch: [currentId], default: () => [] })

const { data: recent } = await useAsyncData('org:recent-transactions', async () => {
  if (!currentId.value) return []
  const { data, error } = await supabase.rpc('search_transactions', {
    p_organization_id: currentId.value,
    p_limit: 8,
  })
  if (error) throw error
  return data ?? []
}, { watch: [currentId], default: () => [] })

const hasActivity = computed(() => (recent.value?.length ?? 0) > 0)
</script>

<template>
  <div class="space-y-6">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h1 class="text-xl font-semibold">Dashboard</h1>
    </div>

    <EmptyState
      v-if="!hasActivity"
      title="Add your first transaction to start seeing your financial overview."
      description="Record an expense or some income and the figures here fill in immediately."
      :action-label="can('transactions.create') ? 'Add a transaction' : undefined"
      @action="start('expense')"
    />

    <template v-else>
      <section aria-labelledby="kpis" class="space-y-3">
        <h2 id="kpis" class="sr-only">Key figures</h2>
        <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <KpiCard title="Total assets" :amount-minor="summary?.total_assets_minor" good-direction="neutral" />
          <KpiCard title="Total liabilities" :amount-minor="summary?.total_liabilities_minor" good-direction="neutral" />
          <KpiCard title="Net worth" :amount-minor="summary?.net_worth_minor" good-direction="neutral" hint="Assets − liabilities" />
          <KpiCard title="Cash and bank" :amount-minor="summary?.cash_and_bank_minor" good-direction="neutral" />
          <KpiCard
            title="Revenue this month"
            :amount-minor="summary?.revenue_this_month_minor"
            :previous-minor="summary?.revenue_previous_month_minor"
            good-direction="up"
          />
          <KpiCard
            title="Expenses this month"
            :amount-minor="summary?.expenses_this_month_minor"
            :previous-minor="summary?.expenses_previous_month_minor"
            good-direction="down"
          />
          <KpiCard
            title="Net profit this month"
            :amount-minor="summary?.net_profit_this_month_minor"
            :previous-minor="summary?.net_profit_previous_month_minor"
            good-direction="up"
          />
          <KpiCard
            title="Receivable / payable"
            :amount-minor="summary?.accounts_receivable_minor"
            good-direction="neutral"
            :hint="`Owed to you. Payable: ${formatMoney(summary?.accounts_payable_minor ?? 0, summary?.base_currency ?? 'EGP')}`"
          />
        </div>
      </section>

      <div class="grid gap-6 xl:grid-cols-3">
        <section class="ls-card p-5 xl:col-span-2" aria-labelledby="chart-heading">
          <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
            <h2 id="chart-heading" class="text-base font-semibold">Revenue vs expenses</h2>
            <div class="flex gap-1" role="group" aria-label="Chart range">
              <button
                v-for="option in [3, 6, 12]"
                :key="option"
                type="button"
                class="ls-btn ls-btn-sm"
                :class="{ 'ls-btn-primary': months === option }"
                :aria-pressed="months === option"
                @click="months = option"
              >
                {{ option }}m
              </button>
            </div>
          </div>
          <RevenueExpenseChart :series="series ?? []" />
        </section>

        <section class="ls-card p-5" aria-labelledby="cash-heading">
          <h2 id="cash-heading" class="mb-4 text-base font-semibold">Cash position</h2>
          <table v-if="liquid?.length" class="ls-table">
            <caption class="sr-only">Balances of cash, bank and wallet accounts</caption>
            <tbody>
              <tr v-for="(account, index) in liquid" :key="account.account_id ?? index">
                <td>{{ account.name }}</td>
                <td class="ls-num">
                  <MoneyText :amount-minor="account.balance_minor" :currency="account.currency" />
                </td>
              </tr>
            </tbody>
          </table>
          <p v-else class="text-sm text-neutral-500">No liquid accounts yet.</p>
        </section>
      </div>

      <section class="ls-card overflow-hidden" aria-labelledby="recent-heading">
        <div class="flex items-center justify-between px-5 py-4">
          <h2 id="recent-heading" class="text-base font-semibold">Recent transactions</h2>
          <NuxtLink to="/transactions" class="text-sm text-accent-700 hover:underline dark:text-accent-100">
            View all
          </NuxtLink>
        </div>
        <div class="overflow-x-auto">
          <table class="ls-table">
            <thead>
              <tr>
                <th scope="col">Date</th>
                <th scope="col">Description</th>
                <th scope="col">Category</th>
                <th scope="col">Account</th>
                <th scope="col">Status</th>
                <th scope="col" class="text-right">Amount</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in recent" :key="row.id">
                <td class="whitespace-nowrap">{{ row.transaction_date }}</td>
                <td class="max-w-64 truncate">{{ row.description || '—' }}</td>
                <td>{{ row.category_name || '—' }}</td>
                <td class="whitespace-nowrap text-neutral-500">
                  {{ row.from_account_name }} → {{ row.to_account_name }}
                </td>
                <td><StatusBadge :status="row.status" /></td>
                <td class="ls-num">
                  <MoneyText :amount-minor="row.amount_minor" :currency="row.currency_code" />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>
  </div>
</template>

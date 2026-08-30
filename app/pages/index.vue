<script setup lang="ts">
import type { Database } from '~~/types/database.types'
import type { SeriesPoint } from '~/components/RevenueExpenseChart.vue'

definePageMeta({ layout: 'default' })

const supabase = useSupabaseClient<Database>()
const { currentId, can, baseCurrency } = useTenant()
const { start } = useAddTransaction()
const { t, locale } = useI18n()

useHead({ title: () => `${t('dashboard.title')} · ${t('app.name')}` })

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

const payableHint = computed(() =>
  t('dashboard.payableHint', {
    amount: formatMoney(summary.value?.accounts_payable_minor ?? 0, baseCurrency.value, locale.value),
  }),
)
</script>

<template>
  <div class="space-y-8">
    <h1 class="text-2xl font-extrabold">{{ t('dashboard.title') }}</h1>

    <EmptyState
      v-if="!hasActivity"
      :title="t('dashboard.emptyTitle')"
      :description="t('dashboard.emptyHint')"
      :action-label="can('transactions.create') ? t('dashboard.emptyAction') : undefined"
      @action="start('expense')"
    />

    <template v-else>
      <section aria-labelledby="kpis" class="space-y-3">
        <h2 id="kpis" class="sr-only">{{ t('dashboard.kpis') }}</h2>
        <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <KpiCard :title="t('dashboard.totalAssets')" :amount-minor="summary?.total_assets_minor" good-direction="neutral" />
          <KpiCard :title="t('dashboard.totalLiabilities')" :amount-minor="summary?.total_liabilities_minor" good-direction="neutral" />
          <KpiCard :title="t('dashboard.netWorth')" :amount-minor="summary?.net_worth_minor" good-direction="neutral" :hint="t('dashboard.netWorthHint')" />
          <KpiCard :title="t('dashboard.cashAndBank')" :amount-minor="summary?.cash_and_bank_minor" good-direction="neutral" />
          <KpiCard
            :title="t('dashboard.revenueThisMonth')"
            :amount-minor="summary?.revenue_this_month_minor"
            :previous-minor="summary?.revenue_previous_month_minor"
            good-direction="up"
          />
          <KpiCard
            :title="t('dashboard.expensesThisMonth')"
            :amount-minor="summary?.expenses_this_month_minor"
            :previous-minor="summary?.expenses_previous_month_minor"
            good-direction="down"
          />
          <KpiCard
            :title="t('dashboard.netProfitThisMonth')"
            :amount-minor="summary?.net_profit_this_month_minor"
            :previous-minor="summary?.net_profit_previous_month_minor"
            good-direction="up"
          />
          <KpiCard
            :title="t('dashboard.receivable')"
            :amount-minor="summary?.accounts_receivable_minor"
            good-direction="neutral"
            :hint="payableHint"
          />
        </div>
      </section>

      <div class="grid gap-6 xl:grid-cols-3">
        <section class="ls-card min-w-0 p-6 xl:col-span-2" aria-labelledby="chart-heading">
          <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
            <h2 id="chart-heading" class="text-base font-bold">{{ t('dashboard.revenueVsExpenses') }}</h2>
            <div class="flex gap-1" role="group" :aria-label="t('dashboard.chartRange')">
              <button
                v-for="option in [3, 6, 12]"
                :key="option"
                type="button"
                class="ls-btn ls-btn-sm"
                :class="{ 'ls-btn-primary': months === option }"
                :aria-pressed="months === option"
                @click="months = option"
              >
                {{ t('dashboard.months', { count: option }) }}
              </button>
            </div>
          </div>
          <RevenueExpenseChart :series="series ?? []" />
        </section>

        <section class="ls-card min-w-0 p-6" aria-labelledby="cash-heading">
          <h2 id="cash-heading" class="mb-4 text-base font-bold">{{ t('dashboard.cashPosition') }}</h2>
          <table v-if="liquid?.length" class="ls-table">
            <caption class="sr-only">{{ t('dashboard.cashPositionCaption') }}</caption>
            <tbody>
              <tr v-for="(account, index) in liquid" :key="account.account_id ?? index">
                <td>{{ account.name }}</td>
                <td class="ls-num">
                  <MoneyText :amount-minor="account.balance_minor" :currency="account.currency" />
                </td>
              </tr>
            </tbody>
          </table>
          <p v-else class="text-sm text-fg-muted">{{ t('dashboard.noLiquidAccounts') }}</p>
        </section>
      </div>

      <section class="ls-card overflow-hidden" aria-labelledby="recent-heading">
        <div class="flex items-center justify-between px-6 py-4">
          <h2 id="recent-heading" class="text-base font-bold">{{ t('dashboard.recent') }}</h2>
          <NuxtLink to="/transactions" class="text-sm font-semibold text-link hover:underline">
            {{ t('dashboard.viewAll') }}
          </NuxtLink>
        </div>
        <div class="overflow-x-auto">
          <table class="ls-table">
            <thead>
              <tr>
                <th scope="col">{{ t('transactions.date') }}</th>
                <th scope="col">{{ t('transactions.description') }}</th>
                <th scope="col">{{ t('transactions.category') }}</th>
                <th scope="col">{{ t('transactions.account') }}</th>
                <th scope="col">{{ t('transactions.status') }}</th>
                <th scope="col" class="text-end">{{ t('transactions.amount') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in recent" :key="row.id">
                <td class="whitespace-nowrap">{{ formatDate(row.transaction_date, locale) }}</td>
                <td class="max-w-64 truncate">{{ row.description || t('common.dash') }}</td>
                <td>{{ row.category_name || t('common.dash') }}</td>
                <td class="whitespace-nowrap text-fg-muted">
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

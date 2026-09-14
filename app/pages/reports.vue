<script setup lang="ts">
import type { Database } from '~~/types/database.types'

definePageMeta({ layout: 'default' })

/**
 * One page, five tabs. Every figure is produced by a database function reading
 * posted ledger entries — drafts and scheduled transactions never appear here.
 */

const supabase = useSupabaseClient<Database>()
const route = useRoute()
const router = useRouter()
const { currentId, baseCurrency, can } = useTenant()
const { t, locale } = useI18n()

useHead({ title: () => `${t('reports.title')} · ${t('app.name')}` })

const TABS = [
  { key: 'overview', labelKey: 'reports.tabs.overview' },
  { key: 'profit-loss', labelKey: 'reports.tabs.profitLoss' },
  { key: 'balance-sheet', labelKey: 'reports.tabs.balanceSheet' },
  { key: 'cash-flow', labelKey: 'reports.tabs.cashFlow' },
  { key: 'ledger', labelKey: 'reports.tabs.ledger' },
] as const

type TabKey = (typeof TABS)[number]['key']

const tab = computed<TabKey>(() => {
  const requested = String(route.query.tab ?? 'overview')
  return (TABS.some(item => item.key === requested) ? requested : 'overview') as TabKey
})

function selectTab(key: TabKey) {
  router.replace({ query: { ...route.query, tab: key } })
}

// Default range: the year to date, which is what people check most often.
const now = new Date()
const from = ref(`${now.getFullYear()}-01-01`)
const to = ref(now.toISOString().slice(0, 10))
const asOf = ref(now.toISOString().slice(0, 10))

const { data: accounts } = useOrgAccounts()
const ledgerAccountId = ref<string>('')

watchEffect(() => {
  if (!ledgerAccountId.value && accounts.value?.length) {
    ledgerAccountId.value = accounts.value.find(a => a.system_key === 'bank')?.id
      ?? accounts.value[0]!.id
  }
})

interface ReportRow {
  section: string
  account_id: string | null
  code: string | null
  name: string
  amount_minor: number
}

const { data: profitLoss, pending: profitLossPending } = useLazyAsyncData<ReportRow[]>('org:report-pl', async () => {
  if (!currentId.value) return []
  const { data, error } = await supabase.rpc('report_profit_and_loss', {
    p_organization_id: currentId.value,
    p_from_date: from.value,
    p_to_date: to.value,
  })
  if (error) throw error
  return (data ?? []) as ReportRow[]
}, { watch: [currentId, from, to], default: () => [] })

const { data: balanceSheet, pending: balanceSheetPending } = useLazyAsyncData<ReportRow[]>('org:report-bs', async () => {
  if (!currentId.value) return []
  const { data, error } = await supabase.rpc('report_balance_sheet', {
    p_organization_id: currentId.value,
    p_as_of_date: asOf.value,
  })
  if (error) throw error
  return (data ?? []) as ReportRow[]
}, { watch: [currentId, asOf], default: () => [] })

const { data: integrity } = useLazyAsyncData('org:report-integrity', async () => {
  if (!currentId.value) return null
  const { data, error } = await supabase.rpc('check_balance_sheet_integrity', {
    p_organization_id: currentId.value,
    p_as_of_date: asOf.value,
  })
  if (error) throw error
  return data as unknown as Record<string, number | boolean | string>
}, { watch: [currentId, asOf] })

const { data: cashFlow, pending: cashFlowPending } = useLazyAsyncData('org:report-cf', async () => {
  if (!currentId.value) return []
  const { data, error } = await supabase.rpc('report_cash_flow', {
    p_organization_id: currentId.value,
    p_from_date: from.value,
    p_to_date: to.value,
  })
  if (error) throw error
  return data ?? []
}, { watch: [currentId, from, to], default: () => [] })

const { data: ledger, pending: ledgerPending } = useLazyAsyncData('org:report-ledger', async () => {
  if (!currentId.value || !ledgerAccountId.value) return []
  const { data, error } = await supabase.rpc('report_general_ledger', {
    p_organization_id: currentId.value,
    p_account_id: ledgerAccountId.value,
    p_from_date: from.value,
    p_to_date: to.value,
  })
  if (error) throw error
  return data ?? []
}, { watch: [currentId, ledgerAccountId, from, to], default: () => [] })

const { data: trialBalance, pending: trialBalancePending } = useLazyAsyncData('org:report-tb', async () => {
  if (!currentId.value) return []
  const { data, error } = await supabase.rpc('report_trial_balance', {
    p_organization_id: currentId.value,
    p_as_of_date: asOf.value,
  })
  if (error) throw error
  return data ?? []
}, { watch: [currentId, asOf], default: () => [] })

function sectionTotal(rows: ReportRow[] | null, section: string) {
  return (rows ?? [])
    .filter(r => r.section === section)
    .reduce((sum, r) => sum + Number(r.amount_minor), 0)
}

const revenue = computed(() => sectionTotal(profitLoss.value, 'revenue'))
const costOfSales = computed(() => sectionTotal(profitLoss.value, 'cost_of_sales'))
const operatingExpenses = computed(() => sectionTotal(profitLoss.value, 'operating_expenses'))
const netProfit = computed(() => revenue.value - costOfSales.value - operatingExpenses.value)

const assets = computed(() => sectionTotal(balanceSheet.value, 'asset'))
const liabilities = computed(() => sectionTotal(balanceSheet.value, 'liability'))
const equity = computed(() => sectionTotal(balanceSheet.value, 'equity'))

const trialTotals = computed(() => {
  const rows = (trialBalance.value ?? []) as Array<{ debit_minor: number, credit_minor: number }>
  return {
    debit: rows.reduce((s, r) => s + Number(r.debit_minor), 0),
    credit: rows.reduce((s, r) => s + Number(r.credit_minor), 0),
  }
})

const plSections = [
  { key: 'revenue', labelKey: 'reports.revenue' },
  { key: 'cost_of_sales', labelKey: 'reports.costOfSales' },
  { key: 'operating_expenses', labelKey: 'reports.operatingExpenses' },
]

const bsSections = [
  { key: 'asset', labelKey: 'reports.assets' },
  { key: 'liability', labelKey: 'reports.liabilities' },
  { key: 'equity', labelKey: 'reports.equity' },
]

function rowsIn(rows: ReportRow[] | null, section: string) {
  return (rows ?? []).filter(r => r.section === section)
}

const exportPending = ref(false)
const exportError = ref('')

function downloadCsv(filename: string, csv: string) {
  const url = URL.createObjectURL(new Blob([`\uFEFF${csv}`], { type: 'text/csv;charset=utf-8' }))
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  link.click()
  URL.revokeObjectURL(url)
}

async function exportReport(report: 'profit_loss' | 'balance_sheet' | 'trial_balance' | 'cash_flow' | 'general_ledger') {
  if (!currentId.value || exportPending.value) return
  exportPending.value = true
  exportError.value = ''
  try {
    const { data, error } = await supabase.rpc('export_financial_report_csv', {
      p_organization_id: currentId.value,
      p_report: report,
      p_from_date: ['profit_loss', 'cash_flow', 'general_ledger'].includes(report) ? from.value : undefined,
      p_to_date: ['profit_loss', 'cash_flow', 'general_ledger'].includes(report) ? to.value : undefined,
      p_as_of_date: ['balance_sheet', 'trial_balance'].includes(report) ? asOf.value : undefined,
      p_account_id: report === 'general_ledger' ? ledgerAccountId.value : undefined,
    })
    if (error) throw error
    const filenames = {
      profit_loss: `profit-and-loss-${from.value}-to-${to.value}.csv`,
      balance_sheet: `balance-sheet-${asOf.value}.csv`,
      trial_balance: `trial-balance-${asOf.value}.csv`,
      cash_flow: `cash-flow-${from.value}-to-${to.value}.csv`,
      general_ledger: `general-ledger-${from.value}-to-${to.value}.csv`,
    }
    downloadCsv(filenames[report], data)
  }
  catch {
    exportError.value = t('reports.exportFailed')
  }
  finally {
    exportPending.value = false
  }
}
</script>

<template>
  <div class="space-y-6">
    <div>
      <h1 class="text-h1 font-bold">{{ t('reports.title') }}</h1>
      <p class="mt-1 text-sm text-fg-muted">{{ t('reports.csvExports') }}</p>
    </div>

    <p v-if="exportError" class="ls-error" role="alert">{{ exportError }}</p>

    <div class="flex gap-1 border-b border-[var(--bs-border)]" role="tablist">
      <button
        v-for="item in TABS"
        :key="item.key"
        type="button"
        role="tab"
        :aria-selected="tab === item.key"
        class="ls-tab -mb-px"
        :class="{ 'ls-tab-active': tab === item.key }"
        @click="selectTab(item.key)"
      >
        {{ t(item.labelKey) }}
      </button>
    </div>

    <div class="flex flex-wrap items-end gap-3">
      <template v-if="['profit-loss', 'cash-flow', 'ledger'].includes(tab)">
        <FloatingField :label="t('reports.from')"><input id="from" v-model="from" type="date" class="ls-input"></FloatingField>
        <FloatingField :label="t('reports.to')"><input id="to" v-model="to" type="date" class="ls-input"></FloatingField>
      </template>
      <FloatingField v-else :label="t('reports.asOf')"><input id="asof" v-model="asOf" type="date" class="ls-input"></FloatingField>

      <FloatingField v-if="tab === 'ledger'" class="min-w-56" :label="t('reports.account')">
        <select id="ledger-account" v-model="ledgerAccountId" class="ls-input">
          <option v-for="a in accounts" :key="a.id" :value="a.id">
            {{ a.code ? `${a.code} · ` : '' }}{{ a.name }}
          </option>
        </select>
      </FloatingField>
    </div>

    <!-- Overview -->
    <section v-if="tab === 'overview'" class="space-y-4" role="tabpanel" :aria-label="t('reports.tabs.overview')">
      <div
        v-if="integrity && integrity.balanced === false"
        class="rounded-control border border-[var(--bs-status-error)] bg-[var(--bs-status-error-bg)] px-4 py-3 text-sm text-[var(--bs-status-error)]"
        role="alert"
      >
        <p class="font-bold">{{ t('reports.integrityTitle') }}</p>
        <p class="mt-1">
          {{ t('reports.integrityBody', {
            difference: formatMoney(Number(integrity.difference_minor), baseCurrency, locale),
          }) }}
        </p>
      </div>

      <SectionSkeleton v-if="balanceSheetPending || profitLossPending" variant="cards" />
      <div v-else class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard :title="t('reports.assets')" :amount-minor="assets" good-direction="neutral" />
        <KpiCard :title="t('reports.liabilities')" :amount-minor="liabilities" good-direction="neutral" />
        <KpiCard :title="t('reports.equity')" :amount-minor="equity" good-direction="neutral" />
        <KpiCard :title="t('reports.netProfitPeriod')" :amount-minor="netProfit" good-direction="neutral" />
      </div>

      <SectionSkeleton v-if="trialBalancePending" variant="table" :rows="7" />
      <section v-else class="ls-card overflow-hidden" aria-labelledby="tb-heading">
        <div class="flex flex-wrap items-center justify-between gap-3 px-6 py-4">
          <h2 id="tb-heading" class="text-base font-bold">{{ t('reports.trialBalance') }}</h2>
          <div class="flex items-center gap-3">
            <p class="text-sm font-semibold" :class="trialTotals.debit === trialTotals.credit ? 'text-[var(--bs-status-success)]' : 'text-[var(--bs-status-error)]'">
              {{ trialTotals.debit === trialTotals.credit ? t('reports.inBalance') : t('reports.outOfBalance') }}
            </p>
            <button v-if="can('reports.export')" type="button" class="ls-btn ls-btn-sm" :disabled="exportPending" @click="exportReport('trial_balance')">{{ t('common.exportCsv') }}</button>
          </div>
        </div>
        <div class="overflow-x-auto">
          <table class="ls-table">
            <thead>
              <tr>
                <th scope="col">{{ t('accounts.code') }}</th>
                <th scope="col">{{ t('reports.account') }}</th>
                <th scope="col" class="text-end">{{ t('detail.debit') }}</th>
                <th scope="col" class="text-end">{{ t('detail.credit') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in trialBalance" :key="row.account_id">
                <td class="font-mono text-xs text-fg-muted" dir="ltr">{{ row.code || t('common.dash') }}</td>
                <td>{{ row.name }}</td>
                <td class="ls-num"><MoneyText :amount-minor="row.debit_minor" /></td>
                <td class="ls-num"><MoneyText :amount-minor="row.credit_minor" /></td>
              </tr>
            </tbody>
            <tfoot>
              <tr class="font-bold">
                <td colspan="2">{{ t('reports.total') }}</td>
                <td class="ls-num"><MoneyText :amount-minor="trialTotals.debit" /></td>
                <td class="ls-num"><MoneyText :amount-minor="trialTotals.credit" /></td>
              </tr>
            </tfoot>
          </table>
        </div>
      </section>
    </section>

    <!-- Profit & Loss -->
    <section v-else-if="tab === 'profit-loss'" class="space-y-4" role="tabpanel" :aria-label="t('reports.tabs.profitLoss')">
      <div class="flex justify-end">
        <button v-if="can('reports.export')" type="button" class="ls-btn" :disabled="exportPending" @click="exportReport('profit_loss')">{{ t('common.exportCsv') }}</button>
      </div>

      <SectionSkeleton v-if="profitLossPending" variant="table" :rows="7" />

      <EmptyState
        v-else-if="!profitLoss?.length"
        :title="t('reports.emptyTitle')"
        :description="t('reports.emptyRange')"
      />

      <div v-else class="ls-card overflow-hidden">
        <table class="ls-table">
          <caption class="sr-only">{{ t('reports.tabs.profitLoss') }}</caption>
          <tbody>
            <template v-for="section in plSections" :key="section.key">
              <tr v-if="rowsIn(profitLoss, section.key).length" class="bg-surface-muted">
                <th scope="colgroup">{{ t(section.labelKey) }}</th>
                <td class="ls-num font-bold">
                  <MoneyText :amount-minor="sectionTotal(profitLoss, section.key)" />
                </td>
              </tr>
              <tr v-for="row in rowsIn(profitLoss, section.key)" :key="row.account_id ?? row.name">
                <td class="ps-8">{{ row.name }}</td>
                <td class="ls-num"><MoneyText :amount-minor="row.amount_minor" /></td>
              </tr>
            </template>
          </tbody>
          <tfoot>
            <tr class="text-base font-bold">
              <td>{{ t('reports.netProfit') }}</td>
              <td class="ls-num"><MoneyText :amount-minor="netProfit" signed /></td>
            </tr>
          </tfoot>
        </table>
      </div>
    </section>

    <!-- Balance sheet -->
    <section v-else-if="tab === 'balance-sheet'" class="space-y-4" role="tabpanel" :aria-label="t('reports.tabs.balanceSheet')">
      <div class="flex justify-end">
        <button v-if="can('reports.export')" type="button" class="ls-btn" :disabled="exportPending" @click="exportReport('balance_sheet')">{{ t('common.exportCsv') }}</button>
      </div>

      <SectionSkeleton v-if="balanceSheetPending" variant="table" :rows="7" />

      <EmptyState
        v-else-if="!balanceSheet?.length"
        :title="t('reports.emptyTitle')"
        :description="t('reports.emptyAsOf')"
      />

      <template v-else>
        <div class="ls-card overflow-hidden">
          <table class="ls-table">
            <caption class="sr-only">{{ t('reports.tabs.balanceSheet') }}</caption>
            <tbody>
              <template v-for="section in bsSections" :key="section.key">
                <tr v-if="rowsIn(balanceSheet, section.key).length" class="bg-surface-muted">
                  <th scope="colgroup">{{ t(section.labelKey) }}</th>
                  <td class="ls-num font-bold">
                    <MoneyText :amount-minor="sectionTotal(balanceSheet, section.key)" />
                  </td>
                </tr>
                <tr v-for="row in rowsIn(balanceSheet, section.key)" :key="row.account_id ?? row.name">
                  <td class="ps-8">{{ row.name }}</td>
                  <td class="ls-num"><MoneyText :amount-minor="row.amount_minor" /></td>
                </tr>
              </template>
            </tbody>
          </table>
        </div>

        <p class="text-sm" :class="assets === liabilities + equity ? 'text-fg-muted' : 'text-[var(--bs-status-error)]'">
          {{ t('reports.equation', {
            assets: formatMoney(assets, baseCurrency, locale),
            liabilities: formatMoney(liabilities, baseCurrency, locale),
            equity: formatMoney(equity, baseCurrency, locale),
          }) }}
        </p>
      </template>
    </section>

    <!-- Cash flow -->
    <section v-else-if="tab === 'cash-flow'" class="space-y-4" role="tabpanel" :aria-label="t('reports.tabs.cashFlow')">
      <div class="flex justify-end">
        <button v-if="can('reports.export')" type="button" class="ls-btn" :disabled="exportPending" @click="exportReport('cash_flow')">{{ t('common.exportCsv') }}</button>
      </div>
      <SectionSkeleton v-if="cashFlowPending" variant="table" :rows="5" />

      <EmptyState
        v-else-if="!cashFlow?.length"
        :title="t('reports.emptyCashTitle')"
        :description="t('reports.emptyCashHint')"
      />

      <div v-else class="ls-card overflow-hidden">
        <table class="ls-table">
          <caption class="sr-only">{{ t('reports.tabs.cashFlow') }}</caption>
          <thead>
            <tr>
              <th scope="col">{{ t('reports.activity') }}</th>
              <th scope="col" class="text-end">{{ t('reports.netMovement') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in cashFlow" :key="row.section">
              <td>{{ t(`reports.cashFlowSections.${row.section}`) }}</td>
              <td class="ls-num"><MoneyText :amount-minor="row.amount_minor" signed explicit-sign /></td>
            </tr>
          </tbody>
          <tfoot>
            <tr class="font-bold">
              <td>{{ t('reports.netChangeInCash') }}</td>
              <td class="ls-num">
                <MoneyText
                  :amount-minor="cashFlow.reduce((s, r) => s + Number(r.amount_minor), 0)"
                  signed
                  explicit-sign
                />
              </td>
            </tr>
          </tfoot>
        </table>
      </div>
    </section>

    <!-- General ledger -->
    <section v-else class="space-y-4" role="tabpanel" :aria-label="t('reports.tabs.ledger')">
      <div class="flex justify-end">
        <button v-if="can('reports.export')" type="button" class="ls-btn" :disabled="exportPending || !ledgerAccountId" @click="exportReport('general_ledger')">{{ t('common.exportCsv') }}</button>
      </div>
      <SectionSkeleton v-if="ledgerPending" variant="table" :rows="8" />

      <EmptyState
        v-else-if="!ledger?.length"
        :title="t('reports.emptyLedgerTitle')"
        :description="t('reports.emptyLedgerHint')"
      />

      <div v-else class="ls-card overflow-x-auto">
        <table class="ls-table">
          <caption class="sr-only">{{ t('reports.tabs.ledger') }}</caption>
          <thead>
            <tr>
              <th scope="col">{{ t('transactions.date') }}</th>
              <th scope="col">{{ t('transactions.reference') }}</th>
              <th scope="col">{{ t('transactions.description') }}</th>
              <th scope="col" class="text-end">{{ t('detail.debit') }}</th>
              <th scope="col" class="text-end">{{ t('detail.credit') }}</th>
              <th scope="col" class="text-end">{{ t('reports.runningBalance') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in ledger" :key="row.entry_id">
              <td class="whitespace-nowrap">{{ formatDate(row.entry_date, locale) }}</td>
              <td class="text-fg-muted">{{ row.reference || t('common.dash') }}</td>
              <td class="max-w-64 truncate">{{ row.description || row.memo || t('common.dash') }}</td>
              <td class="ls-num">
                <MoneyText v-if="Number(row.debit_minor)" :amount-minor="row.debit_minor" />
                <span v-else class="text-fg-disabled">{{ t('common.dash') }}</span>
              </td>
              <td class="ls-num">
                <MoneyText v-if="Number(row.credit_minor)" :amount-minor="row.credit_minor" />
                <span v-else class="text-neutral-300">—</span>
              </td>
              <td class="ls-num font-semibold">
                <MoneyText :amount-minor="row.running_balance_minor" />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>

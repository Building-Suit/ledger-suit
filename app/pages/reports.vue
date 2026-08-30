<script setup lang="ts">
import type { Database } from '~~/types/database.types'

definePageMeta({ layout: 'default' })
useHead({ title: 'Reports · Ledger Suit' })

/**
 * One page, five tabs. Every figure is produced by a database function reading
 * posted ledger entries — drafts and scheduled transactions never appear here.
 */

const supabase = useSupabaseClient<Database>()
const route = useRoute()
const router = useRouter()
const { currentId, baseCurrency } = useTenant()

const TABS = [
  { key: 'overview', label: 'Overview' },
  { key: 'profit-loss', label: 'Profit & Loss' },
  { key: 'balance-sheet', label: 'Balance Sheet' },
  { key: 'cash-flow', label: 'Cash Flow' },
  { key: 'ledger', label: 'Ledger' },
] as const

type TabKey = (typeof TABS)[number]['key']

const tab = computed<TabKey>(() => {
  const requested = String(route.query.tab ?? 'overview')
  return (TABS.some(t => t.key === requested) ? requested : 'overview') as TabKey
})

function selectTab(key: TabKey) {
  router.replace({ query: { ...route.query, tab: key } })
}

// Default range: the year to date, which is what people check most often.
const now = new Date()
const from = ref(`${now.getFullYear()}-01-01`)
const to = ref(now.toISOString().slice(0, 10))
const asOf = ref(now.toISOString().slice(0, 10))

const { data: accounts } = await useOrgAccounts()
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

const { data: profitLoss } = await useAsyncData<ReportRow[]>('org:report-pl', async () => {
  if (!currentId.value) return []
  const { data, error } = await supabase.rpc('report_profit_and_loss', {
    p_organization_id: currentId.value,
    p_from_date: from.value,
    p_to_date: to.value,
  })
  if (error) throw error
  return (data ?? []) as ReportRow[]
}, { watch: [currentId, from, to], default: () => [] })

const { data: balanceSheet } = await useAsyncData<ReportRow[]>('org:report-bs', async () => {
  if (!currentId.value) return []
  const { data, error } = await supabase.rpc('report_balance_sheet', {
    p_organization_id: currentId.value,
    p_as_of_date: asOf.value,
  })
  if (error) throw error
  return (data ?? []) as ReportRow[]
}, { watch: [currentId, asOf], default: () => [] })

const { data: integrity } = await useAsyncData('org:report-integrity', async () => {
  if (!currentId.value) return null
  const { data, error } = await supabase.rpc('check_balance_sheet_integrity', {
    p_organization_id: currentId.value,
    p_as_of_date: asOf.value,
  })
  if (error) throw error
  return data as unknown as Record<string, number | boolean | string>
}, { watch: [currentId, asOf] })

const { data: cashFlow } = await useAsyncData('org:report-cf', async () => {
  if (!currentId.value) return []
  const { data, error } = await supabase.rpc('report_cash_flow', {
    p_organization_id: currentId.value,
    p_from_date: from.value,
    p_to_date: to.value,
  })
  if (error) throw error
  return data ?? []
}, { watch: [currentId, from, to], default: () => [] })

const { data: ledger } = await useAsyncData('org:report-ledger', async () => {
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

const { data: trialBalance } = await useAsyncData('org:report-tb', async () => {
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
  { key: 'revenue', label: 'Revenue' },
  { key: 'cost_of_sales', label: 'Cost of sales' },
  { key: 'operating_expenses', label: 'Operating expenses' },
]

const bsSections = [
  { key: 'asset', label: 'Assets' },
  { key: 'liability', label: 'Liabilities' },
  { key: 'equity', label: 'Equity' },
]

function rowsIn(rows: ReportRow[] | null, section: string) {
  return (rows ?? []).filter(r => r.section === section)
}

/** Exports what is on screen. The figures came from the database; this only
 *  serialises them. */
function exportCsv(filename: string, header: string[], lines: (string | number)[][]) {
  const escape = (value: string | number) => {
    const text = String(value ?? '')
    return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text
  }
  const csv = [header, ...lines].map(row => row.map(escape).join(',')).join('\n')
  const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }))
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  link.click()
  URL.revokeObjectURL(url)
}

function exportProfitLoss() {
  exportCsv(
    `profit-and-loss-${from.value}-to-${to.value}.csv`,
    ['Section', 'Code', 'Account', `Amount (${baseCurrency.value})`],
    (profitLoss.value ?? []).map(r => [r.section, r.code ?? '', r.name, formatMoney(r.amount_minor, baseCurrency.value)]),
  )
}

function exportBalanceSheet() {
  exportCsv(
    `balance-sheet-${asOf.value}.csv`,
    ['Section', 'Code', 'Account', `Amount (${baseCurrency.value})`],
    (balanceSheet.value ?? []).map(r => [r.section, r.code ?? '', r.name, formatMoney(r.amount_minor, baseCurrency.value)]),
  )
}

const cashFlowLabels: Record<string, string> = {
  operating: 'Operating activities',
  investing: 'Investing activities',
  financing: 'Financing activities',
  none: 'Unclassified',
}
</script>

<template>
  <div class="space-y-5">
    <h1 class="text-xl font-semibold">Reports</h1>

    <div class="flex gap-1 overflow-x-auto border-b border-neutral-200 dark:border-neutral-800" role="tablist">
      <button
        v-for="item in TABS"
        :key="item.key"
        type="button"
        role="tab"
        :aria-selected="tab === item.key"
        class="-mb-px border-b-2 px-3 py-2 text-sm font-medium whitespace-nowrap"
        :class="tab === item.key
          ? 'border-neutral-900 text-neutral-900 dark:border-white dark:text-white'
          : 'border-transparent text-neutral-500 hover:text-neutral-800 dark:hover:text-neutral-200'"
        @click="selectTab(item.key)"
      >
        {{ item.label }}
      </button>
    </div>

    <div class="flex flex-wrap items-end gap-3">
      <template v-if="['profit-loss', 'cash-flow', 'ledger'].includes(tab)">
        <div>
          <label class="ls-label" for="from">From</label>
          <input id="from" v-model="from" type="date" class="ls-input">
        </div>
        <div>
          <label class="ls-label" for="to">To</label>
          <input id="to" v-model="to" type="date" class="ls-input">
        </div>
      </template>
      <div v-else>
        <label class="ls-label" for="asof">As of</label>
        <input id="asof" v-model="asOf" type="date" class="ls-input">
      </div>

      <div v-if="tab === 'ledger'" class="min-w-56">
        <label class="ls-label" for="ledger-account">Account</label>
        <select id="ledger-account" v-model="ledgerAccountId" class="ls-input">
          <option v-for="a in accounts" :key="a.id" :value="a.id">
            {{ a.code ? `${a.code} · ` : '' }}{{ a.name }}
          </option>
        </select>
      </div>
    </div>

    <!-- Overview -->
    <section v-if="tab === 'overview'" class="space-y-4" role="tabpanel" aria-label="Overview">
      <div
        v-if="integrity && integrity.balanced === false"
        class="rounded-lg border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800 dark:border-red-500/40 dark:bg-red-500/10 dark:text-red-300"
        role="alert"
      >
        <p class="font-semibold">Accounting integrity failure</p>
        <p class="mt-1">
          Assets do not equal liabilities plus equity. The difference is
          <MoneyText :amount-minor="Number(integrity.difference_minor)" />.
          This is a defect, not a rounding artefact — report it before relying on
          any figure on this page.
        </p>
      </div>

      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard title="Assets" :amount-minor="assets" good-direction="neutral" />
        <KpiCard title="Liabilities" :amount-minor="liabilities" good-direction="neutral" />
        <KpiCard title="Equity" :amount-minor="equity" good-direction="neutral" />
        <KpiCard title="Net profit (period)" :amount-minor="netProfit" good-direction="neutral" />
      </div>

      <section class="ls-card overflow-hidden" aria-labelledby="tb-heading">
        <div class="flex items-center justify-between px-5 py-4">
          <h2 id="tb-heading" class="text-base font-semibold">Trial balance</h2>
          <p class="text-sm" :class="trialTotals.debit === trialTotals.credit ? 'text-emerald-700 dark:text-emerald-400' : 'text-red-700 dark:text-red-400'">
            {{ trialTotals.debit === trialTotals.credit ? 'In balance' : 'Out of balance' }}
          </p>
        </div>
        <div class="overflow-x-auto">
          <table class="ls-table">
            <thead>
              <tr>
                <th scope="col">Code</th>
                <th scope="col">Account</th>
                <th scope="col" class="text-right">Debit</th>
                <th scope="col" class="text-right">Credit</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in trialBalance" :key="row.account_id">
                <td class="font-mono text-xs text-neutral-500">{{ row.code || '—' }}</td>
                <td>{{ row.name }}</td>
                <td class="ls-num"><MoneyText :amount-minor="row.debit_minor" /></td>
                <td class="ls-num"><MoneyText :amount-minor="row.credit_minor" /></td>
              </tr>
            </tbody>
            <tfoot>
              <tr class="font-semibold">
                <td colspan="2">Total</td>
                <td class="ls-num"><MoneyText :amount-minor="trialTotals.debit" /></td>
                <td class="ls-num"><MoneyText :amount-minor="trialTotals.credit" /></td>
              </tr>
            </tfoot>
          </table>
        </div>
      </section>
    </section>

    <!-- Profit & Loss -->
    <section v-else-if="tab === 'profit-loss'" class="space-y-4" role="tabpanel" aria-label="Profit and loss">
      <div class="flex justify-end">
        <button type="button" class="ls-btn" @click="exportProfitLoss">Export CSV</button>
      </div>

      <EmptyState
        v-if="!profitLoss?.length"
        title="Reports will appear once posted transactions exist."
        description="Nothing was posted in this date range."
      />

      <div v-else class="ls-card overflow-hidden">
        <table class="ls-table">
          <caption class="sr-only">Profit and loss for the selected period</caption>
          <tbody>
            <template v-for="section in plSections" :key="section.key">
              <tr v-if="rowsIn(profitLoss, section.key).length" class="bg-neutral-50 dark:bg-neutral-800/50">
                <th scope="colgroup" class="text-left">{{ section.label }}</th>
                <td class="ls-num font-semibold">
                  <MoneyText :amount-minor="sectionTotal(profitLoss, section.key)" />
                </td>
              </tr>
              <tr v-for="row in rowsIn(profitLoss, section.key)" :key="row.account_id ?? row.name">
                <td class="pl-8">{{ row.name }}</td>
                <td class="ls-num"><MoneyText :amount-minor="row.amount_minor" /></td>
              </tr>
            </template>
          </tbody>
          <tfoot>
            <tr class="text-base font-semibold">
              <td>Net profit</td>
              <td class="ls-num"><MoneyText :amount-minor="netProfit" signed /></td>
            </tr>
          </tfoot>
        </table>
      </div>
    </section>

    <!-- Balance sheet -->
    <section v-else-if="tab === 'balance-sheet'" class="space-y-4" role="tabpanel" aria-label="Balance sheet">
      <div class="flex justify-end">
        <button type="button" class="ls-btn" @click="exportBalanceSheet">Export CSV</button>
      </div>

      <EmptyState
        v-if="!balanceSheet?.length"
        title="Reports will appear once posted transactions exist."
        description="Nothing has been posted as of this date."
      />

      <template v-else>
        <div class="ls-card overflow-hidden">
          <table class="ls-table">
            <caption class="sr-only">Balance sheet as of the selected date</caption>
            <tbody>
              <template v-for="section in bsSections" :key="section.key">
                <tr v-if="rowsIn(balanceSheet, section.key).length" class="bg-neutral-50 dark:bg-neutral-800/50">
                  <th scope="colgroup" class="text-left">{{ section.label }}</th>
                  <td class="ls-num font-semibold">
                    <MoneyText :amount-minor="sectionTotal(balanceSheet, section.key)" />
                  </td>
                </tr>
                <tr v-for="row in rowsIn(balanceSheet, section.key)" :key="row.account_id ?? row.name">
                  <td class="pl-8">{{ row.name }}</td>
                  <td class="ls-num"><MoneyText :amount-minor="row.amount_minor" /></td>
                </tr>
              </template>
            </tbody>
          </table>
        </div>

        <p class="text-sm" :class="assets === liabilities + equity ? 'text-neutral-500' : 'text-red-700 dark:text-red-400'">
          Assets <MoneyText :amount-minor="assets" /> =
          Liabilities <MoneyText :amount-minor="liabilities" /> +
          Equity <MoneyText :amount-minor="equity" />
        </p>
      </template>
    </section>

    <!-- Cash flow -->
    <section v-else-if="tab === 'cash-flow'" role="tabpanel" aria-label="Cash flow">
      <EmptyState
        v-if="!cashFlow?.length"
        title="No cash movement in this period."
        description="Cash flow appears once money moves through a cash, bank or wallet account."
      />

      <div v-else class="ls-card overflow-hidden">
        <table class="ls-table">
          <caption class="sr-only">Cash flow for the selected period</caption>
          <thead>
            <tr>
              <th scope="col">Activity</th>
              <th scope="col" class="text-right">Net movement</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in cashFlow" :key="row.section">
              <td>{{ cashFlowLabels[row.section] ?? row.section }}</td>
              <td class="ls-num"><MoneyText :amount-minor="row.amount_minor" signed explicit-sign /></td>
            </tr>
          </tbody>
          <tfoot>
            <tr class="font-semibold">
              <td>Net change in cash</td>
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
    <section v-else role="tabpanel" aria-label="Ledger">
      <EmptyState
        v-if="!ledger?.length"
        title="No entries for this account in this period."
        description="Pick another account or widen the date range."
      />

      <div v-else class="ls-card overflow-x-auto">
        <table class="ls-table">
          <caption class="sr-only">Ledger for the selected account, with a running balance</caption>
          <thead>
            <tr>
              <th scope="col">Date</th>
              <th scope="col">Reference</th>
              <th scope="col">Description</th>
              <th scope="col" class="text-right">Debit</th>
              <th scope="col" class="text-right">Credit</th>
              <th scope="col" class="text-right">Balance</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in ledger" :key="row.entry_id">
              <td class="whitespace-nowrap">{{ row.entry_date }}</td>
              <td class="text-neutral-500">{{ row.reference || '—' }}</td>
              <td class="max-w-64 truncate">{{ row.description || row.memo || '—' }}</td>
              <td class="ls-num">
                <MoneyText v-if="Number(row.debit_minor)" :amount-minor="row.debit_minor" />
                <span v-else class="text-neutral-300">—</span>
              </td>
              <td class="ls-num">
                <MoneyText v-if="Number(row.credit_minor)" :amount-minor="row.credit_minor" />
                <span v-else class="text-neutral-300">—</span>
              </td>
              <td class="ls-num font-medium">
                <MoneyText :amount-minor="row.running_balance_minor" />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>

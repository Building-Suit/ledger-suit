<script setup lang="ts">
import type { Database } from '~~/types/database.types'

definePageMeta({ layout: 'default' })
/**
 * The primary operational page.
 *
 * Filtering, sorting, searching and paging all happen in the database via
 * search_transactions(). The browser never holds the dataset — it holds one
 * page of it.
 */

const supabase = useSupabaseClient<Database>()
const { currentId, can, baseCurrency } = useTenant()
const { start } = useAddTransaction()
const { t, locale } = useI18n()

useHead({ title: () => `${t('transactions.title')} · ${t('app.name')}` })

const { data: categories } = await useOrgCategories()
const { data: accounts } = await useOrgAccounts()

const PAGE_SIZE = 25

type TxnStatus = Database['public']['Enums']['transaction_status']
type TxnType = Database['public']['Enums']['transaction_type']

const filters = reactive({
  search: '',
  from: '',
  to: '',
  status: '' as '' | TxnStatus,
  type: '' as '' | TxnType,
  categoryId: '',
  accountId: '',
  minAmount: '',
  maxAmount: '',
})

const sort = reactive({ column: 'transaction_date', direction: 'desc' as 'asc' | 'desc' })
const page = ref(1)
const filtersOpen = ref(false)
const selectedId = ref<string | null>(null)

// Debounced so typing in the search box does not fire a query per keystroke.
const debouncedSearch = ref('')
let searchTimer: ReturnType<typeof setTimeout> | undefined
watch(() => filters.search, (value) => {
  clearTimeout(searchTimer)
  searchTimer = setTimeout(() => {
    debouncedSearch.value = value
    page.value = 1
  }, 300)
})

// `undefined` rather than `null`: supabase-js omits undefined keys entirely,
// so the function's own default applies instead of an explicit NULL.
const omitIfEmpty = (value: string) => (value.trim() === '' ? undefined : value)

function amountToMinor(value: string): number | undefined {
  if (!value.trim()) return undefined
  try {
    return Number(parseMoneyToMinor(value, baseCurrency.value))
  }
  catch {
    return undefined
  }
}

type TransactionRow = Database['public']['Functions']['search_transactions']['Returns'][number]

const { data: result, pending, refresh } = await useAsyncData('org:transactions', async () => {
  if (!currentId.value) return { rows: [] as TransactionRow[], total: 0 }

  const { data, error } = await supabase.rpc('search_transactions', {
    p_organization_id: currentId.value,
    p_search: omitIfEmpty(debouncedSearch.value),
    p_from_date: omitIfEmpty(filters.from),
    p_to_date: omitIfEmpty(filters.to),
    p_statuses: filters.status ? [filters.status] : undefined,
    p_types: filters.type ? [filters.type] : undefined,
    p_category_ids: filters.categoryId ? [filters.categoryId] : undefined,
    p_account_ids: filters.accountId ? [filters.accountId] : undefined,
    p_min_amount_minor: amountToMinor(filters.minAmount),
    p_max_amount_minor: amountToMinor(filters.maxAmount),
    p_sort: sort.column,
    p_direction: sort.direction,
    p_limit: PAGE_SIZE,
    p_offset: (page.value - 1) * PAGE_SIZE,
  })

  if (error) throw error

  const rows = (data ?? []) as TransactionRow[]
  // total_count is the same on every row; an empty page means zero.
  const total = rows.length ? Number(rows[0]!.total_count) : 0
  return { rows, total }
}, {
  watch: [
    currentId,
    debouncedSearch,
    page,
    () => filters.from,
    () => filters.to,
    () => filters.status,
    () => filters.type,
    () => filters.categoryId,
    () => filters.accountId,
    () => filters.minAmount,
    () => filters.maxAmount,
    () => sort.column,
    () => sort.direction,
  ],
  default: () => ({ rows: [] as TransactionRow[], total: 0 }),
})

const rows = computed<TransactionRow[]>(() => result.value?.rows ?? [])
const total = computed(() => result.value?.total ?? 0)
const pageCount = computed(() => Math.max(1, Math.ceil(total.value / PAGE_SIZE)))
const rangeStart = computed(() => (total.value === 0 ? 0 : (page.value - 1) * PAGE_SIZE + 1))
const rangeEnd = computed(() => Math.min(page.value * PAGE_SIZE, total.value))

const activeFilterCount = computed(() =>
  [filters.from, filters.to, filters.status, filters.type, filters.categoryId,
   filters.accountId, filters.minAmount, filters.maxAmount].filter(v => v !== '').length,
)

function toggleSort(column: string) {
  if (sort.column === column) {
    sort.direction = sort.direction === 'asc' ? 'desc' : 'asc'
  }
  else {
    sort.column = column
    sort.direction = 'desc'
  }
  page.value = 1
}

function clearFilters() {
  Object.assign(filters, {
    search: '', from: '', to: '', status: '' as const, type: '' as const,
    categoryId: '', accountId: '', minAmount: '', maxAmount: '',
  })
  debouncedSearch.value = ''
  page.value = 1
}

function ariaSort(column: string) {
  if (sort.column !== column) return 'none'
  return sort.direction === 'asc' ? 'ascending' : 'descending'
}

const STATUSES = ['draft', 'scheduled', 'pending', 'pending_approval', 'posted', 'voided', 'reversed', 'failed']
const TYPES = ['income', 'expense', 'transfer', 'asset_purchase', 'liability_created',
  'liability_payment', 'owner_contribution', 'owner_withdrawal', 'adjustment', 'opening_balance', 'reversal']
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h1 class="text-2xl font-extrabold">{{ t('transactions.title') }}</h1>
      <p class="text-sm text-fg-muted">{{ t('transactions.count', total) }}</p>
    </div>

    <div class="flex flex-wrap items-center gap-2">
      <div class="min-w-48 flex-1">
        <label class="sr-only" for="search">{{ t('transactions.searchLabel') }}</label>
        <input
          id="search"
          v-model="filters.search"
          type="search"
          class="ls-input"
          :placeholder="t('transactions.searchPlaceholder')"
        >
      </div>
      <button
        type="button"
        class="ls-btn"
        :aria-expanded="filtersOpen"
        @click="filtersOpen = !filtersOpen"
      >
        {{ t('transactions.filters') }}
        <span v-if="activeFilterCount" class="ls-badge bg-[var(--bs-primary)] text-[var(--bs-text-on-primary)]">
          {{ activeFilterCount }}
        </span>
      </button>
      <button v-if="activeFilterCount || filters.search" type="button" class="ls-btn" @click="clearFilters">
        {{ t('common.clear') }}
      </button>
    </div>

    <div v-if="filtersOpen" class="ls-card grid gap-3 p-4 sm:grid-cols-2 lg:grid-cols-4">
      <div>
        <label class="ls-label" for="from">{{ t('transactions.fromDate') }}</label>
        <input id="from" v-model="filters.from" type="date" class="ls-input">
      </div>
      <div>
        <label class="ls-label" for="to">{{ t('transactions.toDate') }}</label>
        <input id="to" v-model="filters.to" type="date" class="ls-input">
      </div>
      <div>
        <label class="ls-label" for="status">{{ t('transactions.status') }}</label>
        <select id="status" v-model="filters.status" class="ls-input">
          <option value="">{{ t('common.any') }}</option>
          <option v-for="s in STATUSES" :key="s" :value="s">{{ t(`status.${s}`) }}</option>
        </select>
      </div>
      <div>
        <label class="ls-label" for="type">{{ t('transactions.type') }}</label>
        <select id="type" v-model="filters.type" class="ls-input">
          <option value="">{{ t('common.any') }}</option>
          <option v-for="type in TYPES" :key="type" :value="type">{{ t(`types.${type}`) }}</option>
        </select>
      </div>
      <div>
        <label class="ls-label" for="category">{{ t('transactions.category') }}</label>
        <select id="category" v-model="filters.categoryId" class="ls-input">
          <option value="">{{ t('common.any') }}</option>
          <option v-for="c in categories" :key="c.id" :value="c.id">{{ c.name }}</option>
        </select>
      </div>
      <div>
        <label class="ls-label" for="account">{{ t('transactions.account') }}</label>
        <select id="account" v-model="filters.accountId" class="ls-input">
          <option value="">{{ t('common.any') }}</option>
          <option v-for="a in accounts" :key="a.id" :value="a.id">{{ a.name }}</option>
        </select>
      </div>
      <div>
        <label class="ls-label" for="min">{{ t('transactions.minAmount') }}</label>
        <input id="min" v-model="filters.minAmount" class="ls-input" inputmode="decimal" placeholder="0.00">
      </div>
      <div>
        <label class="ls-label" for="max">{{ t('transactions.maxAmount') }}</label>
        <input id="max" v-model="filters.maxAmount" class="ls-input" inputmode="decimal" placeholder="0.00">
      </div>
    </div>

    <EmptyState
      v-if="!pending && rows.length === 0 && !activeFilterCount && !debouncedSearch"
      :title="t('transactions.emptyTitle')"
      :description="t('transactions.emptyHint')"
      :action-label="can('transactions.create') ? t('transactions.emptyAction') : undefined"
      @action="start('expense')"
    />

    <EmptyState
      v-else-if="!pending && rows.length === 0"
      :title="t('transactions.noMatchTitle')"
      :description="t('transactions.noMatchHint')"
      :action-label="t('transactions.noMatchAction')"
      @action="clearFilters"
    />

    <div v-else class="ls-card overflow-hidden">
      <!-- Wide financial table on desktop -->
      <div class="hidden overflow-x-auto md:block">
        <table class="ls-table">
          <caption class="sr-only">{{ t('transactions.caption') }}</caption>
          <thead>
            <tr>
              <th scope="col" :aria-sort="ariaSort('transaction_date')">
                <button type="button" class="hover:underline" @click="toggleSort('transaction_date')">{{ t('transactions.date') }}</button>
              </th>
              <th scope="col">{{ t('transactions.description') }}</th>
              <th scope="col" :aria-sort="ariaSort('type')">
                <button type="button" class="hover:underline" @click="toggleSort('type')">{{ t('transactions.type') }}</button>
              </th>
              <th scope="col">{{ t('transactions.category') }}</th>
              <th scope="col">{{ t('transactions.fromTo') }}</th>
              <th scope="col">{{ t('transactions.counterparty') }}</th>
              <th scope="col" :aria-sort="ariaSort('status')">
                <button type="button" class="hover:underline" @click="toggleSort('status')">{{ t('transactions.status') }}</button>
              </th>
              <th scope="col" class="text-end" :aria-sort="ariaSort('amount')">
                <button type="button" class="hover:underline" @click="toggleSort('amount')">{{ t('transactions.amount') }}</button>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in rows"
              :key="row.id"
              class="cursor-pointer hover:bg-surface-muted"
              @click="selectedId = row.id"
            >
              <td class="whitespace-nowrap">{{ formatDate(row.transaction_date, locale) }}</td>
              <td class="max-w-64">
                <span class="block truncate">{{ row.description || t('common.dash') }}</span>
                <span v-if="row.reference" class="block text-xs text-fg-muted">{{ row.reference }}</span>
              </td>
              <td class="whitespace-nowrap">{{ t(`types.${row.type}`) }}</td>
              <td>{{ row.category_name || t('common.dash') }}</td>
              <td class="whitespace-nowrap text-fg-muted">
                {{ row.from_account_name || t('common.dash') }} → {{ row.to_account_name || t('common.dash') }}
              </td>
              <td>{{ row.counterparty_name || t('common.dash') }}</td>
              <td><StatusBadge :status="row.status" /></td>
              <td class="ls-num font-semibold">
                <MoneyText :amount-minor="row.amount_minor" :currency="row.currency_code" />
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Compact rows on small screens: a wide table is unusable on a phone -->
      <ul class="divide-y divide-[var(--bs-border)] md:hidden">
        <li v-for="row in rows" :key="row.id">
          <button type="button" class="w-full px-4 py-3 text-start" @click="selectedId = row.id">
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <p class="truncate text-sm font-semibold">{{ row.description || t('common.dash') }}</p>
                <p class="mt-0.5 text-xs text-fg-muted">
                  {{ formatDate(row.transaction_date, locale) }} · {{ row.category_name || t(`types.${row.type}`) }}
                </p>
              </div>
              <div class="shrink-0 text-right">
                <MoneyText class="text-sm font-semibold" :amount-minor="row.amount_minor" :currency="row.currency_code" />
                <StatusBadge class="mt-1 block" :status="row.status" />
              </div>
            </div>
          </button>
        </li>
      </ul>

      <div class="flex flex-wrap items-center justify-between gap-3 border-t border-[var(--bs-border)] px-4 py-3">
        <p class="text-sm text-fg-muted">
          {{ t('transactions.showing', { from: rangeStart, to: rangeEnd, total }) }}
        </p>
        <div class="flex items-center gap-2">
          <button type="button" class="ls-btn ls-btn-sm" :disabled="page <= 1" @click="page--">{{ t('common.previous') }}</button>
          <span class="text-sm text-fg-muted">{{ t('transactions.page', { page, pages: pageCount }) }}</span>
          <button type="button" class="ls-btn ls-btn-sm" :disabled="page >= pageCount" @click="page++">{{ t('common.next') }}</button>
        </div>
      </div>
    </div>

    <TransactionDetailDialog
      :transaction-id="selectedId"
      @close="selectedId = null"
      @changed="refresh()"
    />
  </div>
</template>

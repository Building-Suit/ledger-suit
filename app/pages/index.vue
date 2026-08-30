<script setup lang="ts">
import type { Database } from '~~/types/database.types'

// Phase 1 shell. The four product pages (Dashboard, Transactions, Accounts,
// Reports) land in Phase 2; this page exists to prove the wiring end to end:
// auth -> membership -> RLS -> server-side aggregation RPC.

const supabase = useSupabaseClient<Database>()
const user = useSupabaseUser()

type Membership = {
  role: string
  organizations: {
    id: string
    name: string
    base_currency: string
  } | null
}

const { data: memberships } = await useAsyncData('memberships', async () => {
  const { data, error } = await supabase
    .from('organization_members')
    .select('role, organizations(id, name, base_currency)')
    .eq('status', 'active')

  if (error) throw error
  return (data ?? []) as unknown as Membership[]
})

const selectedId = ref<string | null>(null)

watchEffect(() => {
  if (!selectedId.value && memberships.value?.length) {
    selectedId.value = memberships.value[0]?.organizations?.id ?? null
  }
})

const selected = computed(() =>
  memberships.value?.find(m => m.organizations?.id === selectedId.value) ?? null,
)

// Every KPI is computed in the database. Nothing here recalculates a figure.
const { data: summary } = await useAsyncData(
  'dashboard-summary',
  async () => {
    if (!selectedId.value) return null

    const { data, error } = await supabase.rpc('dashboard_summary', {
      p_organization_id: selectedId.value,
    })

    if (error) throw error
    return data as Record<string, string | number>
  },
  { watch: [selectedId] },
)

const currency = computed(() => selected.value?.organizations?.base_currency ?? 'EGP')

const kpis = computed(() => {
  if (!summary.value) return []
  const s = summary.value
  return [
    { label: 'Total assets', value: s.total_assets_minor },
    { label: 'Total liabilities', value: s.total_liabilities_minor },
    { label: 'Net worth', value: s.net_worth_minor },
    { label: 'Cash and bank', value: s.cash_and_bank_minor },
    { label: 'Revenue this month', value: s.revenue_this_month_minor },
    { label: 'Expenses this month', value: s.expenses_this_month_minor },
    { label: 'Net profit this month', value: s.net_profit_this_month_minor },
  ]
})

async function signOut() {
  await supabase.auth.signOut()
  await navigateTo('/login')
}
</script>

<template>
  <main class="mx-auto w-full max-w-5xl px-4 py-10">
    <header class="flex flex-wrap items-center justify-between gap-4">
      <div>
        <h1 class="text-xl font-semibold">Ledger Suit</h1>
        <p class="text-sm text-neutral-500">{{ user?.email }}</p>
      </div>

      <div class="flex items-center gap-3">
        <label for="org" class="sr-only">Organization</label>
        <select
          id="org"
          v-model="selectedId"
          class="rounded-md border border-neutral-300 px-3 py-2 text-sm dark:border-neutral-700 dark:bg-neutral-950"
        >
          <option
            v-for="m in memberships"
            :key="m.organizations?.id"
            :value="m.organizations?.id"
          >
            {{ m.organizations?.name }} — {{ m.role }}
          </option>
        </select>

        <button
          type="button"
          class="rounded-md border border-neutral-300 px-3 py-2 text-sm dark:border-neutral-700"
          @click="signOut"
        >
          Sign out
        </button>
      </div>
    </header>

    <section v-if="!memberships?.length" class="mt-10 rounded-xl border border-dashed border-neutral-300 p-10 text-center dark:border-neutral-700">
      <p class="font-medium">You are not a member of any organization yet.</p>
      <p class="mt-1 text-sm text-neutral-500">
        Create one to start seeing your financial overview.
      </p>
    </section>

    <section v-else class="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <article
        v-for="kpi in kpis"
        :key="kpi.label"
        class="rounded-xl border border-neutral-200 bg-white p-5 dark:border-neutral-800 dark:bg-neutral-900"
      >
        <p class="text-sm text-neutral-500">{{ kpi.label }}</p>
        <p class="mt-2 text-2xl font-semibold tabular-nums">
          {{ formatMoney(kpi.value ?? 0, currency) }}
        </p>
      </article>
    </section>

    <p class="mt-10 text-sm text-neutral-500">
      Phase 1 delivers the accounting core: schema, ledger, posting RPCs,
      row level security and tests. Dashboard, Transactions, Accounts and
      Reports arrive in Phase 2.
    </p>
  </main>
</template>

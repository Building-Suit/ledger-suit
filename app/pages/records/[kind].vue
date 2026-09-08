<script setup lang="ts">
import type { Database } from '~~/types/database.types'

definePageMeta({ layout: 'default' })

type TransactionFlow = typeof ADD_FLOWS[number]
type OperationKind = 'commitments' | 'recurring' | 'counterparties' | 'tags'
type RecordKind = TransactionFlow | OperationKind | 'invitations'
type GenericRow = Record<string, unknown>
type TransactionRow = Database['public']['Functions']['search_transactions']['Returns'][number]

const route = useRoute()
const supabase = useSupabaseClient<Database>()
const { currentId, baseCurrency, can } = useTenant()
const { writesAllowed } = useBilling()
const { start, revision: transactionRevision } = useAddTransaction()
const { show: showOperations, revision: operationRevision } = useOperationsCenter()
const { show: showInvitation, revision: invitationRevision } = useTeamInvitation()
const { t, locale } = useI18n()
const toasts = useToasts()
const describeError = useErrorMessage()
const { data: accounts } = useOrgAccounts()
const paymentAccounts = usePaymentAccounts(accounts)

const OPERATION_KINDS: OperationKind[] = ['commitments', 'recurring', 'counterparties', 'tags']
const VALID_KINDS: RecordKind[] = [...ADD_FLOWS, ...OPERATION_KINDS, 'invitations']
const kind = computed(() => String(route.params.kind) as RecordKind)

if (!VALID_KINDS.includes(kind.value)) {
  throw createError({ statusCode: 404, statusMessage: 'Page not found' })
}

// Preserve old bookmarks while replacing the invitation-only screen with the
// complete workspace access console.
if (kind.value === 'invitations') await navigateTo('/team', { replace: true })

const isTransaction = computed(() => (ADD_FLOWS as readonly string[]).includes(kind.value))
const title = computed(() => {
  if (isTransaction.value) return t(`add.flows.${kind.value}`)
  if (kind.value === 'invitations') return t('add.items.invitation')
  if (kind.value === 'commitments') return t('operations.tabs.commitments')
  const itemKey = kind.value === 'counterparties' ? 'counterparty' : kind.value === 'tags' ? 'tag' : 'recurring'
  return t(`add.items.${itemKey}`)
})

useHead({ title: () => `${title.value} · ${t('app.name')}` })

const dataKey = computed(() => `org:record-page:${kind.value}`)
const { data: rows, pending, refresh } = useLazyAsyncData<Array<TransactionRow | GenericRow>>(dataKey, async () => {
  if (!currentId.value) return []

  if (isTransaction.value) {
    const { data, error } = await supabase.rpc('search_transactions', {
      p_organization_id: currentId.value,
      p_types: [kind.value as TransactionFlow],
      p_sort: 'transaction_date',
      p_direction: 'desc',
      p_limit: 100,
      p_offset: 0,
    })
    if (error) throw error
    return (data ?? []) as TransactionRow[]
  }

  if (kind.value === 'commitments') {
    const { data, error } = await supabase.from('commitment_states').select('*').eq('organization_id', currentId.value).order('due_date')
    if (error) throw error
    return (data ?? []) as GenericRow[]
  }
  if (kind.value === 'recurring') {
    const { data, error } = await supabase.from('recurring_rules').select('*').eq('organization_id', currentId.value).order('created_at', { ascending: false })
    if (error) throw error
    return (data ?? []) as GenericRow[]
  }
  if (kind.value === 'counterparties') {
    const { data, error } = await supabase.from('counterparties').select('*').eq('organization_id', currentId.value).order('name')
    if (error) throw error
    return (data ?? []) as GenericRow[]
  }
  if (kind.value === 'tags') {
    const { data, error } = await supabase.from('tags').select('*').eq('organization_id', currentId.value).order('name')
    if (error) throw error
    return (data ?? []) as GenericRow[]
  }

  const { data, error } = await supabase.from('organization_invitations').select('id, email, role, status, created_at, expires_at').eq('organization_id', currentId.value).order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as GenericRow[]
}, { watch: [currentId, kind], default: () => [] })

const selectedId = ref<string | null>(null)
const canCreate = computed(() => {
  if (!writesAllowed.value) return false
  if (isTransaction.value) return can(FLOW_CAPABILITY[kind.value as TransactionFlow])
  if (kind.value === 'commitments') return can('commitments.create')
  if (kind.value === 'recurring') return can('recurring.manage')
  if (kind.value === 'counterparties') return can('counterparties.manage')
  if (kind.value === 'tags') return can('tags.manage')
  return can('members.invite')
})

function addRecord() {
  if (isTransaction.value) start(kind.value as TransactionFlow)
  else if (kind.value === 'invitations') showInvitation()
  else showOperations(kind.value as OperationKind)
}

async function openCreateFromRoute() {
  if (route.query.create !== '1' || !canCreate.value) return
  addRecord()
  await navigateTo(route.path, { replace: true })
}

watch(() => route.query.create, () => void openCreateFromRoute(), { immediate: true })
watch(transactionRevision, () => { if (isTransaction.value) void refresh() })
watch(() => operationRevision.value[kind.value as OperationKind], () => { if (OPERATION_KINDS.includes(kind.value as OperationKind)) void refresh() })
watch(invitationRevision, () => { if (kind.value === 'invitations') void refresh() })

const actionBusy = ref(false)
const actionError = ref<string | null>(null)
const today = () => new Date().toISOString().slice(0, 10)
const commitmentAction = reactive({ id: '', mode: 'settle' as 'settle' | 'postpone', amount: '', paymentAccountId: '', date: today() })

function openCommitmentAction(id: string, mode: 'settle' | 'postpone') {
  Object.assign(commitmentAction, { id, mode, amount: '', paymentAccountId: paymentAccounts.value[0]?.id ?? '', date: today() })
  actionError.value = null
}

async function runRowAction(action: () => PromiseLike<{ error: unknown }>) {
  actionBusy.value = true
  actionError.value = null
  try {
    const { error } = await action()
    if (error) throw error
    await refresh()
    toasts.success(t('operations.saved'))
  }
  catch (error) { actionError.value = describeError(error) }
  finally { actionBusy.value = false }
}

async function submitCommitmentAction() {
  if (!commitmentAction.id) return
  const id = commitmentAction.id
  await runRowAction(() => commitmentAction.mode === 'settle'
    ? supabase.rpc('settle_commitment', {
        p_commitment_id: id,
        p_payment_account_id: commitmentAction.paymentAccountId,
        p_amount_minor: commitmentAction.amount ? Number(parseMoneyToMinor(commitmentAction.amount, baseCurrency.value)) : undefined,
        p_settled_on: commitmentAction.date,
      })
    : supabase.rpc('postpone_commitment', { p_commitment_id: id, p_new_due_date: commitmentAction.date }))
  if (!actionError.value) commitmentAction.id = ''
}

async function cancelCommitment(id: string) {
  await runRowAction(() => supabase.rpc('cancel_commitment', { p_commitment_id: id }))
}

async function setRuleStatus(id: string, status: Database['public']['Enums']['recurring_status']) {
  await runRowAction(() => supabase.rpc('set_recurring_rule_status', { p_rule_id: id, p_status: status }))
}

const value = (row: TransactionRow | GenericRow, key: string) => (row as GenericRow)[key]
const text = (row: TransactionRow | GenericRow, key: string) => String(value(row, key) ?? t('common.dash'))
const number = (row: TransactionRow | GenericRow, key: string) => Number(value(row, key) ?? 0)
const date = (row: TransactionRow | GenericRow, key: string) => {
  const raw = value(row, key)
  return formatDate(typeof raw === 'string' ? raw.slice(0, 10) : null, locale.value)
}
</script>

<template>
  <div class="space-y-6">
    <header class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <NuxtLink v-if="isTransaction" to="/transactions" class="text-xs font-semibold text-link">{{ t('recordPages.allTransactions') }}</NuxtLink>
        <h1 class="mt-1 text-h1 font-bold">{{ title }}</h1>
        <p class="mt-1 text-sm text-fg-muted">{{ t('recordPages.count', rows.length) }}</p>
      </div>
      <button v-if="canCreate" type="button" class="ls-btn ls-btn-primary" @click="addRecord">
        {{ t('recordPages.add', { item: title }) }}
      </button>
    </header>

    <SectionSkeleton v-if="pending" variant="table" :rows="8" />
    <EmptyState v-else-if="rows.length === 0" :title="t('recordPages.empty', { item: title })" :description="t('recordPages.emptyHint')" :action-label="canCreate ? t('recordPages.add', { item: title }) : undefined" @action="addRecord" />

    <div v-else class="ls-card overflow-x-auto">
      <table v-if="isTransaction" class="ls-table">
        <caption class="sr-only">{{ title }}</caption>
        <thead><tr><th>{{ t('transactions.date') }}</th><th>{{ t('transactions.description') }}</th><th>{{ t('transactions.category') }}</th><th>{{ t('transactions.fromTo') }}</th><th>{{ t('transactions.status') }}</th><th class="text-end">{{ t('transactions.amount') }}</th></tr></thead>
        <tbody><tr v-for="row in rows" :key="text(row, 'id')" class="cursor-pointer hover:bg-surface-muted" @click="selectedId = text(row, 'id')"><td class="whitespace-nowrap">{{ date(row, 'transaction_date') }}</td><td>{{ text(row, 'description') }}</td><td>{{ text(row, 'category_name') }}</td><td class="whitespace-nowrap text-fg-muted">{{ text(row, 'from_account_name') }} <AppIcon name="arrowRight" :size="14" directional class="inline-block" /> {{ text(row, 'to_account_name') }}</td><td><StatusBadge :status="text(row, 'status')" /></td><td class="ls-num font-semibold"><MoneyText :amount-minor="number(row, 'amount_minor')" :currency="text(row, 'currency_code')" /></td></tr></tbody>
      </table>

      <table v-else-if="kind === 'commitments'" class="ls-table"><thead><tr><th>{{ t('operations.name') }}</th><th>{{ t('recordPages.kind') }}</th><th>{{ t('add.dueDate') }}</th><th>{{ t('transactions.status') }}</th><th class="text-end">{{ t('transactions.amount') }}</th><th class="text-end">{{ t('accounts.actions') }}</th></tr></thead><tbody><tr v-for="row in rows" :key="text(row, 'id')"><td>{{ text(row, 'title') }}</td><td>{{ text(row, 'type').replaceAll('_', ' ') }}</td><td>{{ date(row, 'due_date') }}</td><td><StatusBadge :status="text(row, 'status')" /></td><td class="ls-num"><MoneyText :amount-minor="number(row, 'outstanding_minor')" :currency="text(row, 'currency_code')" /></td><td class="whitespace-nowrap text-end"><template v-if="!['paid','cancelled'].includes(text(row, 'status'))"><button v-if="can('commitments.settle')" class="ls-btn ls-btn-sm" @click="openCommitmentAction(text(row, 'id'), 'settle')">{{ t('operations.settle') }}</button><button v-if="can('commitments.update')" class="ls-btn ls-btn-sm ms-1" @click="openCommitmentAction(text(row, 'id'), 'postpone')">{{ t('operations.postpone') }}</button><button v-if="can('commitments.update')" class="ls-btn ls-btn-sm ms-1" :disabled="actionBusy" @click="cancelCommitment(text(row, 'id'))">{{ t('common.cancel') }}</button></template></td></tr></tbody></table>

      <table v-else-if="kind === 'recurring'" class="ls-table"><thead><tr><th>{{ t('operations.name') }}</th><th>{{ t('transactions.type') }}</th><th>{{ t('recordPages.schedule') }}</th><th>{{ t('recordPages.nextRun') }}</th><th>{{ t('transactions.status') }}</th><th class="text-end">{{ t('accounts.actions') }}</th></tr></thead><tbody><tr v-for="row in rows" :key="text(row, 'id')"><td>{{ text(row, 'name') }}</td><td>{{ t(`types.${text(row, 'transaction_type')}`) }}</td><td>{{ text(row, 'interval_count') }} × {{ text(row, 'frequency') }}</td><td>{{ date(row, 'next_run_on') }}</td><td><StatusBadge :status="text(row, 'status')" /></td><td class="text-end"><button v-if="can('recurring.manage') && text(row, 'status') === 'active'" class="ls-btn ls-btn-sm" :disabled="actionBusy" @click="setRuleStatus(text(row, 'id'), 'paused')">{{ t('operations.pause') }}</button><button v-else-if="can('recurring.manage') && ['paused','failed'].includes(text(row, 'status'))" class="ls-btn ls-btn-sm" :disabled="actionBusy" @click="setRuleStatus(text(row, 'id'), 'active')">{{ t('operations.resume') }}</button></td></tr></tbody></table>

      <table v-else-if="kind === 'counterparties'" class="ls-table"><thead><tr><th>{{ t('operations.name') }}</th><th>{{ t('recordPages.kind') }}</th><th>{{ t('auth.email') }}</th><th>{{ t('operations.phone') }}</th><th>{{ t('transactions.status') }}</th></tr></thead><tbody><tr v-for="row in rows" :key="text(row, 'id')"><td>{{ text(row, 'name') }}</td><td>{{ text(row, 'type') }}</td><td>{{ text(row, 'email') }}</td><td>{{ text(row, 'phone') }}</td><td><StatusBadge :status="value(row, 'is_archived') ? 'archived' : 'active'" /></td></tr></tbody></table>

      <table v-else-if="kind === 'tags'" class="ls-table"><thead><tr><th>{{ t('operations.name') }}</th><th>{{ t('recordPages.color') }}</th><th>{{ t('recordPages.created') }}</th></tr></thead><tbody><tr v-for="row in rows" :key="text(row, 'id')"><td>{{ text(row, 'name') }}</td><td><span class="inline-flex items-center gap-2"><span class="size-3 rounded-full" :style="{ backgroundColor: text(row, 'color') }" />{{ text(row, 'color') }}</span></td><td>{{ date(row, 'created_at') }}</td></tr></tbody></table>

      <table v-else class="ls-table"><thead><tr><th>{{ t('auth.email') }}</th><th>{{ t('recordPages.role') }}</th><th>{{ t('transactions.status') }}</th><th>{{ t('recordPages.created') }}</th><th>{{ t('recordPages.expires') }}</th></tr></thead><tbody><tr v-for="row in rows" :key="text(row, 'id')"><td>{{ text(row, 'email') }}</td><td>{{ t(`org.roles.${text(row, 'role')}`) }}</td><td><StatusBadge :status="text(row, 'status')" /></td><td>{{ date(row, 'created_at') }}</td><td>{{ date(row, 'expires_at') }}</td></tr></tbody></table>
    </div>

    <p v-if="actionError && !commitmentAction.id" class="ls-error" role="alert">{{ actionError }}</p>

    <Teleport to="body">
      <Transition name="ls-modal">
        <div v-if="commitmentAction.id" class="fixed inset-0 z-[60] grid place-items-center ls-scrim p-4" role="dialog" aria-modal="true" @click.self="commitmentAction.id = ''">
          <form class="ls-modal-panel ls-card w-full max-w-lg space-y-4 p-6 shadow-overlay" @submit.prevent="submitCommitmentAction">
            <div class="flex items-center justify-between"><h2 class="text-lg font-bold">{{ t(commitmentAction.mode === 'settle' ? 'operations.settle' : 'operations.postpone') }}</h2><button type="button" class="ls-btn ls-btn-sm" :aria-label="t('common.close')" @click="commitmentAction.id = ''"><AppIcon name="close" /></button></div>
            <template v-if="commitmentAction.mode === 'settle'"><FloatingField :label="t('add.chooseAccount')"><select v-model="commitmentAction.paymentAccountId" class="ls-input" required><option value="">{{ t('add.chooseAccount') }}</option><option v-for="account in paymentAccounts" :key="account.id" :value="account.id">{{ account.name }}</option></select></FloatingField><FloatingField :label="t('operations.fullOrPartialAmount')"><input v-model="commitmentAction.amount" class="ls-input" inputmode="decimal" :placeholder="t('operations.fullOrPartialAmount')"></FloatingField></template>
            <FloatingField :label="t('add.date')"><input v-model="commitmentAction.date" type="date" class="ls-input" required></FloatingField>
            <p v-if="actionError" class="ls-error" role="alert">{{ actionError }}</p>
            <div class="flex justify-end gap-2"><button type="button" class="ls-btn" @click="commitmentAction.id = ''">{{ t('common.cancel') }}</button><button class="ls-btn ls-btn-primary" :disabled="actionBusy">{{ t(commitmentAction.mode === 'settle' ? 'operations.convert' : 'operations.postpone') }}</button></div>
          </form>
        </div>
      </Transition>
    </Teleport>

    <TransactionDetailDialog v-if="selectedId" :transaction-id="selectedId" @changed="refresh" @close="selectedId = null" />
  </div>
</template>

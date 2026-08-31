<script setup lang="ts">
import type { Database } from '~~/types/database.types'

const supabase = useSupabaseClient<Database>()
const { currentId, baseCurrency, can } = useTenant()
const { open, tab, close } = useOperationsCenter()
const { data: accounts } = await useOrgAccounts()
const { data: categories } = await useOrgCategories()
const toasts = useToasts()
const describeError = useErrorMessage()
const { t, locale } = useI18n()

const paymentAccounts = usePaymentAccounts(accounts)
const liabilityAccounts = computed(() => accounts.value.filter(account => account.type === 'liability' && !account.is_archived))
const incomeCategories = computed(() => categories.value.filter(c => c.kind === 'income'))
const expenseCategories = computed(() => categories.value.filter(c => c.kind === 'expense'))
const busy = ref(false)
const errorMessage = ref<string | null>(null)

const { data: commitments, refresh: refreshCommitments } = await useAsyncData('org:commitments', async () => {
  if (!currentId.value) return []
  const { data, error } = await supabase.from('commitment_states').select('*').eq('organization_id', currentId.value).order('due_date')
  if (error) throw error
  return data ?? []
}, { watch: [currentId], default: () => [] })

const { data: rules, refresh: refreshRules } = await useAsyncData('org:recurring-rules', async () => {
  if (!currentId.value) return []
  const { data, error } = await supabase.from('recurring_rules').select('*').eq('organization_id', currentId.value).order('created_at', { ascending: false })
  if (error) throw error
  return data ?? []
}, { watch: [currentId], default: () => [] })

const { data: occurrences, refresh: refreshOccurrences } = await useAsyncData('org:recurring-occurrences', async () => {
  if (!currentId.value) return []
  const { data, error } = await supabase.from('recurring_occurrences').select('*').eq('organization_id', currentId.value).order('occurrence_date', { ascending: false }).limit(50)
  if (error) throw error
  return data ?? []
}, { watch: [currentId], default: () => [] })

const { data: counterparties, refresh: refreshCounterparties } = await useOrgCounterparties()
const { data: tags, refresh: refreshTags } = await useAsyncData('org:tags', async () => {
  if (!currentId.value) return []
  const { data, error } = await supabase.from('tags').select('*').eq('organization_id', currentId.value).order('name')
  if (error) throw error
  return data ?? []
}, { watch: [currentId], default: () => [] })

const today = () => new Date().toISOString().slice(0, 10)
const commitmentForm = reactive({ type: 'payable', title: '', description: '', amount: '', dueDate: today(), categoryId: '', counterpartyId: '', autoConvert: false, paymentAccountId: '', reminderDays: 3 })
const recurringForm = reactive({ name: '', transactionType: 'expense', amount: '', principal: '', interest: '', fees: '', liabilityAccountId: '', categoryId: '', paymentAccountId: '', frequency: 'monthly', intervalCount: 1, startDate: today(), endDate: '', maxOccurrences: '', mode: 'requires_confirmation' })
const counterpartyForm = reactive({ name: '', type: 'other', email: '', phone: '', taxIdentifier: '', notes: '' })
const tagForm = reactive({ name: '', color: '#2563EB' })
const commitmentAction = reactive({ id: '', mode: 'settle' as 'settle' | 'postpone', amount: '', paymentAccountId: '', date: today() })

async function run(action: () => Promise<void>) {
  busy.value = true; errorMessage.value = null
  try { await action() }
  catch (error) { errorMessage.value = describeError(error) }
  finally { busy.value = false }
}

async function createCommitment() {
  const organizationId = currentId.value
  if (!organizationId) return
  await run(async () => {
    const amount = Number(parseMoneyToMinor(commitmentForm.amount, baseCurrency.value))
    const { data: id, error } = await supabase.rpc('create_commitment', {
      p_organization_id: organizationId,
      p_type: commitmentForm.type as Database['public']['Enums']['commitment_type'],
      p_title: commitmentForm.title,
      p_amount_minor: amount,
      p_due_date: commitmentForm.dueDate,
      p_linked_category_id: commitmentForm.categoryId || undefined,
      p_counterparty_id: commitmentForm.counterpartyId || undefined,
      p_description: commitmentForm.description || undefined,
      p_auto_convert: false,
      p_reminder_days_before: commitmentForm.reminderDays,
    })
    if (error) throw error
    if (commitmentForm.autoConvert) {
      const { error: updateError } = await supabase.rpc('update_commitment' as never, {
        p_commitment_id: id!, p_title: commitmentForm.title, p_amount_minor: amount,
        p_linked_category_id: commitmentForm.categoryId || undefined,
        p_auto_convert: true, p_auto_payment_account_id: commitmentForm.paymentAccountId,
      } as never)
      if (updateError) throw updateError
    }
    Object.assign(commitmentForm, { title: '', description: '', amount: '', dueDate: today(), categoryId: '', counterpartyId: '', autoConvert: false, paymentAccountId: '', reminderDays: 3 })
    await refreshCommitments(); toasts.success(t('operations.saved'))
  })
}

function openCommitmentAction(id: string, mode: 'settle' | 'postpone') {
  Object.assign(commitmentAction, { id, mode, amount: '', paymentAccountId: paymentAccounts.value[0]?.id ?? '', date: today() })
}

async function submitCommitmentAction() {
  if (!commitmentAction.id) return
  await run(async () => {
    const result = commitmentAction.mode === 'settle'
      ? await supabase.rpc('settle_commitment', {
          p_commitment_id: commitmentAction.id,
          p_payment_account_id: commitmentAction.paymentAccountId,
          p_amount_minor: commitmentAction.amount ? Number(parseMoneyToMinor(commitmentAction.amount, baseCurrency.value)) : undefined,
          p_settled_on: commitmentAction.date,
        })
      : await supabase.rpc('postpone_commitment', {
          p_commitment_id: commitmentAction.id,
          p_new_due_date: commitmentAction.date,
        })
    const { error } = result
    if (error) throw error
    commitmentAction.id = ''
    await refreshCommitments(); await refreshNuxtData(); toasts.success(t('operations.saved'))
  })
}

async function cancelCommitment(id: string) {
  await run(async () => { const { error } = await supabase.rpc('cancel_commitment', { p_commitment_id: id }); if (error) throw error; await refreshCommitments() })
}

async function createRecurring() {
  const organizationId = currentId.value
  if (!organizationId) return
  await run(async () => {
    const template: Record<string, unknown> = recurringForm.transactionType === 'liability_payment'
      ? {
          liability_account_id: recurringForm.liabilityAccountId,
          payment_account_id: recurringForm.paymentAccountId,
          principal_minor: Number(parseMoneyToMinor(recurringForm.principal || '0', baseCurrency.value)),
          interest_minor: Number(parseMoneyToMinor(recurringForm.interest || '0', baseCurrency.value)),
          fees_minor: Number(parseMoneyToMinor(recurringForm.fees || '0', baseCurrency.value)),
          description: recurringForm.name,
        }
      : {
          amount_minor: Number(parseMoneyToMinor(recurringForm.amount, baseCurrency.value)),
          category_id: recurringForm.categoryId || undefined,
          description: recurringForm.name,
          [recurringForm.transactionType === 'expense' ? 'source_account_id' : 'destination_account_id']: recurringForm.paymentAccountId,
        }
    const { error } = await supabase.rpc('create_recurring_rule', {
      p_organization_id: organizationId,
      p_name: recurringForm.name,
      p_transaction_type: recurringForm.transactionType as Database['public']['Enums']['transaction_type'],
      p_template: template as Database['public']['Functions']['create_recurring_rule']['Args']['p_template'],
      p_frequency: recurringForm.frequency as Database['public']['Enums']['recurrence_frequency'],
      p_start_date: recurringForm.startDate,
      p_interval_count: recurringForm.intervalCount,
      p_end_date: recurringForm.endDate || undefined,
      p_max_occurrences: recurringForm.maxOccurrences ? Number(recurringForm.maxOccurrences) : undefined,
      p_mode: recurringForm.mode as Database['public']['Enums']['recurring_mode'],
    })
    if (error) throw error
    Object.assign(recurringForm, { name: '', amount: '', principal: '', interest: '', fees: '', liabilityAccountId: '', categoryId: '', paymentAccountId: '', intervalCount: 1, startDate: today(), endDate: '', maxOccurrences: '' })
    await refreshRules(); toasts.success(t('operations.saved'))
  })
}

async function setRuleStatus(id: string, status: Database['public']['Enums']['recurring_status']) {
  await run(async () => { const { error } = await supabase.rpc('set_recurring_rule_status', { p_rule_id: id, p_status: status }); if (error) throw error; await refreshRules() })
}

async function occurrenceAction(id: string, action: 'confirm' | 'retry' | 'skip') {
  await run(async () => {
    const calls = {
      confirm: () => supabase.rpc('confirm_recurring_occurrence', { p_occurrence_id: id }),
      retry: () => supabase.rpc('retry_recurring_occurrence' as never, { p_occurrence_id: id } as never),
      skip: () => supabase.rpc('skip_recurring_occurrence', { p_occurrence_id: id }),
    }
    const { error } = await calls[action](); if (error) throw error
    await Promise.all([refreshOccurrences(), refreshRules(), refreshNuxtData()])
  })
}

async function createCounterparty() {
  const organizationId = currentId.value
  if (!organizationId) return
  await run(async () => {
    const { error } = await supabase.from('counterparties').insert({ organization_id: organizationId, name: counterpartyForm.name, type: counterpartyForm.type as Database['public']['Enums']['counterparty_type'], email: counterpartyForm.email || null, phone: counterpartyForm.phone || null, tax_identifier: counterpartyForm.taxIdentifier || null, notes: counterpartyForm.notes || null, created_by: (await supabase.auth.getUser()).data.user?.id ?? null })
    if (error) throw error
    Object.assign(counterpartyForm, { name: '', email: '', phone: '', taxIdentifier: '', notes: '' }); await refreshCounterparties(); toasts.success(t('operations.saved'))
  })
}

async function createTag() {
  const organizationId = currentId.value
  if (!organizationId) return
  await run(async () => {
    const { error } = await supabase.from('tags').insert({ organization_id: organizationId, name: tagForm.name, color: tagForm.color, created_by: (await supabase.auth.getUser()).data.user?.id ?? null })
    if (error) throw error
    tagForm.name = ''; await refreshTags(); toasts.success(t('operations.saved'))
  })
}
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="fixed inset-0 z-50 flex justify-end ls-scrim" role="dialog" aria-modal="true" @click.self="close">
      <div class="flex h-full w-full max-w-4xl flex-col bg-surface shadow-overlay">
        <header class="flex items-center justify-between border-b border-[var(--bs-border)] px-5 py-4">
          <h2 class="text-lg font-bold">{{ t('operations.title') }}</h2><button class="ls-btn ls-btn-sm" @click="close">✕</button>
        </header>
        <nav class="flex gap-1 overflow-x-auto border-b border-[var(--bs-border)] px-4" aria-label="Operations">
          <button v-for="key in (['commitments','recurring','counterparties','tags'] as const)" :key="key" class="ls-tab" :class="{ 'ls-tab-active': tab === key }" @click="tab = key">{{ t(`operations.tabs.${key}`) }}</button>
        </nav>
        <main class="min-h-0 flex-1 overflow-y-auto p-5">
          <p v-if="errorMessage" class="ls-error mb-4" role="alert">{{ errorMessage }}</p>

          <section v-if="tab === 'commitments'" class="space-y-5">
            <form v-if="can('commitments.create')" class="ls-card-flat grid gap-3 p-4 md:grid-cols-3" @submit.prevent="createCommitment">
              <input v-model="commitmentForm.title" class="ls-input" :placeholder="t('operations.name')" required>
              <input v-model="commitmentForm.description" class="ls-input" :placeholder="t('transactions.description')">
              <input v-model="commitmentForm.amount" class="ls-input" inputmode="decimal" :placeholder="t('transactions.amount')" required>
              <input v-model="commitmentForm.dueDate" type="date" class="ls-input" required>
              <select v-model="commitmentForm.type" class="ls-input"><option value="payable">{{ t('operations.payable') }}</option><option value="receivable">{{ t('operations.receivable') }}</option><option value="scheduled_expense">{{ t('operations.scheduledExpense') }}</option><option value="scheduled_income">{{ t('operations.scheduledIncome') }}</option></select>
              <select v-model="commitmentForm.categoryId" class="ls-input"><option value="">{{ t('add.chooseCategory') }}</option><option v-for="c in (['receivable','scheduled_income'].includes(commitmentForm.type) ? incomeCategories : expenseCategories)" :key="c.id" :value="c.id">{{ c.name }}</option></select>
              <select v-model="commitmentForm.counterpartyId" class="ls-input"><option value="">{{ t('add.counterparty') }}</option><option v-for="party in counterparties" :key="party.id" :value="party.id">{{ party.name }}</option></select>
              <select v-model="commitmentForm.paymentAccountId" class="ls-input" :required="commitmentForm.autoConvert"><option value="">{{ t('add.chooseAccount') }}</option><option v-for="a in paymentAccounts" :key="a.id" :value="a.id">{{ a.name }}</option></select>
              <label class="flex items-center gap-2 text-sm"><input v-model="commitmentForm.autoConvert" type="checkbox">{{ t('operations.autoConvert') }}</label>
              <label class="flex items-center gap-2 text-sm">{{ t('operations.reminderDays') }} <input v-model.number="commitmentForm.reminderDays" type="number" min="0" max="90" class="ls-input w-24"></label>
              <button class="ls-btn ls-btn-primary md:col-start-3" :disabled="busy">{{ t('operations.addCommitment') }}</button>
            </form>
            <form v-if="commitmentAction.id" class="ls-card-flat grid gap-3 p-4 md:grid-cols-4" @submit.prevent="submitCommitmentAction">
              <template v-if="commitmentAction.mode === 'settle'">
                <select v-model="commitmentAction.paymentAccountId" class="ls-input" required><option value="">{{ t('add.chooseAccount') }}</option><option v-for="account in paymentAccounts" :key="account.id" :value="account.id">{{ account.name }}</option></select>
                <input v-model="commitmentAction.amount" class="ls-input" inputmode="decimal" :placeholder="t('operations.fullOrPartialAmount')">
              </template>
              <input v-model="commitmentAction.date" type="date" class="ls-input" required>
              <div class="flex gap-2"><button class="ls-btn ls-btn-primary" :disabled="busy">{{ t(commitmentAction.mode === 'settle' ? 'operations.convert' : 'operations.postpone') }}</button><button type="button" class="ls-btn" @click="commitmentAction.id = ''">{{ t('common.cancel') }}</button></div>
            </form>
            <div class="ls-card overflow-x-auto"><table class="ls-table"><thead><tr><th>{{ t('operations.name') }}</th><th>{{ t('add.dueDate') }}</th><th>{{ t('transactions.status') }}</th><th class="text-end">{{ t('transactions.amount') }}</th><th><span class="sr-only">{{ t('accounts.actions') }}</span></th></tr></thead><tbody><tr v-for="(row, index) in commitments" :key="row.id ?? index"><td>{{ row.title }}</td><td>{{ formatDate(row.due_date, locale) }}</td><td><StatusBadge :status="row.display_status ?? row.status ?? 'unknown'" /><StatusBadge v-if="row.status === 'partially_paid' && row.display_status !== 'partially_paid'" class="ms-1" :status="row.status" /></td><td class="ls-num"><MoneyText :amount-minor="row.outstanding_minor ?? 0" /></td><td class="whitespace-nowrap"><button v-if="can('commitments.settle') && !['paid','cancelled'].includes(row.status ?? '')" class="ls-btn ls-btn-sm" @click="openCommitmentAction(row.id!, 'settle')">{{ t('operations.settle') }}</button><button v-if="can('commitments.update') && !['paid','cancelled'].includes(row.status ?? '')" class="ls-btn ls-btn-sm ms-1" @click="openCommitmentAction(row.id!, 'postpone')">{{ t('operations.postpone') }}</button><button v-if="can('commitments.update') && !['paid','cancelled'].includes(row.status ?? '')" class="ls-btn ls-btn-sm ms-1" @click="cancelCommitment(row.id!)">{{ t('common.cancel') }}</button></td></tr></tbody></table></div>
          </section>

          <section v-else-if="tab === 'recurring'" class="space-y-5">
            <form v-if="can('recurring.manage')" class="ls-card-flat grid gap-3 p-4 md:grid-cols-3" @submit.prevent="createRecurring">
              <input v-model="recurringForm.name" class="ls-input" :placeholder="t('operations.name')" required><input v-if="recurringForm.transactionType !== 'liability_payment'" v-model="recurringForm.amount" class="ls-input" inputmode="decimal" :placeholder="t('transactions.amount')" required>
              <select v-model="recurringForm.transactionType" class="ls-input"><option value="expense">{{ t('types.expense') }}</option><option value="income">{{ t('types.income') }}</option><option value="liability_payment">{{ t('types.liability_payment') }}</option></select>
              <select v-if="recurringForm.transactionType !== 'liability_payment'" v-model="recurringForm.categoryId" class="ls-input"><option value="">{{ t('add.chooseCategory') }}</option><option v-for="c in (recurringForm.transactionType === 'income' ? incomeCategories : expenseCategories)" :key="c.id" :value="c.id">{{ c.name }}</option></select>
              <template v-else>
                <select v-model="recurringForm.liabilityAccountId" class="ls-input" required><option value="">{{ t('add.liabilityAccount') }}</option><option v-for="account in liabilityAccounts" :key="account.id" :value="account.id">{{ account.name }}</option></select>
                <input v-model="recurringForm.principal" class="ls-input" inputmode="decimal" :placeholder="t('add.principal')" required>
                <input v-model="recurringForm.interest" class="ls-input" inputmode="decimal" :placeholder="t('add.interest')">
                <input v-model="recurringForm.fees" class="ls-input" inputmode="decimal" :placeholder="t('add.fees')">
              </template>
              <select v-model="recurringForm.paymentAccountId" class="ls-input" required><option value="">{{ t('add.chooseAccount') }}</option><option v-for="a in paymentAccounts" :key="a.id" :value="a.id">{{ a.name }}</option></select>
              <label class="flex items-center gap-2 text-sm">{{ t('operations.every') }} <input v-model.number="recurringForm.intervalCount" type="number" min="1" class="ls-input w-24" required></label>
              <input v-model="recurringForm.endDate" type="date" class="ls-input" :aria-label="t('operations.endDate')">
              <input v-model="recurringForm.maxOccurrences" type="number" min="1" class="ls-input" :placeholder="t('operations.maxOccurrences')">
              <select v-model="recurringForm.frequency" class="ls-input"><option v-for="f in ['daily','weekly','monthly','quarterly','yearly']" :key="f" :value="f">{{ f }}</option></select><input v-model="recurringForm.startDate" type="date" class="ls-input"><select v-model="recurringForm.mode" class="ls-input"><option value="requires_confirmation">{{ t('operations.confirmMode') }}</option><option value="auto_post">{{ t('operations.autoPost') }}</option></select><button class="ls-btn ls-btn-primary">{{ t('operations.addRule') }}</button>
            </form>
            <div class="grid gap-4 lg:grid-cols-2"><div class="ls-card p-4"><h3 class="mb-3 font-bold">{{ t('operations.rules') }}</h3><div v-for="rule in rules" :key="rule.id" class="border-b border-[var(--bs-border)] py-3 last:border-0"><div class="flex justify-between gap-3"><span>{{ rule.name }}</span><StatusBadge :status="rule.status" /></div><p class="text-xs text-fg-muted">{{ rule.frequency }} · {{ formatDate(rule.next_run_on, locale) }}</p><button v-if="rule.status === 'active'" class="ls-btn ls-btn-sm mt-2" @click="setRuleStatus(rule.id, 'paused')">{{ t('operations.pause') }}</button><button v-else-if="rule.status === 'paused' || rule.status === 'failed'" class="ls-btn ls-btn-sm mt-2" @click="setRuleStatus(rule.id, 'active')">{{ t('operations.resume') }}</button></div></div><div class="ls-card p-4"><h3 class="mb-3 font-bold">{{ t('operations.occurrences') }}</h3><div v-for="item in occurrences" :key="item.id" class="border-b border-[var(--bs-border)] py-3 last:border-0"><div class="flex justify-between"><span>{{ formatDate(item.occurrence_date, locale) }}</span><StatusBadge :status="item.status" /></div><div class="mt-2"><button v-if="item.status === 'pending'" class="ls-btn ls-btn-sm" @click="occurrenceAction(item.id, 'confirm')">{{ t('operations.confirm') }}</button><button v-if="item.status === 'failed'" class="ls-btn ls-btn-sm" @click="occurrenceAction(item.id, 'retry')">{{ t('operations.retry') }}</button><button v-if="item.status !== 'posted' && item.status !== 'skipped'" class="ls-btn ls-btn-sm ms-1" @click="occurrenceAction(item.id, 'skip')">{{ t('operations.skip') }}</button></div></div></div></div>
          </section>

          <section v-else-if="tab === 'counterparties'" class="space-y-4"><form v-if="can('counterparties.manage')" class="ls-card-flat flex flex-wrap gap-3 p-4" @submit.prevent="createCounterparty"><input v-model="counterpartyForm.name" class="ls-input flex-1" :placeholder="t('operations.name')" required><select v-model="counterpartyForm.type" class="ls-input"><option v-for="type in ['customer','vendor','lender','employee','government','other']" :key="type" :value="type">{{ type }}</option></select><input v-model="counterpartyForm.email" type="email" class="ls-input" :placeholder="t('auth.email')"><input v-model="counterpartyForm.phone" class="ls-input" :placeholder="t('operations.phone')"><input v-model="counterpartyForm.taxIdentifier" class="ls-input" :placeholder="t('operations.taxIdentifier')"><input v-model="counterpartyForm.notes" class="ls-input flex-1" :placeholder="t('operations.notes')"><button class="ls-btn ls-btn-primary">{{ t('common.save') }}</button></form><div class="ls-card p-4"><div v-for="item in counterparties" :key="item.id" class="flex justify-between border-b border-[var(--bs-border)] py-3 last:border-0"><span>{{ item.name }}</span><span class="text-sm text-fg-muted">{{ item.type }}</span></div></div></section>
          <section v-else class="space-y-4"><form v-if="can('tags.manage')" class="ls-card-flat flex gap-3 p-4" @submit.prevent="createTag"><input v-model="tagForm.name" class="ls-input flex-1" :placeholder="t('operations.name')" required><input v-model="tagForm.color" type="color" class="h-10 w-16"><button class="ls-btn ls-btn-primary">{{ t('common.save') }}</button></form><div class="ls-card p-4"><div v-for="item in tags" :key="item.id" class="flex items-center gap-3 border-b border-[var(--bs-border)] py-3 last:border-0"><span class="h-3 w-3 rounded-full" :style="{ backgroundColor: item.color ?? '#64748b' }" />{{ item.name }}</div></div></section>
        </main>
      </div>
    </div>
  </Teleport>
</template>

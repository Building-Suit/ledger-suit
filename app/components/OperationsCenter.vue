<script setup lang="ts">
import type { Database } from '~~/types/database.types'

const supabase = useSupabaseClient<Database>()
const { currentId, baseCurrency, can } = useTenant()
const { open, tab, close, markChanged } = useOperationsCenter()
const { data: accounts } = useOrgAccounts()
const { data: categories } = useOrgCategories()
const { data: counterparties } = useOrgCounterparties()
const toasts = useToasts()
const describeError = useErrorMessage()
const { t } = useI18n()

const paymentAccounts = usePaymentAccounts(accounts)
const liabilityAccounts = computed(() => accounts.value.filter(account => account.type === 'liability' && !account.is_archived))
const incomeCategories = computed(() => categories.value.filter(c => c.kind === 'income'))
const expenseCategories = computed(() => categories.value.filter(c => c.kind === 'expense'))
const busy = ref(false)
const errorMessage = ref<string | null>(null)
const today = () => new Date().toISOString().slice(0, 10)

const commitmentForm = reactive({ type: 'payable', title: '', description: '', amount: '', dueDate: today(), categoryId: '', counterpartyId: '', autoConvert: false, paymentAccountId: '', reminderDays: 3 })
const recurringForm = reactive({ name: '', transactionType: 'expense', amount: '', principal: '', interest: '', fees: '', liabilityAccountId: '', categoryId: '', paymentAccountId: '', frequency: 'monthly', intervalCount: 1, startDate: today(), endDate: '', maxOccurrences: '', mode: 'requires_confirmation' })
const counterpartyForm = reactive({ name: '', type: 'other', email: '', phone: '', taxIdentifier: '', notes: '' })
const tagForm = reactive({ name: '', color: '#2F77C9' })

const title = computed(() => t(tab.value === 'commitments' ? 'operations.addCommitment' : tab.value === 'recurring' ? 'operations.addRule' : tab.value === 'counterparties' ? 'recordPages.addCounterparty' : 'recordPages.addTag'))

watch(open, (isOpen) => {
  if (isOpen) errorMessage.value = null
})

async function run(kind: OperationsTab, action: () => Promise<void>) {
  busy.value = true
  errorMessage.value = null
  try {
    await action()
    markChanged(kind)
    if (kind === 'counterparties') clearNuxtData('org:counterparties')
    if (kind === 'tags') clearNuxtData('org:tags')
    toasts.success(t('operations.saved'))
    close()
  }
  catch (error) { errorMessage.value = describeError(error) }
  finally { busy.value = false }
}

async function createCommitment() {
  const organizationId = currentId.value
  if (!organizationId) return
  await run('commitments', async () => {
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
  })
}

async function createRecurring() {
  const organizationId = currentId.value
  if (!organizationId) return
  await run('recurring', async () => {
    const template: Record<string, unknown> = recurringForm.transactionType === 'liability_payment'
      ? { liability_account_id: recurringForm.liabilityAccountId, payment_account_id: recurringForm.paymentAccountId, principal_minor: Number(parseMoneyToMinor(recurringForm.principal || '0', baseCurrency.value)), interest_minor: Number(parseMoneyToMinor(recurringForm.interest || '0', baseCurrency.value)), fees_minor: Number(parseMoneyToMinor(recurringForm.fees || '0', baseCurrency.value)), description: recurringForm.name }
      : { amount_minor: Number(parseMoneyToMinor(recurringForm.amount, baseCurrency.value)), category_id: recurringForm.categoryId || undefined, description: recurringForm.name, [recurringForm.transactionType === 'expense' ? 'source_account_id' : 'destination_account_id']: recurringForm.paymentAccountId }
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
  })
}

async function createCounterparty() {
  const organizationId = currentId.value
  if (!organizationId) return
  await run('counterparties', async () => {
    const { error } = await supabase.rpc('create_counterparty', {
      p_organization_id: organizationId,
      p_name: counterpartyForm.name,
      p_type: counterpartyForm.type as Database['public']['Enums']['counterparty_type'],
      p_email: counterpartyForm.email || undefined,
      p_phone: counterpartyForm.phone || undefined,
      p_tax_identifier: counterpartyForm.taxIdentifier || undefined,
      p_notes: counterpartyForm.notes || undefined,
    })
    if (error) throw error
    Object.assign(counterpartyForm, { name: '', email: '', phone: '', taxIdentifier: '', notes: '' })
  })
}

async function createTag() {
  const organizationId = currentId.value
  if (!organizationId) return
  await run('tags', async () => {
    const { error } = await supabase.from('tags').insert({ organization_id: organizationId, name: tagForm.name, color: tagForm.color, created_by: (await supabase.auth.getUser()).data.user?.id ?? null })
    if (error) throw error
    tagForm.name = ''
  })
}
</script>

<template>
  <Teleport to="body">
    <Transition name="ls-modal">
      <div v-if="open" class="fixed inset-0 z-50 grid place-items-center ls-scrim p-4" role="dialog" aria-modal="true" :aria-label="title" @click.self="close">
        <div class="ls-modal-panel ls-card flex max-h-[92dvh] w-full max-w-4xl flex-col overflow-hidden shadow-overlay">
          <header class="flex items-center justify-between border-b border-[var(--bs-border)] px-6 py-4">
            <h2 class="text-lg font-bold">{{ title }}</h2>
            <button type="button" class="ls-btn ls-btn-sm" :aria-label="t('common.close')" @click="close"><AppIcon name="close" /></button>
          </header>
          <main class="min-h-0 flex-1 overflow-y-auto p-6">
            <p v-if="errorMessage" class="ls-error mb-4" role="alert">{{ errorMessage }}</p>

            <form v-if="tab === 'commitments' && can('commitments.create')" class="grid gap-3 md:grid-cols-2" @submit.prevent="createCommitment">
              <FloatingField :label="t('operations.name')"><input v-model="commitmentForm.title" class="ls-input" :placeholder="t('operations.name')" required></FloatingField>
              <FloatingField :label="t('transactions.description')"><input v-model="commitmentForm.description" class="ls-input" :placeholder="t('transactions.description')"></FloatingField>
              <FloatingField :label="t('transactions.amount')"><input v-model="commitmentForm.amount" class="ls-input" inputmode="decimal" :placeholder="t('transactions.amount')" required></FloatingField>
              <FloatingField :label="t('add.dueDate')"><input v-model="commitmentForm.dueDate" type="date" class="ls-input" required></FloatingField>
              <FloatingField :label="t('transactions.type')"><select v-model="commitmentForm.type" class="ls-input"><option value="payable">{{ t('operations.payable') }}</option><option value="receivable">{{ t('operations.receivable') }}</option><option value="scheduled_expense">{{ t('operations.scheduledExpense') }}</option><option value="scheduled_income">{{ t('operations.scheduledIncome') }}</option></select></FloatingField>
              <FloatingField :label="t('add.category')"><select v-model="commitmentForm.categoryId" class="ls-input"><option value="">{{ t('add.chooseCategory') }}</option><option v-for="c in (['receivable','scheduled_income'].includes(commitmentForm.type) ? incomeCategories : expenseCategories)" :key="c.id" :value="c.id">{{ c.name }}</option></select></FloatingField>
              <FloatingField :label="t('add.counterparty')"><select v-model="commitmentForm.counterpartyId" class="ls-input"><option value="">{{ t('add.counterparty') }}</option><option v-for="party in counterparties" :key="party.id" :value="party.id">{{ party.name }}</option></select></FloatingField>
              <FloatingField :label="t('add.chooseAccount')"><select v-model="commitmentForm.paymentAccountId" class="ls-input" :required="commitmentForm.autoConvert"><option value="">{{ t('add.chooseAccount') }}</option><option v-for="a in paymentAccounts" :key="a.id" :value="a.id">{{ a.name }}</option></select></FloatingField>
              <label class="flex items-center gap-2 text-sm"><input v-model="commitmentForm.autoConvert" type="checkbox">{{ t('operations.autoConvert') }}</label>
              <label class="flex items-center gap-2 text-sm">{{ t('operations.reminderDays') }} <input v-model.number="commitmentForm.reminderDays" type="number" min="0" max="90" class="ls-input w-24"></label>
              <div class="flex justify-end gap-2 md:col-span-2"><button type="button" class="ls-btn" @click="close">{{ t('common.cancel') }}</button><button class="ls-btn ls-btn-primary" :disabled="busy">{{ t('operations.addCommitment') }}</button></div>
            </form>

            <form v-else-if="tab === 'recurring' && can('recurring.manage')" class="grid gap-3 md:grid-cols-3" @submit.prevent="createRecurring">
              <FloatingField :label="t('operations.name')"><input v-model="recurringForm.name" class="ls-input" :placeholder="t('operations.name')" required></FloatingField><FloatingField v-if="recurringForm.transactionType !== 'liability_payment'" :label="t('transactions.amount')"><input v-model="recurringForm.amount" class="ls-input" inputmode="decimal" :placeholder="t('transactions.amount')" required></FloatingField>
              <FloatingField :label="t('transactions.type')"><select v-model="recurringForm.transactionType" class="ls-input"><option value="expense">{{ t('types.expense') }}</option><option value="income">{{ t('types.income') }}</option><option value="liability_payment">{{ t('types.liability_payment') }}</option></select></FloatingField>
              <FloatingField v-if="recurringForm.transactionType !== 'liability_payment'" :label="t('add.category')"><select v-model="recurringForm.categoryId" class="ls-input"><option value="">{{ t('add.chooseCategory') }}</option><option v-for="c in (recurringForm.transactionType === 'income' ? incomeCategories : expenseCategories)" :key="c.id" :value="c.id">{{ c.name }}</option></select></FloatingField>
              <template v-else><select v-model="recurringForm.liabilityAccountId" class="ls-input" required><option value="">{{ t('add.liabilityAccount') }}</option><option v-for="account in liabilityAccounts" :key="account.id" :value="account.id">{{ account.name }}</option></select><input v-model="recurringForm.principal" class="ls-input" inputmode="decimal" :placeholder="t('add.principal')" required><input v-model="recurringForm.interest" class="ls-input" inputmode="decimal" :placeholder="t('add.interest')"><input v-model="recurringForm.fees" class="ls-input" inputmode="decimal" :placeholder="t('add.fees')"></template>
              <select v-model="recurringForm.paymentAccountId" class="ls-input" required><option value="">{{ t('add.chooseAccount') }}</option><option v-for="a in paymentAccounts" :key="a.id" :value="a.id">{{ a.name }}</option></select>
              <label class="flex items-center gap-2 text-sm">{{ t('operations.every') }} <input v-model.number="recurringForm.intervalCount" type="number" min="1" class="ls-input w-24" required></label>
              <input v-model="recurringForm.endDate" type="date" class="ls-input" :aria-label="t('operations.endDate')"><input v-model="recurringForm.maxOccurrences" type="number" min="1" class="ls-input" :placeholder="t('operations.maxOccurrences')"><select v-model="recurringForm.frequency" class="ls-input"><option v-for="f in ['daily','weekly','monthly','quarterly','yearly']" :key="f" :value="f">{{ f }}</option></select><input v-model="recurringForm.startDate" type="date" class="ls-input"><select v-model="recurringForm.mode" class="ls-input"><option value="requires_confirmation">{{ t('operations.confirmMode') }}</option><option value="auto_post">{{ t('operations.autoPost') }}</option></select>
              <div class="flex justify-end gap-2 md:col-span-3"><button type="button" class="ls-btn" @click="close">{{ t('common.cancel') }}</button><button class="ls-btn ls-btn-primary" :disabled="busy">{{ t('operations.addRule') }}</button></div>
            </form>

            <form v-else-if="tab === 'counterparties' && can('counterparties.manage')" class="grid gap-3 md:grid-cols-2" @submit.prevent="createCounterparty"><input v-model="counterpartyForm.name" class="ls-input" :placeholder="t('operations.name')" required><select v-model="counterpartyForm.type" class="ls-input"><option v-for="type in ['customer','vendor','lender','employee','government','other']" :key="type" :value="type">{{ type }}</option></select><input v-model="counterpartyForm.email" type="email" class="ls-input" :placeholder="t('auth.email')"><input v-model="counterpartyForm.phone" class="ls-input" :placeholder="t('operations.phone')"><input v-model="counterpartyForm.taxIdentifier" class="ls-input" :placeholder="t('operations.taxIdentifier')"><input v-model="counterpartyForm.notes" class="ls-input" :placeholder="t('operations.notes')"><div class="flex justify-end gap-2 md:col-span-2"><button type="button" class="ls-btn" @click="close">{{ t('common.cancel') }}</button><button class="ls-btn ls-btn-primary" :disabled="busy">{{ t('common.save') }}</button></div></form>

            <form v-else-if="can('tags.manage')" class="space-y-4" @submit.prevent="createTag"><input v-model="tagForm.name" class="ls-input" :placeholder="t('operations.name')" required><input v-model="tagForm.color" type="color" class="h-12 w-full rounded-control border border-[var(--bs-border)] bg-surface p-1"><div class="flex justify-end gap-2"><button type="button" class="ls-btn" @click="close">{{ t('common.cancel') }}</button><button class="ls-btn ls-btn-primary" :disabled="busy">{{ t('common.save') }}</button></div></form>
          </main>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

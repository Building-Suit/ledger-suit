<script setup lang="ts">
import type { Database } from '~~/types/database.types'

/**
 * The single entry point for recording money.
 *
 * The user picks a plain-language flow ("Expense") and fills in plain-language
 * fields. No debit or credit appears anywhere — the database derives the
 * journal. The one exception is Adjustment, which is explicitly the accountant's
 * manual-journal tool.
 */

const supabase = useSupabaseClient<Database>()
const { currentId, baseCurrency, can } = useTenant()
const { open, flow, close } = useAddTransaction()
const toasts = useToasts()
const { t } = useI18n()
const describeError = useErrorMessage()

const { data: accounts } = await useOrgAccounts()
const { data: categories } = await useOrgCategories()
const { data: counterparties } = await useOrgCounterparties()

const paymentAccounts = usePaymentAccounts(accounts)
const assetAccounts = useAccountsOfType(accounts, ['asset'])
const liabilityAccounts = useAccountsOfType(accounts, ['liability'])
const equityAccounts = useAccountsOfType(accounts, ['equity'])
const postableAccounts = useAccountsOfType(accounts, ['asset', 'liability', 'equity', 'revenue', 'expense'])

const incomeCategories = computed(() => categories.value.filter(c => c.kind === 'income'))
const expenseCategories = computed(() => categories.value.filter(c => c.kind === 'expense'))

const availableFlows = computed(() => ADD_FLOWS.filter(f => can(FLOW_CAPABILITY[f])))

interface JournalLine {
  accountId: string
  side: 'debit' | 'credit'
  amount: string
}

const today = () => new Date().toISOString().slice(0, 10)

const form = reactive({
  amount: '',
  date: today(),
  description: '',
  reference: '',
  counterpartyId: '',
  categoryId: '',
  sourceAccountId: '',
  destinationAccountId: '',
  assetAccountId: '',
  liabilityAccountId: '',
  equityAccountId: '',
  feeAmount: '',
  principal: '',
  interest: '',
  fees: '',
  dueDate: '',
  usefulLifeMonths: '',
  reason: '',
  lines: [] as JournalLine[],
})

const submitting = ref(false)
const fieldError = ref<string | null>(null)

// One key per dialog session: a double-click, or a retry after a dropped
// response, resolves to the same transaction instead of posting twice.
const idempotencyKey = ref('')

function resetForm() {
  Object.assign(form, {
    amount: '',
    date: today(),
    description: '',
    reference: '',
    counterpartyId: '',
    categoryId: '',
    sourceAccountId: '',
    destinationAccountId: '',
    assetAccountId: '',
    liabilityAccountId: '',
    equityAccountId: '',
    feeAmount: '',
    principal: '',
    interest: '',
    fees: '',
    dueDate: '',
    usefulLifeMonths: '',
    reason: '',
    lines: [
      { accountId: '', side: 'debit', amount: '' },
      { accountId: '', side: 'credit', amount: '' },
    ],
  })
  fieldError.value = null
  idempotencyKey.value = crypto.randomUUID()
}

watch(open, (isOpen) => {
  if (isOpen) resetForm()
})

/** Parses an amount field, returning null and setting an error if invalid. */
function toMinor(input: string, label: string): number | null {
  try {
    const minor = parseMoneyToMinor(input, baseCurrency.value)
    if (minor <= 0n) {
      fieldError.value = t('add.validation.amountPositive', { field: label })
      return null
    }
    if (minor > BigInt(Number.MAX_SAFE_INTEGER)) {
      fieldError.value = t('add.validation.amountTooLarge', { field: label })
      return null
    }
    return Number(minor)
  }
  catch {
    fieldError.value = t('add.validation.amountInvalid', { field: label })
    return null
  }
}

function optionalMinor(input: string, label: string): number | null | undefined {
  if (!input.trim()) return 0
  return toMinor(input, label)
}

const adjustmentTotals = computed(() => {
  let debit = 0n
  let credit = 0n
  for (const line of form.lines) {
    if (!line.amount.trim()) continue
    try {
      const minor = parseMoneyToMinor(line.amount, baseCurrency.value)
      if (line.side === 'debit') debit += minor
      else credit += minor
    }
    catch { /* an unparseable line simply does not count yet */ }
  }
  return { debit, credit, balanced: debit === credit && debit > 0n }
})

function addLine() {
  form.lines.push({ accountId: '', side: 'debit', amount: '' })
}

function removeLine(index: number) {
  if (form.lines.length <= 2) return
  form.lines.splice(index, 1)
}

const nullable = (value: string) => (value.trim() === '' ? null : value)

async function submit() {
  if (!currentId.value) return
  fieldError.value = null
  submitting.value = true

  try {
    const org = currentId.value
    const shared = {
      p_organization_id: org,
      p_transaction_date: form.date,
      p_description: nullable(form.description),
      p_reference: nullable(form.reference),
      p_idempotency_key: idempotencyKey.value,
    }

    let rpc: { fn: string, args: Record<string, unknown> } | null = null

    switch (flow.value) {
      case 'income': {
        const amount = toMinor(form.amount, t('transactions.amount'))
        if (amount === null) return
        rpc = { fn: 'record_income', args: {
          ...shared,
          p_amount_minor: amount,
          p_destination_account_id: form.destinationAccountId,
          p_category_id: nullable(form.categoryId),
          p_counterparty_id: nullable(form.counterpartyId),
        } }
        break
      }

      case 'expense': {
        const amount = toMinor(form.amount, t('transactions.amount'))
        if (amount === null) return
        rpc = { fn: 'record_expense', args: {
          ...shared,
          p_amount_minor: amount,
          p_source_account_id: form.sourceAccountId,
          p_category_id: nullable(form.categoryId),
          p_counterparty_id: nullable(form.counterpartyId),
        } }
        break
      }

      case 'transfer': {
        const amount = toMinor(form.amount, t('transactions.amount'))
        if (amount === null) return
        const fee = optionalMinor(form.feeAmount, t('add.transferFee'))
        if (fee === null) return
        rpc = { fn: 'record_transfer', args: {
          ...shared,
          p_amount_minor: amount,
          p_from_account_id: form.sourceAccountId,
          p_to_account_id: form.destinationAccountId,
          p_fee_minor: fee,
        } }
        break
      }

      case 'asset_purchase': {
        const amount = toMinor(form.amount, t('transactions.amount'))
        if (amount === null) return
        rpc = { fn: 'record_asset_purchase', args: {
          ...shared,
          p_amount_minor: amount,
          p_asset_account_id: form.assetAccountId,
          p_payment_account_id: form.sourceAccountId,
          p_counterparty_id: nullable(form.counterpartyId),
          p_useful_life_months: form.usefulLifeMonths ? Number(form.usefulLifeMonths) : null,
        } }
        break
      }

      case 'liability_created': {
        const amount = toMinor(form.amount, t('transactions.amount'))
        if (amount === null) return
        rpc = { fn: 'record_liability_created', args: {
          ...shared,
          p_amount_minor: amount,
          p_liability_account_id: form.liabilityAccountId,
          p_destination_account_id: form.destinationAccountId,
          p_counterparty_id: nullable(form.counterpartyId),
          p_due_date: nullable(form.dueDate),
        } }
        break
      }

      case 'liability_payment': {
        const principal = optionalMinor(form.principal, t('add.principal'))
        const interest = optionalMinor(form.interest, t('add.interest'))
        const fees = optionalMinor(form.fees, t('add.fees'))
        if (principal === null || interest === null || fees === null) return
        if ((principal ?? 0) + (interest ?? 0) + (fees ?? 0) <= 0) {
          fieldError.value = t('add.validation.paymentRequired')
          return
        }
        rpc = { fn: 'record_liability_payment', args: {
          ...shared,
          p_liability_account_id: form.liabilityAccountId,
          p_payment_account_id: form.sourceAccountId,
          p_principal_minor: principal,
          p_interest_minor: interest,
          p_fees_minor: fees,
          p_counterparty_id: nullable(form.counterpartyId),
        } }
        break
      }

      case 'owner_contribution': {
        const amount = toMinor(form.amount, t('transactions.amount'))
        if (amount === null) return
        rpc = { fn: 'record_owner_contribution', args: {
          ...shared,
          p_amount_minor: amount,
          p_destination_account_id: form.destinationAccountId,
          p_equity_account_id: nullable(form.equityAccountId),
        } }
        break
      }

      case 'owner_withdrawal': {
        const amount = toMinor(form.amount, t('transactions.amount'))
        if (amount === null) return
        rpc = { fn: 'record_owner_withdrawal', args: {
          ...shared,
          p_amount_minor: amount,
          p_source_account_id: form.sourceAccountId,
          p_drawings_account_id: nullable(form.equityAccountId),
        } }
        break
      }

      case 'adjustment': {
        if (!adjustmentTotals.value.balanced) {
          fieldError.value = t('add.validation.mustBalance')
          return
        }
        if (!form.description.trim() || !form.reason.trim()) {
          fieldError.value = t('add.validation.descriptionAndReason')
          return
        }

        const lines = form.lines
          .filter(l => l.accountId && l.amount.trim())
          .map(l => ({
            account_id: l.accountId,
            side: l.side,
            amount_minor: Number(parseMoneyToMinor(l.amount, baseCurrency.value)),
          }))

        rpc = { fn: 'create_adjustment', args: {
          p_organization_id: org,
          p_transaction_date: form.date,
          p_lines: lines,
          p_description: form.description,
          p_reason: form.reason,
          p_idempotency_key: idempotencyKey.value,
        } }
        break
      }
    }

    if (!rpc) return

    const { error } = await supabase.rpc(rpc.fn as never, rpc.args as never)
    if (error) throw error

    toasts.success(t('add.savedTitle'), t('add.savedBody'))
    close()
    await refreshNuxtData()
  }
  catch (err) {
    fieldError.value = describeError(err)
  }
  finally {
    submitting.value = false
  }
}


</script>

<template>
  <Teleport to="body">
    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-end justify-center ls-scrim p-0 sm:items-center sm:p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="add-transaction-title"
      @click.self="close()"
    >
      <div class="ls-card flex max-h-[92dvh] w-full max-w-2xl flex-col overflow-hidden rounded-b-none shadow-overlay sm:rounded-modal">
        <header class="flex items-center justify-between border-b border-[var(--bs-border)] px-6 py-4">
          <h2 id="add-transaction-title" class="text-base font-bold">
            {{ t(`add.flows.${flow}`) }}
          </h2>
          <button type="button" class="ls-btn ls-btn-sm" :aria-label="t('common.close')" @click="close()">
            ✕
          </button>
        </header>

        <div class="border-b border-[var(--bs-border)] px-6 py-3">
          <label class="ls-label" for="flow">{{ t('add.whatAreYouRecording') }}</label>
          <select id="flow" v-model="flow" class="ls-input">
            <option v-for="f in availableFlows" :key="f" :value="f">
              {{ t(`add.flows.${f}`) }} — {{ t(`add.hints.${f}`) }}
            </option>
          </select>
        </div>

        <form class="min-h-0 flex-1 overflow-y-auto px-6 py-4" @submit.prevent="submit">
          <div class="grid gap-4 sm:grid-cols-2">
            <!-- Amount: every flow except the split ones -->
            <div v-if="!['liability_payment', 'adjustment'].includes(flow)">
              <label class="ls-label" for="amount">{{ t('add.amount', { currency: baseCurrency }) }}</label>
              <input id="amount" v-model="form.amount" class="ls-input" inputmode="decimal" placeholder="0.00" required>
            </div>

            <div>
              <label class="ls-label" for="date">{{ t('add.date') }}</label>
              <input id="date" v-model="form.date" type="date" class="ls-input" required>
            </div>

            <!-- Income -->
            <template v-if="flow === 'income'">
              <div>
                <label class="ls-label" for="dest">{{ t('add.receivedInto') }}</label>
                <select id="dest" v-model="form.destinationAccountId" class="ls-input" required>
                  <option value="" disabled>{{ t('add.chooseAccount') }}</option>
                  <option v-for="a in paymentAccounts" :key="a.id" :value="a.id">{{ a.name }}</option>
                </select>
              </div>
              <div>
                <label class="ls-label" for="cat">{{ t('add.category') }}</label>
                <select id="cat" v-model="form.categoryId" class="ls-input" required>
                  <option value="" disabled>{{ t('add.chooseCategory') }}</option>
                  <option v-for="c in incomeCategories" :key="c.id" :value="c.id">{{ c.name }}</option>
                </select>
              </div>
            </template>

            <!-- Expense -->
            <template v-if="flow === 'expense'">
              <div>
                <label class="ls-label" for="src">{{ t('add.paidFrom') }}</label>
                <select id="src" v-model="form.sourceAccountId" class="ls-input" required>
                  <option value="" disabled>{{ t('add.chooseAccount') }}</option>
                  <option v-for="a in paymentAccounts" :key="a.id" :value="a.id">{{ a.name }}</option>
                </select>
              </div>
              <div>
                <label class="ls-label" for="cat">{{ t('add.category') }}</label>
                <select id="cat" v-model="form.categoryId" class="ls-input" required>
                  <option value="" disabled>{{ t('add.chooseCategory') }}</option>
                  <option v-for="c in expenseCategories" :key="c.id" :value="c.id">{{ c.name }}</option>
                </select>
              </div>
            </template>

            <!-- Transfer -->
            <template v-if="flow === 'transfer'">
              <div>
                <label class="ls-label" for="src">{{ t('add.from') }}</label>
                <select id="src" v-model="form.sourceAccountId" class="ls-input" required>
                  <option value="" disabled>{{ t('add.chooseAccount') }}</option>
                  <option v-for="a in paymentAccounts" :key="a.id" :value="a.id">{{ a.name }}</option>
                </select>
              </div>
              <div>
                <label class="ls-label" for="dest">{{ t('add.to') }}</label>
                <select id="dest" v-model="form.destinationAccountId" class="ls-input" required>
                  <option value="" disabled>{{ t('add.chooseAccount') }}</option>
                  <option v-for="a in paymentAccounts" :key="a.id" :value="a.id">{{ a.name }}</option>
                </select>
              </div>
              <div>
                <label class="ls-label" for="fee">{{ t('add.transferFee') }} ({{ t('common.optional') }})</label>
                <input id="fee" v-model="form.feeAmount" class="ls-input" inputmode="decimal" placeholder="0.00">
                <p class="ls-hint">{{ t('add.transferFeeHint') }}</p>
              </div>
            </template>

            <!-- Asset purchase -->
            <template v-if="flow === 'asset_purchase'">
              <div>
                <label class="ls-label" for="asset">{{ t('add.assetAccount') }}</label>
                <select id="asset" v-model="form.assetAccountId" class="ls-input" required>
                  <option value="" disabled>{{ t('add.chooseAccount') }}</option>
                  <option v-for="a in assetAccounts" :key="a.id" :value="a.id">{{ a.name }}</option>
                </select>
              </div>
              <div>
                <label class="ls-label" for="src">{{ t('add.paidFrom') }}</label>
                <select id="src" v-model="form.sourceAccountId" class="ls-input" required>
                  <option value="" disabled>{{ t('add.chooseAccount') }}</option>
                  <option v-for="a in paymentAccounts" :key="a.id" :value="a.id">{{ a.name }}</option>
                </select>
              </div>
              <div>
                <label class="ls-label" for="life">{{ t('add.usefulLife') }} ({{ t('common.optional') }})</label>
                <input id="life" v-model="form.usefulLifeMonths" type="number" min="1" class="ls-input">
                <p class="ls-hint">{{ t('add.usefulLifeHint') }}</p>
              </div>
            </template>

            <!-- Liability created -->
            <template v-if="flow === 'liability_created'">
              <div>
                <label class="ls-label" for="liab">{{ t('add.liabilityAccount') }}</label>
                <select id="liab" v-model="form.liabilityAccountId" class="ls-input" required>
                  <option value="" disabled>{{ t('add.chooseAccount') }}</option>
                  <option v-for="a in liabilityAccounts" :key="a.id" :value="a.id">{{ a.name }}</option>
                </select>
              </div>
              <div>
                <label class="ls-label" for="dest">{{ t('add.receivedInto') }}</label>
                <select id="dest" v-model="form.destinationAccountId" class="ls-input" required>
                  <option value="" disabled>{{ t('add.chooseAccount') }}</option>
                  <option v-for="a in paymentAccounts" :key="a.id" :value="a.id">{{ a.name }}</option>
                </select>
              </div>
              <div>
                <label class="ls-label" for="due">{{ t('add.dueDate') }} ({{ t('common.optional') }})</label>
                <input id="due" v-model="form.dueDate" type="date" class="ls-input">
              </div>
            </template>

            <!-- Liability payment -->
            <template v-if="flow === 'liability_payment'">
              <div>
                <label class="ls-label" for="liab">{{ t('add.liability') }}</label>
                <select id="liab" v-model="form.liabilityAccountId" class="ls-input" required>
                  <option value="" disabled>{{ t('add.chooseAccount') }}</option>
                  <option v-for="a in liabilityAccounts" :key="a.id" :value="a.id">{{ a.name }}</option>
                </select>
              </div>
              <div>
                <label class="ls-label" for="src">{{ t('add.paidFrom') }}</label>
                <select id="src" v-model="form.sourceAccountId" class="ls-input" required>
                  <option value="" disabled>{{ t('add.chooseAccount') }}</option>
                  <option v-for="a in paymentAccounts" :key="a.id" :value="a.id">{{ a.name }}</option>
                </select>
              </div>
              <div>
                <label class="ls-label" for="principal">{{ t('add.principal') }}</label>
                <input id="principal" v-model="form.principal" class="ls-input" inputmode="decimal" placeholder="0.00">
              </div>
              <div>
                <label class="ls-label" for="interest">{{ t('add.interest') }}</label>
                <input id="interest" v-model="form.interest" class="ls-input" inputmode="decimal" placeholder="0.00">
              </div>
              <div>
                <label class="ls-label" for="fees">{{ t('add.fees') }}</label>
                <input id="fees" v-model="form.fees" class="ls-input" inputmode="decimal" placeholder="0.00">
                <p class="ls-hint">{{ t('add.liabilityPaymentHint') }}</p>
              </div>
            </template>

            <!-- Owner contribution -->
            <template v-if="flow === 'owner_contribution'">
              <div>
                <label class="ls-label" for="dest">{{ t('add.receivedInto') }}</label>
                <select id="dest" v-model="form.destinationAccountId" class="ls-input" required>
                  <option value="" disabled>{{ t('add.chooseAccount') }}</option>
                  <option v-for="a in paymentAccounts" :key="a.id" :value="a.id">{{ a.name }}</option>
                </select>
              </div>
              <div>
                <label class="ls-label" for="equity">{{ t('add.equityAccount') }} ({{ t('common.optional') }})</label>
                <select id="equity" v-model="form.equityAccountId" class="ls-input">
                  <option value="">{{ t('add.ownerCapitalDefault') }}</option>
                  <option v-for="a in equityAccounts" :key="a.id" :value="a.id">{{ a.name }}</option>
                </select>
              </div>
            </template>

            <!-- Owner withdrawal -->
            <template v-if="flow === 'owner_withdrawal'">
              <div>
                <label class="ls-label" for="src">{{ t('add.takenFrom') }}</label>
                <select id="src" v-model="form.sourceAccountId" class="ls-input" required>
                  <option value="" disabled>{{ t('add.chooseAccount') }}</option>
                  <option v-for="a in paymentAccounts" :key="a.id" :value="a.id">{{ a.name }}</option>
                </select>
              </div>
              <div>
                <label class="ls-label" for="equity">{{ t('add.drawingsAccount') }} ({{ t('common.optional') }})</label>
                <select id="equity" v-model="form.equityAccountId" class="ls-input">
                  <option value="">{{ t('add.ownerDrawingsDefault') }}</option>
                  <option v-for="a in equityAccounts" :key="a.id" :value="a.id">{{ a.name }}</option>
                </select>
              </div>
            </template>

            <!-- Counterparty, where it means something -->
            <div v-if="['income', 'expense', 'asset_purchase', 'liability_created', 'liability_payment'].includes(flow)">
              <label class="ls-label" for="cp">{{ t('add.counterparty') }} ({{ t('common.optional') }})</label>
              <select id="cp" v-model="form.counterpartyId" class="ls-input">
                <option value="">{{ t('common.none') }}</option>
                <option v-for="c in counterparties" :key="c.id" :value="c.id">{{ c.name }}</option>
              </select>
            </div>

            <div :class="flow === 'adjustment' ? 'sm:col-span-2' : ''">
              <label class="ls-label" for="descr">{{ t('add.description') }}</label>
              <input
                id="descr"
                v-model="form.description"
                class="ls-input"
                :required="flow === 'adjustment'"
                :placeholder="t('add.descriptionPlaceholder')"
              >
            </div>

            <div v-if="flow !== 'adjustment'">
              <label class="ls-label" for="ref">{{ t('add.reference') }} ({{ t('common.optional') }})</label>
              <input id="ref" v-model="form.reference" class="ls-input" :placeholder="t('add.referencePlaceholder')">
            </div>

            <div v-if="flow === 'adjustment'" class="sm:col-span-2">
              <label class="ls-label" for="reason">{{ t('add.adjustmentReason') }}</label>
              <input id="reason" v-model="form.reason" class="ls-input" required :placeholder="t('add.adjustmentReasonPlaceholder')">
            </div>
          </div>

          <!-- Manual journal -->
          <div v-if="flow === 'adjustment'" class="mt-6">
            <div class="mb-2 flex items-center justify-between">
              <h3 class="text-sm font-bold">{{ t('add.journalLines') }}</h3>
              <button type="button" class="ls-btn ls-btn-sm" @click="addLine">{{ t('add.addLine') }}</button>
            </div>

            <div class="space-y-2">
              <div
                v-for="(line, index) in form.lines"
                :key="index"
                class="grid grid-cols-[1fr_7rem_8rem_2rem] items-end gap-2"
              >
                <div>
                  <label class="sr-only" :for="`line-account-${index}`">{{ t('detail.account') }}</label>
                  <select :id="`line-account-${index}`" v-model="line.accountId" class="ls-input">
                    <option value="" disabled>{{ t('detail.account') }}</option>
                    <option v-for="a in postableAccounts" :key="a.id" :value="a.id">
                      {{ a.code ? `${a.code} · ` : '' }}{{ a.name }}
                    </option>
                  </select>
                </div>
                <div>
                  <label class="sr-only" :for="`line-side-${index}`">{{ t('add.side') }}</label>
                  <select :id="`line-side-${index}`" v-model="line.side" class="ls-input">
                    <option value="debit">{{ t('add.debit') }}</option>
                    <option value="credit">{{ t('add.credit') }}</option>
                  </select>
                </div>
                <div>
                  <label class="sr-only" :for="`line-amount-${index}`">{{ t('transactions.amount') }}</label>
                  <input :id="`line-amount-${index}`" v-model="line.amount" class="ls-input" inputmode="decimal" placeholder="0.00">
                </div>
                <button
                  type="button"
                  class="ls-btn ls-btn-sm h-9"
                  :disabled="form.lines.length <= 2"
                  :aria-label="t('add.removeLine', { index: index + 1 })"
                  @click="removeLine(index)"
                >
                  ✕
                </button>
              </div>
            </div>

            <div class="mt-3 flex flex-wrap items-center justify-between gap-2 rounded-control bg-surface-muted px-3 py-2 text-sm">
              <span>
                {{ t('add.debitsTotal') }} <MoneyText :amount-minor="Number(adjustmentTotals.debit)" />
                · {{ t('add.creditsTotal') }} <MoneyText :amount-minor="Number(adjustmentTotals.credit)" />
              </span>
              <span
                class="font-semibold"
                :class="adjustmentTotals.balanced ? 'text-[var(--bs-status-success)]' : 'text-[var(--bs-status-error)]'"
              >
                {{ adjustmentTotals.balanced ? t('add.balanced') : t('add.notBalanced') }}
              </span>
            </div>
          </div>

          <p v-if="fieldError" role="alert" class="ls-error mt-4">
            {{ fieldError }}
          </p>
        </form>

        <footer class="flex items-center justify-end gap-2 border-t border-[var(--bs-border)] px-6 py-4">
          <button type="button" class="ls-btn" @click="close()">{{ t('common.cancel') }}</button>
          <button
            type="button"
            class="ls-btn ls-btn-accent"
            :disabled="submitting"
            @click="submit"
          >
            {{ submitting ? t('common.saving') : t('common.save') }}
          </button>
        </footer>
      </div>
    </div>
  </Teleport>
</template>

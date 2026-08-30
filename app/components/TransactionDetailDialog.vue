<script setup lang="ts">
import type { Database } from '~~/types/database.types'

/**
 * Transaction detail, including the journal behind it.
 *
 * The journal is the "advanced view" from spec section 75 — the same posting a
 * non-accountant created without ever seeing a debit or a credit. Correcting a
 * posted transaction is only offered as a reversal, because that is the only
 * thing the database permits.
 */

const props = defineProps<{ transactionId: string | null }>()
const emit = defineEmits<{ close: [], changed: [] }>()

const supabase = useSupabaseClient<Database>()
const { can } = useTenant()
const toasts = useToasts()
const { t, locale } = useI18n()
const describeError = useErrorMessage()

const reversing = ref(false)
const reason = ref('')
const confirming = ref(false)
const errorMessage = ref<string | null>(null)

const { data: detail, refresh } = await useAsyncData(
  'transaction-detail',
  async () => {
    if (!props.transactionId) return null

    const [{ data: transaction, error: txError }, { data: entries, error: entryError }] =
      await Promise.all([
        supabase
          .from('transaction_summaries')
          .select('*')
          .eq('id', props.transactionId)
          .maybeSingle(),
        supabase
          .from('ledger_entries')
          .select('entry_id, side, amount_minor, currency_code, base_amount_minor, memo, account_code, account_name, account_type')
          .eq('transaction_id', props.transactionId)
          .order('side', { ascending: true }),
      ])

    if (txError) throw txError
    if (entryError) throw entryError

    return { transaction, entries: entries ?? [] }
  },
  { watch: [() => props.transactionId] },
)

const transaction = computed(() => detail.value?.transaction ?? null)
const entries = computed(() => detail.value?.entries ?? [])

const canReverse = computed(
  () => can('transactions.reverse') && transaction.value?.status === 'posted',
)

async function reverse() {
  if (!props.transactionId) return
  if (!reason.value.trim()) {
    errorMessage.value = t('detail.reverseReasonRequired')
    return
  }

  reversing.value = true
  errorMessage.value = null

  try {
    const { error } = await supabase.rpc('reverse_transaction', {
      p_transaction_id: props.transactionId,
      p_reason: reason.value,
    })
    if (error) throw error

    toasts.success(t('detail.reversedTitle'), t('detail.reversedBody'))
    confirming.value = false
    reason.value = ''
    await refresh()
    emit('changed')
  }
  catch (err) {
    errorMessage.value = describeError(err)
  }
  finally {
    reversing.value = false
  }
}
</script>

<template>
  <Teleport to="body">
    <div
      v-if="transactionId"
      class="fixed inset-0 z-50 flex justify-end bg-black/40"
      role="dialog"
      aria-modal="true"
      aria-labelledby="transaction-detail-title"
      @click.self="emit('close')"
    >
      <div class="flex h-full w-full max-w-xl flex-col overflow-hidden border-s border-[var(--bs-border)] bg-surface">
        <header class="flex items-start justify-between gap-3 border-b border-[var(--bs-border)] px-6 py-4">
          <div class="min-w-0">
            <h2 id="transaction-detail-title" class="truncate text-base font-bold">
              {{ transaction?.description || t('detail.title') }}
            </h2>
            <p class="mt-1 flex items-center gap-2 text-sm text-fg-muted">
              <StatusBadge v-if="transaction?.status" :status="transaction.status" />
              <span v-if="transaction?.type">{{ t(`types.${transaction.type}`) }}</span>
            </p>
          </div>
          <button type="button" class="ls-btn ls-btn-sm" :aria-label="t('common.close')" @click="emit('close')">✕</button>
        </header>

        <div class="min-h-0 flex-1 space-y-6 overflow-y-auto px-6 py-4">
          <dl class="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
            <div>
              <dt class="text-fg-muted">{{ t('transactions.date') }}</dt>
              <dd>{{ formatDate(transaction?.transaction_date, locale) }}</dd>
            </div>
            <div>
              <dt class="text-fg-muted">{{ t('transactions.amount') }}</dt>
              <dd class="font-semibold">
                <MoneyText :amount-minor="transaction?.amount_minor" :currency="transaction?.currency_code ?? undefined" />
              </dd>
            </div>
            <div>
              <dt class="text-fg-muted">{{ t('transactions.category') }}</dt>
              <dd>{{ transaction?.category_name || t('common.dash') }}</dd>
            </div>
            <div>
              <dt class="text-fg-muted">{{ t('transactions.counterparty') }}</dt>
              <dd>{{ transaction?.counterparty_name || t('common.dash') }}</dd>
            </div>
            <div>
              <dt class="text-fg-muted">{{ t('transactions.reference') }}</dt>
              <dd>{{ transaction?.reference || t('common.dash') }}</dd>
            </div>
            <div>
              <dt class="text-fg-muted">{{ t('transactions.createdBy') }}</dt>
              <dd>{{ transaction?.created_by_name || transaction?.created_by_email || t('common.dash') }}</dd>
            </div>
            <div v-if="transaction?.adjustment_reason" class="col-span-2">
              <dt class="text-fg-muted">{{ t('detail.reason') }}</dt>
              <dd>{{ transaction.adjustment_reason }}</dd>
            </div>
          </dl>

          <section aria-labelledby="journal-heading">
            <h3 id="journal-heading" class="mb-2 text-sm font-bold">{{ t('detail.journal') }}</h3>
            <table class="ls-table">
              <thead>
                <tr>
                  <th scope="col">{{ t('detail.account') }}</th>
                  <th scope="col" class="text-end">{{ t('detail.debit') }}</th>
                  <th scope="col" class="text-end">{{ t('detail.credit') }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="(entry, index) in entries" :key="entry.entry_id ?? index">
                  <td>
                    <span class="block">{{ entry.account_name }}</span>
                    <span v-if="entry.memo" class="block text-xs text-fg-muted">{{ entry.memo }}</span>
                  </td>
                  <td class="ls-num">
                    <MoneyText v-if="entry.side === 'debit'" :amount-minor="entry.amount_minor" :currency="entry.currency_code" />
                    <span v-else class="text-fg-disabled">{{ t('common.dash') }}</span>
                  </td>
                  <td class="ls-num">
                    <MoneyText v-if="entry.side === 'credit'" :amount-minor="entry.amount_minor" :currency="entry.currency_code" />
                    <span v-else class="text-fg-disabled">{{ t('common.dash') }}</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </section>

          <p
            v-if="transaction?.reversed_by_transaction_id"
            class="rounded-control bg-[var(--bs-info-bg)] px-3 py-2 text-sm text-[var(--bs-info)]"
          >
            {{ t('detail.reversedNotice') }}
          </p>

          <div v-if="confirming" class="ls-card-flat space-y-3 p-4">
            <p class="text-sm">{{ t('detail.reverseExplain') }}</p>
            <div>
              <label class="ls-label" for="reverse-reason">{{ t('detail.reverseReason') }}</label>
              <input
                id="reverse-reason"
                v-model="reason"
                class="ls-input"
                :placeholder="t('detail.reverseReasonPlaceholder')"
              >
            </div>
            <div class="flex justify-end gap-2">
              <button type="button" class="ls-btn" @click="confirming = false">{{ t('common.cancel') }}</button>
              <button type="button" class="ls-btn ls-btn-danger" :disabled="reversing" @click="reverse">
                {{ reversing ? t('detail.reversing') : t('detail.reverseConfirm') }}
              </button>
            </div>
          </div>

          <p v-if="errorMessage" role="alert" class="ls-error">
            {{ errorMessage }}
          </p>
        </div>

        <footer v-if="canReverse && !confirming" class="border-t border-[var(--bs-border)] px-6 py-4">
          <button type="button" class="ls-btn" @click="confirming = true">{{ t('detail.reverseAction') }}</button>
        </footer>
      </div>
    </div>
  </Teleport>
</template>

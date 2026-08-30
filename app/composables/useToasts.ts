export interface Toast {
  id: number
  title: string
  description?: string
  tone: 'success' | 'error' | 'info'
}

let nextId = 0

/**
 * Minimal notification queue.
 *
 * Errors surfaced here are the *safe* message. Database functions raise
 * prefixed domain errors (UNBALANCED_JOURNAL, BOOKS_LOCKED, …) which are
 * translated in `describeError` — the raw SQLSTATE and any server detail stay
 * in the console for developers.
 */
export function useToasts() {
  const toasts = useState<Toast[]>('toasts', () => [])

  function push(toast: Omit<Toast, 'id'>) {
    const id = ++nextId
    toasts.value = [...toasts.value, { ...toast, id }]
    if (import.meta.client) {
      setTimeout(() => dismiss(id), toast.tone === 'error' ? 8000 : 4000)
    }
  }

  function dismiss(id: number) {
    toasts.value = toasts.value.filter(t => t.id !== id)
  }

  const success = (title: string, description?: string) =>
    push({ title, description, tone: 'success' })

  const error = (title: string, description?: string) =>
    push({ title, description, tone: 'error' })

  return { toasts, push, dismiss, success, error }
}

const DOMAIN_MESSAGES: Record<string, string> = {
  TENANT_ACCESS_DENIED: 'That record belongs to a different organization.',
  INSUFFICIENT_PERMISSION: 'Your role does not allow this action.',
  UNBALANCED_JOURNAL: 'The journal does not balance. Debits must equal credits.',
  INVALID_TRANSACTION_STATE: 'This transaction is no longer in a state that allows that.',
  BOOKS_LOCKED: 'The books are closed for that date.',
  ACCOUNT_ARCHIVED: 'That account is archived and cannot receive postings.',
  POSTED_RECORD_PROTECTED: 'Posted records cannot be edited. Reverse it and re-enter instead.',
  SYSTEM_ACCOUNT_PROTECTED: 'That is a system account and cannot be changed.',
  INVALID_CURRENCY: 'That currency is not supported.',
  INVALID_EXCHANGE_RATE: 'An exchange rate is required for this currency.',
  INVALID_AMOUNT: 'Enter an amount greater than zero.',
  INVALID_ACCOUNT: 'Choose a valid account for this kind of transaction.',
  INVALID_TRANSFER: 'Check the source and destination accounts.',
  INVALID_ADJUSTMENT: 'A description and a reason are required.',
  INVALID_OPENING_BALANCE: 'Enter at least one non-zero opening balance.',
  MISSING_SYSTEM_ACCOUNT: 'This organization is missing a required system account.',
  ACCOUNT_HAS_LEDGER_HISTORY: 'That account already has postings against it.',
  LAST_OWNER_REQUIRED: 'An organization must keep at least one owner.',
  INVALID_DATE_RANGE: 'The start date must be before the end date.',
}

/** Turns a Postgres/PostgREST error into something safe to show a user. */
export function describeError(err: unknown): string {
  const message
    = typeof err === 'object' && err !== null && 'message' in err
      ? String((err as { message: unknown }).message)
      : String(err)

  const code = message.match(/^([A-Z_]{4,}):/)?.[1]
  if (code && DOMAIN_MESSAGES[code]) return DOMAIN_MESSAGES[code]

  for (const [key, friendly] of Object.entries(DOMAIN_MESSAGES)) {
    if (message.includes(key)) return friendly
  }

  // Never leak a raw SQL error to the interface.
  if (import.meta.dev) console.error(err)
  return 'Something went wrong. Please try again.'
}

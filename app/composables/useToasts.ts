export interface Toast {
  id: number
  title: string
  description?: string
  tone: 'success' | 'error' | 'info'
}

let nextId = 0

/** Notification queue. Messages arrive already translated. */
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

/**
 * The database raises domain errors with a stable, prefixed code
 * (`UNBALANCED_JOURNAL: …`). Those codes are the contract; the wording shown to
 * a user is a translation of the code, never the raw server text — which may
 * contain table names, SQLSTATEs and internal detail.
 */
export function useErrorMessage() {
  const { t, te } = useI18n()

  return function describeError(err: unknown): string {
    const details = typeof err === 'object' && err !== null ? err as Record<string, unknown> : {}
    const sources = [details.message, details.details, details.hint, details.code, err]
      .filter(value => value !== null && value !== undefined)
      .map(String)
    const codes = sources.flatMap(source => [...source.matchAll(/\b[A-Z][A-Z0-9_]{3,}\b/g)].map(match => match[0]))
    const code = codes.find(candidate => te(`errors.${candidate}`))

    if (code) return t(`errors.${code}`)

    // Unrecognised: log the detail for developers, show the safe message.
    if (import.meta.dev) console.error(err)
    return t('errors.generic')
  }
}

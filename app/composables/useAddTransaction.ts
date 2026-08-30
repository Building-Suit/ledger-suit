/** The nine ways money enters the ledger, in the order the menu offers them.
 *  Labels and hints live in the locale files, keyed by these identifiers. */
export const ADD_FLOWS = [
  'income',
  'expense',
  'transfer',
  'asset_purchase',
  'liability_created',
  'liability_payment',
  'owner_contribution',
  'owner_withdrawal',
  'adjustment',
] as const

export type AddFlow = (typeof ADD_FLOWS)[number]

/** Capability required before a flow is offered at all. */
export const FLOW_CAPABILITY: Record<AddFlow, string> = {
  income: 'transactions.create',
  expense: 'transactions.create',
  transfer: 'transactions.create',
  asset_purchase: 'transactions.create',
  liability_created: 'transactions.create',
  liability_payment: 'transactions.create',
  owner_contribution: 'transactions.create',
  owner_withdrawal: 'transactions.create',
  adjustment: 'transactions.adjust',
}

export function useAddTransaction() {
  const open = useState<boolean>('add-transaction:open', () => false)
  const flow = useState<AddFlow>('add-transaction:flow', () => 'expense')

  function start(next: AddFlow) {
    flow.value = next
    open.value = true
  }

  function close() {
    open.value = false
  }

  return { open, flow, start, close }
}

export const ADD_FLOWS = [
  { key: 'income', label: 'Income', hint: 'Money received' },
  { key: 'expense', label: 'Expense', hint: 'Money paid out' },
  { key: 'transfer', label: 'Transfer', hint: 'Between your own accounts' },
  { key: 'asset_purchase', label: 'Asset', hint: 'Something you bought and keep' },
  { key: 'liability_created', label: 'Liability', hint: 'A loan or debt taken on' },
  { key: 'liability_payment', label: 'Liability payment', hint: 'Repay a loan or debt' },
  { key: 'owner_contribution', label: 'Owner contribution', hint: 'Money put into the business' },
  { key: 'owner_withdrawal', label: 'Owner withdrawal', hint: 'Money taken out' },
  { key: 'adjustment', label: 'Adjustment', hint: 'Manual journal entry' },
] as const

export type AddFlow = (typeof ADD_FLOWS)[number]['key']

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

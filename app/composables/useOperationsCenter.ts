export type OperationsTab = 'commitments' | 'recurring' | 'counterparties' | 'tags'

export function useOperationsCenter() {
  const open = useState('operations:open', () => false)
  const tab = useState<OperationsTab>('operations:tab', () => 'commitments')
  function show(next: OperationsTab = 'commitments') { tab.value = next; open.value = true }
  function close() { open.value = false }
  return { open, tab, show, close }
}

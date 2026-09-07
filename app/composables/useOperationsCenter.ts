export type OperationsTab = 'commitments' | 'recurring' | 'counterparties' | 'tags'

export function useOperationsCenter() {
  const open = useState('operations:open', () => false)
  const tab = useState<OperationsTab>('operations:tab', () => 'commitments')
  const revision = useState<Record<OperationsTab, number>>('operations:revision', () => ({ commitments: 0, recurring: 0, counterparties: 0, tags: 0 }))
  function show(next: OperationsTab = 'commitments') { tab.value = next; open.value = true }
  function close() { open.value = false }
  function markChanged(kind: OperationsTab) { revision.value = { ...revision.value, [kind]: revision.value[kind] + 1 } }
  return { open, tab, revision, show, close, markChanged }
}

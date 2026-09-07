export function useTeamInvitation() {
  const open = useState('team-invitation:open', () => false)
  const revision = useState('team-invitation:revision', () => 0)

  function show() { open.value = true }
  function close() { open.value = false }
  function markChanged() { revision.value += 1 }

  return { open, revision, show, close, markChanged }
}

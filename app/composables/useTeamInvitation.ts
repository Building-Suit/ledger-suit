export function useTeamInvitation() {
  const open = useState('team-invitation:open', () => false)

  function show() { open.value = true }
  function close() { open.value = false }

  return { open, show, close }
}

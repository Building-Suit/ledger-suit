<script setup lang="ts">
import type { Database } from '~~/types/database.types'

definePageMeta({ layout: 'default' })

type Role = Database['public']['Enums']['organization_role']
type MemberStatus = Database['public']['Enums']['membership_status']
type Tab = 'members' | 'roles' | 'invitations'

interface ProfileSummary {
  email: string
  full_name: string | null
  job_title: string | null
}

interface MemberRow {
  id: string
  user_id: string
  role: Role
  status: MemberStatus
  granted_capabilities: string[]
  revoked_capabilities: string[]
  joined_at: string
  profile: ProfileSummary | null
}

interface InvitationRow {
  id: string
  email: string
  role: Role
  status: Database['public']['Enums']['invitation_status']
  created_at: string
  expires_at: string
  inviter: Pick<ProfileSummary, 'full_name' | 'job_title'> | null
}

interface CapabilityRow {
  key: string
  domain: string
  description: string
}

const supabase = useSupabaseClient<Database>()
const user = useSupabaseUser()
const { current, currentId, can, loadOrganizations } = useTenant()
const { show: showInvitation, revision: invitationRevision } = useTeamInvitation()
const { t, locale } = useI18n()
const toasts = useToasts()
const describeError = useErrorMessage()

useHead({ title: () => `${t('access.title')} · ${t('app.name')}` })

const roles: Role[] = ['owner', 'admin', 'accountant', 'data_entry', 'viewer']
const assignableRoles = computed<Role[]>(() => current.value?.role === 'owner' ? roles : roles.filter(role => role !== 'owner'))
const activeTab = ref<Tab>('members')
const search = ref('')
const members = ref<MemberRow[]>([])
const invitations = ref<InvitationRow[]>([])
const capabilities = ref<CapabilityRow[]>([])
const roleCapabilities = ref<Array<{ role: Role, capability_key: string }>>([])
const loading = ref(true)
const errorMessage = ref('')

const tabs = computed(() => [
  { key: 'members' as const, label: t('access.members'), count: members.value.length },
  { key: 'roles' as const, label: t('access.rolesPermissions') },
  { key: 'invitations' as const, label: t('access.invitations'), count: invitations.value.filter(invitation => invitation.status === 'pending').length },
])

const visibleMembers = computed(() => {
  const query = search.value.trim().toLocaleLowerCase()
  if (!query) return members.value
  return members.value.filter((member) => {
    const profile = member.profile
    return [profile?.full_name, profile?.email, profile?.job_title, member.role]
      .some(value => String(value ?? '').toLocaleLowerCase().includes(query))
  })
})

const groupedCapabilities = computed(() => {
  const groups = new Map<string, CapabilityRow[]>()
  for (const capability of capabilities.value) {
    const group = groups.get(capability.domain) ?? []
    group.push(capability)
    groups.set(capability.domain, group)
  }
  return [...groups.entries()].sort(([a], [b]) => a.localeCompare(b))
})

function defaultsFor(role: Role) {
  return new Set(roleCapabilities.value.filter(item => item.role === role).map(item => item.capability_key))
}

function rolePermissionCount(role: Role) {
  return defaultsFor(role).size
}

function hasRolePermission(role: Role, capability: string) {
  return defaultsFor(role).has(capability)
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium' }).format(new Date(value))
}

async function loadAccess() {
  if (!currentId.value || !can('members.read')) return
  loading.value = true
  errorMessage.value = ''
  try {
    const [memberResult, invitationResult, capabilityResult, roleResult] = await Promise.all([
      supabase
        .from('organization_members')
        .select('id, user_id, role, status, granted_capabilities, revoked_capabilities, joined_at, profile:profiles!organization_members_user_id_fkey(email, full_name, job_title)')
        .eq('organization_id', currentId.value)
        .order('created_at'),
      supabase
        .from('organization_invitations')
        .select('id, email, role, status, created_at, expires_at, inviter:profiles!organization_invitations_invited_by_fkey(full_name, job_title)')
        .eq('organization_id', currentId.value)
        .order('created_at', { ascending: false }),
      supabase.from('capabilities').select('key, domain, description').order('domain').order('key'),
      supabase.from('role_capabilities').select('role, capability_key'),
    ])
    if (memberResult.error) throw memberResult.error
    if (invitationResult.error) throw invitationResult.error
    if (capabilityResult.error) throw capabilityResult.error
    if (roleResult.error) throw roleResult.error
    members.value = (memberResult.data ?? []) as unknown as MemberRow[]
    invitations.value = (invitationResult.data ?? []) as unknown as InvitationRow[]
    capabilities.value = capabilityResult.data ?? []
    roleCapabilities.value = roleResult.data ?? []
  }
  catch (error) { errorMessage.value = describeError(error) }
  finally { loading.value = false }
}

watch(currentId, () => void loadAccess(), { immediate: true })
watch(invitationRevision, () => void loadAccess())

const editingMember = ref<MemberRow | null>(null)
const editRole = ref<Role>('viewer')
const editStatus = ref<MemberStatus>('active')
const selectedPermissions = ref<Set<string>>(new Set())
const saving = ref(false)

function effectivePermissions(member: MemberRow) {
  const permissions = defaultsFor(member.role)
  member.granted_capabilities.forEach(key => permissions.add(key))
  member.revoked_capabilities.forEach(key => permissions.delete(key))
  return permissions
}

function openEditor(member: MemberRow) {
  editingMember.value = member
  editRole.value = member.role
  editStatus.value = member.status
  selectedPermissions.value = effectivePermissions(member)
  errorMessage.value = ''
}

function togglePermission(key: string, checked: boolean) {
  const next = new Set(selectedPermissions.value)
  if (checked) next.add(key)
  else next.delete(key)
  selectedPermissions.value = next
}

function resetToRoleDefaults() {
  selectedPermissions.value = defaultsFor(editRole.value)
}

async function saveMember() {
  if (!editingMember.value) return
  saving.value = true
  errorMessage.value = ''
  const defaults = defaultsFor(editRole.value)
  const granted = capabilities.value.map(item => item.key).filter(key => selectedPermissions.value.has(key) && !defaults.has(key))
  const revoked = capabilities.value.map(item => item.key).filter(key => !selectedPermissions.value.has(key) && defaults.has(key))
  try {
    const { error } = await supabase.rpc('manage_organization_member', {
      p_member_id: editingMember.value.id,
      p_role: editRole.value,
      p_status: editStatus.value,
      p_granted_capabilities: granted,
      p_revoked_capabilities: revoked,
    })
    if (error) throw error
    editingMember.value = null
    await loadAccess()
    await loadOrganizations(user.value?.id, { force: true })
    toasts.success(t('access.saved'))
  }
  catch (error) { errorMessage.value = describeError(error) }
  finally { saving.value = false }
}

async function quickStatus(member: MemberRow) {
  const nextStatus: MemberStatus = member.status === 'active' ? 'suspended' : 'active'
  editingMember.value = member
  editRole.value = member.role
  editStatus.value = nextStatus
  selectedPermissions.value = effectivePermissions(member)
  await saveMember()
}

async function removeMember(member: MemberRow) {
  if (!confirm(t('access.removeConfirm'))) return
  saving.value = true
  errorMessage.value = ''
  try {
    const { error } = await supabase.rpc('remove_organization_member', { p_member_id: member.id })
    if (error) throw error
    await loadAccess()
    toasts.success(t('access.removed'))
  }
  catch (error) { errorMessage.value = describeError(error) }
  finally { saving.value = false }
}

async function revokeInvitation(invitation: InvitationRow) {
  saving.value = true
  errorMessage.value = ''
  try {
    const { error } = await supabase.rpc('revoke_organization_invitation', { p_invitation_id: invitation.id })
    if (error) throw error
    await loadAccess()
    toasts.success(t('access.revoked'))
  }
  catch (error) { errorMessage.value = describeError(error) }
  finally { saving.value = false }
}

async function resendInvitation(invitation: InvitationRow) {
  saving.value = true
  errorMessage.value = ''
  try {
    const { data, error } = await supabase.functions.invoke('send-invitation', { body: { invitationId: invitation.id } })
    if (error) throw new Error(await edgeFunctionErrorMessage(error, t('errors.generic')))
    if (!data?.sent) throw new Error(data?.warning ?? t('errors.generic'))
    await loadAccess()
    toasts.success(t('access.resent'))
  }
  catch (error) { errorMessage.value = describeError(error) }
  finally { saving.value = false }
}
</script>

<template>
  <div class="space-y-6">
    <header class="flex flex-wrap items-end justify-between gap-4">
      <div class="max-w-3xl">
        <p class="text-xs font-bold uppercase tracking-[.18em] text-fg-muted">{{ t('access.eyebrow') }}</p>
        <h1 class="mt-2 text-h1 font-bold">{{ t('access.title') }}</h1>
        <p class="mt-2 text-sm leading-6 text-fg-muted">{{ t('access.subtitle') }}</p>
      </div>
      <button v-if="can('members.invite')" type="button" class="ls-btn ls-btn-primary" @click="showInvitation">
        <AppIcon name="add" :size="18" /> {{ t('org.invite') }}
      </button>
    </header>

    <div class="ls-card flex flex-wrap gap-1 p-1.5" role="tablist" :aria-label="t('access.title')">
      <button
        v-for="tab in tabs"
        :key="tab.key"
        type="button"
        role="tab"
        :aria-selected="activeTab === tab.key"
        class="min-h-11 rounded-control px-4 text-sm font-bold transition-colors"
        :class="activeTab === tab.key ? 'bg-fg text-background shadow-card' : 'text-fg-muted hover:bg-surface-muted hover:text-fg'"
        @click="activeTab = tab.key"
      >
        {{ tab.label }} <span v-if="tab.count !== undefined" class="ms-1 opacity-70">{{ tab.count }}</span>
      </button>
    </div>

    <SectionSkeleton v-if="loading" variant="table" :rows="6" />
    <p v-else-if="errorMessage && !editingMember" class="ls-error" role="alert">{{ errorMessage }}</p>

    <template v-else-if="activeTab === 'members'">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <p class="text-sm font-semibold text-fg-muted">{{ t('access.memberCount', members.length) }}</p>
        <label class="relative w-full sm:w-72">
          <span class="sr-only">{{ t('access.searchMembers') }}</span>
          <input v-model="search" type="search" class="ls-input" :placeholder="t('access.searchMembers')">
        </label>
      </div>
      <div v-if="visibleMembers.length" class="ls-card overflow-x-auto">
        <table class="ls-table">
          <thead><tr><th>{{ t('access.name') }}</th><th>{{ t('access.role') }}</th><th>{{ t('access.status') }}</th><th>{{ t('access.joined') }}</th><th class="text-end">{{ t('access.actions') }}</th></tr></thead>
          <tbody>
            <tr v-for="member in visibleMembers" :key="member.id">
              <td><div class="flex items-center gap-3"><span class="grid size-9 shrink-0 place-items-center rounded-full bg-surface-muted font-black">{{ (member.profile?.full_name || member.profile?.email || '?').slice(0, 1).toUpperCase() }}</span><div><p class="font-bold">{{ member.profile?.full_name || member.profile?.email }}</p><p class="text-xs text-fg-muted" dir="ltr">{{ member.profile?.email }}</p><p v-if="member.profile?.job_title" class="text-xs text-fg-muted">{{ member.profile.job_title }}</p></div></div></td>
              <td><span class="ls-badge bg-surface-muted">{{ t(`org.roles.${member.role}`) }}</span><span v-if="member.granted_capabilities.length || member.revoked_capabilities.length" class="ms-1 text-xs text-fg-muted">{{ t('access.customized') }}</span></td>
              <td><StatusBadge :status="member.status" /></td>
              <td class="whitespace-nowrap">{{ formatDate(member.joined_at) }}</td>
              <td class="whitespace-nowrap text-end"><button v-if="can('members.update')" type="button" class="ls-btn ls-btn-sm" @click="openEditor(member)">{{ t('access.editAccess') }}</button><button v-if="can('members.update') && member.role !== 'owner' && member.user_id !== user?.id" type="button" class="ls-btn ls-btn-sm ms-1" @click="quickStatus(member)">{{ t(member.status === 'active' ? 'access.suspend' : 'access.reactivate') }}</button><button v-if="can('members.remove') && member.role !== 'owner' && member.user_id !== user?.id" type="button" class="ls-btn ls-btn-sm ms-1 text-danger" @click="removeMember(member)">{{ t('access.remove') }}</button></td>
            </tr>
          </tbody>
        </table>
      </div>
      <EmptyState v-else :title="t('access.noMembers')" />
    </template>

    <template v-else-if="activeTab === 'roles'">
      <section>
        <h2 class="text-lg font-bold">{{ t('access.roleSummary') }}</h2>
        <p class="mt-1 text-sm text-fg-muted">{{ t('access.roleSummaryHint') }}</p>
        <div class="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-5">
          <article v-for="role in roles" :key="role" class="ls-card p-5">
            <span class="grid size-10 place-items-center rounded-control bg-brand-navy text-brand-gold"><AppIcon :name="role === 'viewer' ? 'user' : 'team'" /></span>
            <h3 class="mt-4 font-bold">{{ t(`org.roles.${role}`) }}</h3>
            <p class="mt-2 min-h-16 text-sm leading-5 text-fg-muted">{{ t(`access.roles.${role}`) }}</p>
            <p class="mt-4 text-xs font-bold text-fg-muted">{{ rolePermissionCount(role) }} / {{ capabilities.length }} {{ t('access.permissionsMatrix').toLocaleLowerCase() }}</p>
          </article>
        </div>
      </section>

      <section class="ls-card overflow-x-auto">
        <div class="border-b border-[var(--bs-border)] p-5"><h2 class="text-lg font-bold">{{ t('access.permissionsMatrix') }}</h2></div>
        <table class="ls-table">
          <thead><tr><th>{{ t('access.permission') }}</th><th v-for="role in roles" :key="role" class="text-center">{{ t(`org.roles.${role}`) }}</th></tr></thead>
          <tbody v-for="[domain, items] in groupedCapabilities" :key="domain">
            <tr class="bg-surface-muted"><td :colspan="roles.length + 1" class="font-bold capitalize">{{ domain.replaceAll('_', ' ') }}</td></tr>
            <tr v-for="capability in items" :key="capability.key"><td><p class="font-semibold">{{ capability.description }}</p><code class="text-xs text-fg-muted" dir="ltr">{{ capability.key }}</code></td><td v-for="role in roles" :key="`${capability.key}-${role}`" class="text-center"><AppIcon v-if="hasRolePermission(role, capability.key)" name="check" :size="18" class="mx-auto text-success" /><span v-else class="text-fg-muted">—</span></td></tr>
          </tbody>
        </table>
      </section>
    </template>

    <template v-else>
      <div class="flex items-center justify-between gap-3"><p class="text-sm font-semibold text-fg-muted">{{ t('access.invitationCount', invitations.length) }}</p><button v-if="can('members.invite')" type="button" class="ls-btn ls-btn-primary ls-btn-sm" @click="showInvitation">{{ t('org.invite') }}</button></div>
      <div v-if="invitations.length" class="ls-card overflow-x-auto">
        <table class="ls-table">
          <thead><tr><th>{{ t('auth.email') }}</th><th>{{ t('access.role') }}</th><th>{{ t('access.status') }}</th><th>{{ t('access.invitedBy') }}</th><th>{{ t('access.sent') }}</th><th>{{ t('access.expires') }}</th><th class="text-end">{{ t('access.actions') }}</th></tr></thead>
          <tbody><tr v-for="invitation in invitations" :key="invitation.id"><td dir="ltr">{{ invitation.email }}</td><td>{{ t(`org.roles.${invitation.role}`) }}</td><td><StatusBadge :status="invitation.status" /></td><td><p>{{ invitation.inviter?.full_name || '—' }}</p><p v-if="invitation.inviter?.job_title" class="text-xs text-fg-muted">{{ invitation.inviter.job_title }}</p></td><td class="whitespace-nowrap">{{ formatDate(invitation.created_at) }}</td><td class="whitespace-nowrap">{{ formatDate(invitation.expires_at) }}</td><td class="whitespace-nowrap text-end"><template v-if="invitation.status === 'pending'"><button v-if="can('members.invite')" type="button" class="ls-btn ls-btn-sm" :disabled="saving" @click="resendInvitation(invitation)">{{ t('access.resend') }}</button><button v-if="can('members.update')" type="button" class="ls-btn ls-btn-sm ms-1 text-danger" :disabled="saving" @click="revokeInvitation(invitation)">{{ t('access.revoke') }}</button></template></td></tr></tbody>
        </table>
      </div>
      <EmptyState v-else :title="t('access.noInvitations')" :action-label="can('members.invite') ? t('org.invite') : undefined" @action="showInvitation" />
    </template>

    <TeamMenu :show-trigger="false" />

    <Teleport to="body">
      <Transition name="ls-modal">
        <div v-if="editingMember" class="fixed inset-0 z-[70] grid place-items-center ls-scrim p-4" role="dialog" aria-modal="true" @click.self="editingMember = null">
          <form class="ls-modal-panel ls-card max-h-[90dvh] w-full max-w-3xl overflow-y-auto p-6 shadow-overlay" @submit.prevent="saveMember">
            <div class="flex items-start justify-between gap-4"><div><h2 class="text-lg font-bold">{{ t('access.editAccessFor', { name: editingMember.profile?.full_name || editingMember.profile?.email }) }}</h2><p class="mt-1 text-sm text-fg-muted" dir="ltr">{{ editingMember.profile?.email }}</p></div><button type="button" class="ls-btn ls-btn-sm" :aria-label="t('common.close')" @click="editingMember = null"><AppIcon name="close" /></button></div>
            <div class="mt-6 grid gap-4 sm:grid-cols-2"><FloatingField :label="t('access.role')"><select v-model="editRole" class="ls-input"><option v-for="role in assignableRoles" :key="role" :value="role">{{ t(`org.roles.${role}`) }}</option></select></FloatingField><FloatingField :label="t('access.status')"><select v-model="editStatus" class="ls-input" :disabled="editingMember.user_id === user?.id"><option value="active">{{ t('access.active') }}</option><option value="suspended">{{ t('access.suspended') }}</option></select></FloatingField></div>
            <div class="mt-7 flex flex-wrap items-start justify-between gap-3"><div><h3 class="font-bold">{{ t('access.permissionOverrides') }}</h3><p class="mt-1 max-w-xl text-sm text-fg-muted">{{ t('access.permissionOverridesHint') }}</p></div><button type="button" class="ls-btn ls-btn-sm" @click="resetToRoleDefaults">{{ t('access.roleSummary') }}</button></div>
            <div class="mt-4 grid gap-4 sm:grid-cols-2"><fieldset v-for="[domain, items] in groupedCapabilities" :key="domain" class="rounded-card border border-[var(--bs-border)] p-4"><legend class="px-1 text-sm font-bold capitalize">{{ domain.replaceAll('_', ' ') }}</legend><label v-for="capability in items" :key="capability.key" class="mt-3 flex cursor-pointer items-start gap-3 text-sm"><input type="checkbox" class="mt-1 size-4 accent-[var(--bs-accent)]" :checked="selectedPermissions.has(capability.key)" @change="togglePermission(capability.key, ($event.target as HTMLInputElement).checked)"><span><span class="block font-semibold">{{ capability.description }}</span><code class="text-xs text-fg-muted" dir="ltr">{{ capability.key }}</code></span></label></fieldset></div>
            <p v-if="errorMessage" class="ls-error mt-6" role="alert">{{ errorMessage }}</p>
            <div class="mt-6 flex justify-end gap-2"><button type="button" class="ls-btn" @click="editingMember = null">{{ t('common.cancel') }}</button><button class="ls-btn ls-btn-primary" :disabled="saving">{{ saving ? t('common.saving') : t('access.saveAccess') }}</button></div>
          </form>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

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
  role_id: string | null
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
  role_id: string | null
  status: Database['public']['Enums']['invitation_status']
  created_at: string
  expires_at: string
  inviter: Pick<ProfileSummary, 'full_name' | 'job_title'> | null
}

interface CapabilityRow {
  key: string
  domain: string
  description: string
  description_ar: string
}

interface CustomRoleRow {
  id: string
  key: string
  name_en: string
  name_ar: string
}

const supabase = useSupabaseClient<Database>()
const user = useSupabaseUser()
const { current, currentId, can, loadOrganizations, roleLabel } = useTenant()
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
const roleCapabilities = ref<Array<{ role: Role | null, role_id: string | null, capability_key: string }>>([])
const customRoles = ref<CustomRoleRow[]>([])
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

const PERMISSION_MENU_GROUPS = [
  { key: 'transactions', domains: ['transactions', 'attachments', 'categories', 'imports', 'exports', 'books'] },
  { key: 'ledger', domains: ['accounts'] },
  { key: 'operations', domains: ['commitments', 'recurring'] },
  { key: 'directory', domains: ['counterparties', 'tags'] },
  { key: 'workspace', domains: ['organization', 'members', 'billing', 'audit'] },
  { key: 'insights', domains: ['reports'] },
] as const

const permissionMenuGroups = computed(() => PERMISSION_MENU_GROUPS.map(group => ({
  key: group.key,
  domains: group.domains.map(domain => ({
    key: domain,
    items: capabilities.value.filter(capability => capability.domain === domain),
  })).filter(domain => domain.items.length),
})).filter(group => group.domains.length))

function capabilityTitle(capability: CapabilityRow) {
  return locale.value === 'ar' ? capability.description_ar : capability.description
}

function systemDefaultsFor(role: Role) {
  return new Set(roleCapabilities.value.filter(item => item.role === role).map(item => item.capability_key))
}

function customCapabilitiesFor(roleId: string) {
  return new Set(roleCapabilities.value.filter(item => item.role_id === roleId).map(item => item.capability_key))
}

function rolePermissionCount(role: Role) {
  return systemDefaultsFor(role).size
}

function customPermissionCount(roleId: string) {
  return customCapabilitiesFor(roleId).size
}

function hasRolePermission(role: Role, capability: string) {
  return systemDefaultsFor(role).has(capability)
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium' }).format(new Date(value))
}

async function loadAccess() {
  if (!currentId.value || !can('members.read')) {
    loading.value = false
    return
  }
  loading.value = true
  errorMessage.value = ''
  try {
    const [memberResult, invitationResult, capabilityResult, roleResult, customRoleResult] = await Promise.all([
      supabase
        .from('organization_members')
        .select('id, user_id, role, role_id, status, granted_capabilities, revoked_capabilities, joined_at, profile:profiles!organization_members_user_id_fkey(email, full_name, job_title)')
        .eq('organization_id', currentId.value)
        .order('created_at'),
      supabase
        .from('organization_invitations')
        .select('id, email, role, role_id, status, created_at, expires_at, inviter:profiles!organization_invitations_invited_by_fkey(full_name, job_title)')
        .eq('organization_id', currentId.value)
        .order('created_at', { ascending: false }),
      supabase.from('capabilities').select('key, domain, description, description_ar').order('domain').order('key'),
      supabase.from('role_capabilities').select('role, role_id, capability_key'),
      supabase.from('organization_roles').select('id, key, name_en, name_ar').eq('organization_id', currentId.value).order('created_at'),
    ])
    if (memberResult.error) throw memberResult.error
    if (invitationResult.error) throw invitationResult.error
    if (capabilityResult.error) throw capabilityResult.error
    if (roleResult.error) throw roleResult.error
    if (customRoleResult.error) throw customRoleResult.error
    members.value = (memberResult.data ?? []) as unknown as MemberRow[]
    invitations.value = (invitationResult.data ?? []) as unknown as InvitationRow[]
    capabilities.value = capabilityResult.data ?? []
    roleCapabilities.value = roleResult.data ?? []
    customRoles.value = customRoleResult.data ?? []
  }
  catch (error) { errorMessage.value = describeError(error) }
  finally { loading.value = false }
}

watch(currentId, () => void loadAccess(), { immediate: true })
watch(invitationRevision, () => void loadAccess())

// ---------------------------------------------------------------------------
// Member access editor: a role menu only. The role menu lists system roles
// plus every custom role defined in this workspace.
// ---------------------------------------------------------------------------
const editingMember = ref<MemberRow | null>(null)
const editRoleChoice = ref<string>('system:viewer')
const editStatus = ref<MemberStatus>('active')
const saving = ref(false)

const editedSystemRole = computed<Role | null>(() => editRoleChoice.value.startsWith('system:') ? editRoleChoice.value.slice(7) as Role : null)
const editedCustomRoleId = computed<string | null>(() => editRoleChoice.value.startsWith('custom:') ? editRoleChoice.value.slice(7) : null)

function openEditor(member: MemberRow) {
  editingMember.value = member
  editRoleChoice.value = member.role_id ? `custom:${member.role_id}` : `system:${member.role}`
  editStatus.value = member.status
  errorMessage.value = ''
}

async function saveMember() {
  if (!editingMember.value) return
  saving.value = true
  errorMessage.value = ''
  // Changing the role resets any per-member capability overrides to the new
  // role's defaults; keeping the same role preserves existing overrides.
  const roleChanged = editingMember.value.role_id !== editedCustomRoleId.value
    || (editedCustomRoleId.value === null && editingMember.value.role !== editedSystemRole.value)
  const granted = roleChanged ? [] : editingMember.value.granted_capabilities
  const revoked = roleChanged ? [] : editingMember.value.revoked_capabilities
  try {
    const { error } = await supabase.rpc('manage_organization_member', {
      p_member_id: editingMember.value.id,
      p_role: editedSystemRole.value ?? 'viewer',
      p_role_id: editedCustomRoleId.value ?? undefined,
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
  editRoleChoice.value = member.role_id ? `custom:${member.role_id}` : `system:${member.role}`
  editStatus.value = nextStatus
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

// ---------------------------------------------------------------------------
// Permission matrix: a read-only reference for system and custom roles.
// ---------------------------------------------------------------------------
const matrixOpen = ref(false)

function openMatrix() {
  errorMessage.value = ''
  matrixOpen.value = true
}

// ---------------------------------------------------------------------------
// Custom role create/edit: bilingual names plus the permission list.
// ---------------------------------------------------------------------------
const roleModalOpen = ref(false)
const roleForm = ref<{ id: string | null, name_en: string, name_ar: string, caps: Set<string> }>({ id: null, name_en: '', name_ar: '', caps: new Set() })
const roleSaving = ref(false)

function openCreateRole() {
  roleForm.value = { id: null, name_en: '', name_ar: '', caps: new Set(['organization.read']) }
  errorMessage.value = ''
  roleModalOpen.value = true
}

function openEditRole(role: CustomRoleRow) {
  roleForm.value = { id: role.id, name_en: role.name_en, name_ar: role.name_ar, caps: customCapabilitiesFor(role.id) }
  errorMessage.value = ''
  roleModalOpen.value = true
}

function toggleRoleCap(key: string, checked: boolean) {
  const next = new Set(roleForm.value.caps)
  if (checked) next.add(key)
  else next.delete(key)
  roleForm.value = { ...roleForm.value, caps: next }
}

function slugKey(name: string) {
  const slug = name.toLowerCase().replaceAll(/[^a-z0-9]+/g, '_').replaceAll(/^_+|_+$/g, '').slice(0, 40)
  return slug.length >= 2 ? slug : 'role'
}

async function saveRole() {
  roleSaving.value = true
  errorMessage.value = ''
  try {
    if (roleForm.value.id) {
      const { error } = await supabase.rpc('update_organization_role', {
        p_role_id: roleForm.value.id,
        p_name_en: roleForm.value.name_en,
        p_name_ar: roleForm.value.name_ar,
        p_capabilities: [...roleForm.value.caps],
      })
      if (error) throw error
    }
    else {
      const { error } = await supabase.rpc('create_organization_role', {
        p_organization_id: currentId.value!,
        p_key: slugKey(roleForm.value.name_en),
        p_name_en: roleForm.value.name_en,
        p_name_ar: roleForm.value.name_ar,
        p_capabilities: [...roleForm.value.caps],
      })
      if (error) throw error
    }
    roleModalOpen.value = false
    await loadAccess()
    await loadOrganizations(user.value?.id, { force: true })
    toasts.success(t('access.saved'))
  }
  catch (error) { errorMessage.value = describeError(error) }
  finally { roleSaving.value = false }
}

async function deleteRole(role: CustomRoleRow) {
  if (!confirm(t('access.deleteRoleConfirm'))) return
  errorMessage.value = ''
  try {
    const { error } = await supabase.rpc('delete_organization_role', { p_role_id: role.id })
    if (error) throw error
    await loadAccess()
    toasts.success(t('access.removed'))
  }
  catch (error) { errorMessage.value = describeError(error) }
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
      <div class="flex flex-wrap gap-2">
        <button v-if="can('members.read')" type="button" class="ls-btn" @click="openMatrix">{{ t('access.permissionsMatrix') }}</button>
        <button v-if="can('members.update')" type="button" class="ls-btn ls-btn-primary" @click="openCreateRole"><AppIcon name="add" :size="18" /> {{ t('access.newRole') }}</button>
        <button v-if="can('members.invite')" type="button" class="ls-btn ls-btn-primary" @click="showInvitation">
          <AppIcon name="add" :size="18" /> {{ t('org.invite') }}
        </button>
      </div>
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
    <p v-else-if="errorMessage && !editingMember && !matrixOpen && !roleModalOpen" class="ls-error" role="alert">{{ errorMessage }}</p>

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
              <td><span class="ls-badge bg-surface-muted">{{ roleLabel(member.role, member.role_id) }}</span><span v-if="member.granted_capabilities.length || member.revoked_capabilities.length" class="ms-1 text-xs text-fg-muted">{{ t('access.customized') }}</span></td>
              <td><StatusBadge :status="member.status" /></td>
              <td class="whitespace-nowrap">{{ formatDate(member.joined_at) }}</td>
              <td class="whitespace-nowrap text-end"><button v-if="can('members.update') && member.role !== 'owner'" type="button" class="ls-btn ls-btn-sm" @click="openEditor(member)">{{ t('access.editAccess') }}</button><button v-if="can('members.update') && member.role !== 'owner' && member.user_id !== user?.id" type="button" class="ls-btn ls-btn-sm ms-1" @click="quickStatus(member)">{{ t(member.status === 'active' ? 'access.suspend' : 'access.reactivate') }}</button><button v-if="can('members.remove') && member.role !== 'owner' && member.user_id !== user?.id" type="button" class="ls-btn ls-btn-sm ms-1 text-danger" @click="removeMember(member)">{{ t('access.remove') }}</button></td>
            </tr>
          </tbody>
        </table>
      </div>
      <EmptyState v-else :title="t('access.noMembers')" />
    </template>

    <template v-else-if="activeTab === 'roles'">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 class="text-lg font-bold">{{ t('access.roleSummary') }}</h2>
          <p class="mt-1 text-sm text-fg-muted">{{ t('access.roleSummaryHint') }}</p>
        </div>
      </div>

      <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-5">
        <article v-for="role in roles" :key="role" class="ls-card p-5">
          <span class="grid size-10 place-items-center rounded-control bg-brand-navy text-brand-gold"><AppIcon :name="role === 'viewer' ? 'user' : 'team'" /></span>
          <h3 class="mt-4 font-bold">{{ t(`org.roles.${role}`) }}</h3>
          <p class="mt-2 min-h-16 text-sm leading-5 text-fg-muted">{{ t(`access.roles.${role}`) }}</p>
          <p class="mt-4 text-xs font-bold text-fg-muted">{{ rolePermissionCount(role) }} / {{ capabilities.length }} {{ t('access.permissionsMatrix').toLocaleLowerCase() }}</p>
        </article>
      </div>

      <section>
        <h2 class="text-lg font-bold">{{ t('access.customRoles') }}</h2>
        <p class="mt-1 text-sm text-fg-muted">{{ t('access.customRolesHint') }}</p>
        <div v-if="customRoles.length" class="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
          <article v-for="role in customRoles" :key="role.id" class="ls-card p-5">
            <div class="flex items-start justify-between gap-2">
              <span class="grid size-10 place-items-center rounded-control bg-brand-navy text-brand-gold"><AppIcon name="team" /></span>
              <div v-if="can('members.update')" class="flex gap-1">
                <button type="button" class="ls-btn ls-btn-sm" @click="openEditRole(role)">{{ t('access.editAccess') }}</button>
                <button type="button" class="ls-btn ls-btn-sm text-danger" @click="deleteRole(role)">{{ t('access.remove') }}</button>
              </div>
            </div>
            <h3 class="mt-4 font-bold">{{ roleLabel(null, role.id) }}</h3>
            <p class="text-xs text-fg-muted" dir="ltr">{{ role.name_en }} · {{ role.name_ar }}</p>
            <p class="mt-4 text-xs font-bold text-fg-muted">{{ customPermissionCount(role.id) }} / {{ capabilities.length }} {{ t('access.permissionsMatrix').toLocaleLowerCase() }}</p>
          </article>
        </div>
        <EmptyState v-else class="mt-4" :title="t('access.noCustomRoles')" />
      </section>
    </template>

    <template v-else>
      <p class="text-sm font-semibold text-fg-muted">{{ t('access.invitationCount', invitations.length) }}</p>
      <div v-if="invitations.length" class="ls-card overflow-x-auto">
        <table class="ls-table">
          <thead><tr><th>{{ t('auth.email') }}</th><th>{{ t('access.role') }}</th><th>{{ t('access.status') }}</th><th>{{ t('access.invitedBy') }}</th><th>{{ t('access.sent') }}</th><th>{{ t('access.expires') }}</th><th class="text-end">{{ t('access.actions') }}</th></tr></thead>
          <tbody><tr v-for="invitation in invitations" :key="invitation.id"><td dir="ltr">{{ invitation.email }}</td><td>{{ roleLabel(invitation.role, invitation.role_id) }}</td><td><StatusBadge :status="invitation.status" /></td><td><p>{{ invitation.inviter?.full_name || '—' }}</p><p v-if="invitation.inviter?.job_title" class="text-xs text-fg-muted">{{ invitation.inviter.job_title }}</p></td><td class="whitespace-nowrap">{{ formatDate(invitation.created_at) }}</td><td class="whitespace-nowrap">{{ formatDate(invitation.expires_at) }}</td><td class="whitespace-nowrap text-end"><template v-if="invitation.status === 'pending'"><button v-if="can('members.invite')" type="button" class="ls-btn ls-btn-sm" :disabled="saving" @click="resendInvitation(invitation)">{{ t('access.resend') }}</button><button v-if="can('members.update')" type="button" class="ls-btn ls-btn-sm ms-1 text-danger" :disabled="saving" @click="revokeInvitation(invitation)">{{ t('access.revoke') }}</button></template></td></tr></tbody>
        </table>
      </div>
      <EmptyState v-else :title="t('access.noInvitations')" />
    </template>

    <TeamMenu :show-trigger="false" />

    <Teleport to="body">
      <!-- Edit access: role menu only -->
      <Transition name="ls-modal">
        <div v-if="editingMember" class="fixed inset-0 z-[70] grid place-items-center ls-scrim p-4" role="dialog" aria-modal="true" @click.self="editingMember = null">
          <form class="ls-modal-panel ls-card max-h-[90dvh] w-full max-w-md overflow-y-auto p-6 shadow-overlay" @submit.prevent="saveMember">
            <div class="flex items-start justify-between gap-4"><div><h2 class="text-lg font-bold">{{ t('access.editAccessFor', { name: editingMember.profile?.full_name || editingMember.profile?.email }) }}</h2><p class="mt-1 text-sm text-fg-muted" dir="ltr">{{ editingMember.profile?.email }}</p></div><button type="button" class="ls-btn ls-btn-sm" :aria-label="t('common.close')" @click="editingMember = null"><AppIcon name="close" /></button></div>
            <fieldset class="mt-6">
              <legend class="text-sm font-bold">{{ t('access.role') }}</legend>
              <div class="mt-3 grid gap-2">
                <label v-for="role in assignableRoles" :key="role" class="flex cursor-pointer items-center justify-between gap-3 rounded-card border p-3 text-sm transition-colors" :class="editRoleChoice === `system:${role}` ? 'border-fg bg-surface-muted' : 'border-[var(--bs-border)] hover:bg-surface-muted'"><span class="flex items-center gap-3"><input v-model="editRoleChoice" type="radio" name="edit-member-role" :value="`system:${role}`" class="size-4 accent-[var(--bs-accent)]"><span class="font-bold">{{ t(`org.roles.${role}`) }}</span></span><span class="text-xs text-fg-muted">{{ rolePermissionCount(role) }} / {{ capabilities.length }} {{ t('access.permissionsMatrix').toLocaleLowerCase() }}</span></label>
                <label v-for="role in customRoles" :key="role.id" class="flex cursor-pointer items-center justify-between gap-3 rounded-card border p-3 text-sm transition-colors" :class="editRoleChoice === `custom:${role.id}` ? 'border-fg bg-surface-muted' : 'border-[var(--bs-border)] hover:bg-surface-muted'"><span class="flex items-center gap-3"><input v-model="editRoleChoice" type="radio" name="edit-member-role" :value="`custom:${role.id}`" class="size-4 accent-[var(--bs-accent)]"><span class="font-bold">{{ roleLabel(null, role.id) }}</span></span><span class="text-xs text-fg-muted">{{ customPermissionCount(role.id) }} / {{ capabilities.length }} {{ t('access.permissionsMatrix').toLocaleLowerCase() }}</span></label>
              </div>
            </fieldset>
            <p v-if="errorMessage" class="ls-error mt-6" role="alert">{{ errorMessage }}</p>
            <div class="mt-6 flex justify-end gap-2"><button type="button" class="ls-btn" @click="editingMember = null">{{ t('common.cancel') }}</button><button class="ls-btn ls-btn-primary" :disabled="saving">{{ saving ? t('common.saving') : t('access.saveAccess') }}</button></div>
          </form>
        </div>
      </Transition>

      <!-- Permission matrix -->
      <Transition name="ls-modal">
        <div v-if="matrixOpen" class="fixed inset-0 z-[70] grid place-items-center ls-scrim p-4" role="dialog" aria-modal="true" @click.self="matrixOpen = false">
          <div class="ls-modal-panel ls-card max-h-[92dvh] w-full max-w-6xl overflow-y-auto p-6 shadow-overlay">
            <div class="flex items-start justify-between gap-4"><div><h2 class="text-lg font-bold">{{ t('access.permissionsMatrix') }}</h2><p class="mt-1 text-sm text-fg-muted">{{ t('access.matrixHint') }}</p></div><button type="button" class="ls-btn ls-btn-sm" :aria-label="t('common.close')" @click="matrixOpen = false"><AppIcon name="close" /></button></div>
            <div class="mt-6 overflow-x-auto">
              <table class="ls-table">
                <thead><tr><th>{{ t('access.permission') }}</th><th v-for="role in roles" :key="role" class="text-center">{{ t(`org.roles.${role}`) }}</th><th v-for="role in customRoles" :key="role.id" class="text-center">{{ roleLabel(null, role.id) }}</th></tr></thead>
                <template v-for="group in permissionMenuGroups" :key="group.key">
                  <tbody>
                    <tr class="bg-fg text-background"><td :colspan="roles.length + customRoles.length + 1" class="font-bold">{{ t(`nav.groups.${group.key}`) }}</td></tr>
                  </tbody>
                  <tbody v-for="domain in group.domains" :key="domain.key">
                    <tr class="bg-surface-muted"><td :colspan="roles.length + customRoles.length + 1" class="font-bold">{{ t(`access.permissionAreas.${domain.key}`) }}</td></tr>
                    <tr v-for="capability in domain.items" :key="capability.key">
                      <td><p class="font-semibold">{{ capabilityTitle(capability) }}</p></td>
                      <td v-for="role in roles" :key="`${capability.key}-${role}`" class="text-center"><AppIcon v-if="hasRolePermission(role, capability.key)" name="check" :size="18" class="mx-auto text-success" /><span v-else class="text-fg-muted">—</span></td>
                      <td v-for="role in customRoles" :key="`${capability.key}-${role.id}`" class="text-center"><AppIcon v-if="customCapabilitiesFor(role.id).has(capability.key)" name="check" :size="18" class="mx-auto text-success" /><span v-else class="text-fg-muted">—</span></td>
                    </tr>
                  </tbody>
                </template>
              </table>
            </div>
          </div>
        </div>
      </Transition>

      <!-- Create / edit custom role -->
      <Transition name="ls-modal">
        <div v-if="roleModalOpen" class="fixed inset-0 z-[70] grid place-items-center ls-scrim p-4" role="dialog" aria-modal="true" @click.self="roleModalOpen = false">
          <form class="ls-modal-panel ls-card max-h-[90dvh] w-full max-w-3xl overflow-y-auto p-6 shadow-overlay" @submit.prevent="saveRole">
            <div class="flex items-start justify-between gap-4"><div><h2 class="text-lg font-bold">{{ roleForm.id ? t('access.editRole') : t('access.newRole') }}</h2></div><button type="button" class="ls-btn ls-btn-sm" :aria-label="t('common.close')" @click="roleModalOpen = false"><AppIcon name="close" /></button></div>
            <div class="mt-6 grid gap-4 sm:grid-cols-2">
              <FloatingField :label="t('access.roleNameEn')"><input v-model="roleForm.name_en" type="text" class="ls-input" dir="ltr" required maxlength="80"></FloatingField>
              <FloatingField :label="t('access.roleNameAr')"><input v-model="roleForm.name_ar" type="text" class="ls-input" dir="rtl" required maxlength="80"></FloatingField>
            </div>
            <h3 class="mt-7 font-bold">{{ t('access.permission') }}</h3>
            <div class="mt-4 space-y-5">
              <section v-for="group in permissionMenuGroups" :key="group.key">
                <h4 class="rounded-control bg-fg px-4 py-2 text-sm font-bold text-background">{{ t(`nav.groups.${group.key}`) }}</h4>
                <div class="mt-3 grid gap-4 sm:grid-cols-2">
                  <fieldset v-for="domain in group.domains" :key="domain.key" class="rounded-card border border-[var(--bs-border)] p-4">
                    <legend class="px-1 text-sm font-bold">{{ t(`access.permissionAreas.${domain.key}`) }}</legend>
                    <label v-for="capability in domain.items" :key="capability.key" class="mt-3 flex cursor-pointer items-start gap-3 text-sm"><input type="checkbox" class="mt-1 size-4 accent-[var(--bs-accent)]" :checked="roleForm.caps.has(capability.key)" @change="toggleRoleCap(capability.key, ($event.target as HTMLInputElement).checked)"><span class="font-semibold">{{ capabilityTitle(capability) }}</span></label>
                  </fieldset>
                </div>
              </section>
            </div>
            <p v-if="errorMessage" class="ls-error mt-6" role="alert">{{ errorMessage }}</p>
            <div class="mt-6 flex justify-end gap-2"><button type="button" class="ls-btn" @click="roleModalOpen = false">{{ t('common.cancel') }}</button><button class="ls-btn ls-btn-primary" :disabled="roleSaving">{{ roleSaving ? t('common.saving') : t('access.createRole') }}</button></div>
          </form>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

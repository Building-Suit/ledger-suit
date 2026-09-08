<script setup lang="ts">
import type { Database } from '~~/types/database.types'

withDefaults(defineProps<{
  showTrigger?: boolean
}>(), {
  showTrigger: true,
})

const supabase = useSupabaseClient<Database>()
const { currentId, can, roleLabel } = useTenant()
const { t } = useI18n()
const { open, show, close, markChanged } = useTeamInvitation()
const email = ref('')
const role = ref<string>('system:viewer')
const customRoles = ref<Array<{ id: string, name_en: string, name_ar: string }>>([])
const pending = ref(false)
const errorMessage = ref('')
const describeError = useErrorMessage()
const toasts = useToasts()

watch(open, async (isOpen) => {
  if (!isOpen || !currentId.value) return
  const { data } = await supabase.from('organization_roles').select('id, key, name_en, name_ar').eq('organization_id', currentId.value).order('created_at')
  customRoles.value = data ?? []
})

async function invite() {
  if (!currentId.value) return
  pending.value = true; errorMessage.value = ''
  const isCustom = role.value.startsWith('custom:')
  try {
    const { data, error } = await supabase.functions.invoke('send-invitation', {
      body: {
        organizationId: currentId.value,
        email: email.value,
        role: isCustom ? 'viewer' : role.value.slice(7),
        roleId: isCustom ? role.value.slice(7) : null,
      },
    })
    if (error) throw new Error(await edgeFunctionErrorMessage(error, t('errors.generic')))
    markChanged()
    if (!data?.sent) throw new Error(data?.warning ?? t('errors.generic'))
    email.value = ''
    role.value = 'system:viewer'
    close()
    toasts.success(t('access.inviteSent'))
  }
  catch (error) { errorMessage.value = describeError(error) }
  finally { pending.value = false }
}
</script>
<template>
  <div v-if="can('members.invite')">
    <button v-if="showTrigger" type="button" class="ls-btn ls-btn-sm w-full" @click="show">{{ t('org.invite') }}</button>
    <Teleport to="body">
      <div v-if="open" class="fixed inset-0 z-[70] grid place-items-center ls-scrim p-4" role="dialog" aria-modal="true" @click.self="close">
        <form class="ls-modal-panel ls-card w-full max-w-lg space-y-4 p-6 shadow-overlay" @submit.prevent="invite">
          <div class="flex justify-between">
            <h2 class="text-lg font-bold">{{ t('org.invite') }}</h2>
            <button type="button" class="ls-btn ls-btn-sm" :aria-label="t('common.close')" @click="close"><AppIcon name="close" /></button>
          </div>
          <p class="text-sm leading-6 text-fg-muted">{{ t('access.inviteDescription') }}</p>
          <FloatingField :label="t('auth.email')"><input v-model="email" type="email" class="ls-input" :placeholder="t('auth.email')" autocomplete="email" dir="ltr" required></FloatingField>
          <FloatingField :label="t('team.role')"><select v-model="role" class="ls-input">
            <option v-for="key in ['admin','accountant','data_entry','viewer']" :key="key" :value="`system:${key}`">{{ t(`org.roles.${key}`) }}</option>
            <option v-for="custom in customRoles" :key="custom.id" :value="`custom:${custom.id}`">{{ roleLabel(null, custom.id) }}</option>
          </select></FloatingField>
          <div class="flex items-start gap-3 rounded-control bg-surface-muted p-4"><AppIcon name="mail" class="mt-0.5 shrink-0 text-accent" /><div><p class="text-sm font-bold">{{ t('access.emailDelivery') }}</p><p class="mt-1 text-xs leading-5 text-fg-muted">{{ t('access.emailDeliveryHint') }}</p></div></div>
          <button class="ls-btn ls-btn-primary w-full" :disabled="pending">{{ pending ? t('onboarding.sendingOtp') : t('org.createInvite') }}</button>
          <p v-if="errorMessage" class="ls-error">{{ errorMessage }}</p>
        </form>
      </div>
    </Teleport>
  </div>
</template>

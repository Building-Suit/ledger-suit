<script setup lang="ts">
import type { Database } from '~~/types/database.types'
const supabase = useSupabaseClient<Database>()
const { currentId, can } = useTenant()
const { t } = useI18n()
const open = ref(false)
const email = ref('')
const role = ref<Database['public']['Enums']['organization_role']>('viewer')
const token = ref('')
const pending = ref(false)
const errorMessage = ref('')
const describeError = useErrorMessage()

async function invite() {
  if (!currentId.value) return
  pending.value = true; errorMessage.value = ''; token.value = ''
  try {
    const { data, error } = await supabase.rpc('create_organization_invitation' as never, { p_organization_id: currentId.value, p_email: email.value, p_role: role.value } as never)
    if (error) throw error
    token.value = String((data as Array<{ invitation_token: string }> | null)?.[0]?.invitation_token ?? '')
  }
  catch (error) { errorMessage.value = describeError(error) }
  finally { pending.value = false }
}
</script>
<template>
  <div v-if="can('members.invite')"><button type="button" class="ls-btn ls-btn-sm w-full" @click="open = true">{{ t('org.invite') }}</button><Teleport to="body"><div v-if="open" class="fixed inset-0 z-50 grid place-items-center ls-scrim p-4" role="dialog" aria-modal="true" @click.self="open = false"><form class="ls-card w-full max-w-lg space-y-4 p-6" @submit.prevent="invite"><div class="flex justify-between"><h2 class="text-lg font-bold">{{ t('org.invite') }}</h2><button type="button" class="ls-btn ls-btn-sm" @click="open = false">✕</button></div><input v-model="email" type="email" class="ls-input" :placeholder="t('auth.email')" required><select v-model="role" class="ls-input"><option v-for="key in ['admin','accountant','data_entry','viewer']" :key="key" :value="key">{{ t(`org.roles.${key}`) }}</option></select><button class="ls-btn ls-btn-primary w-full" :disabled="pending">{{ t('org.createInvite') }}</button><div v-if="token" class="rounded-control bg-surface-muted p-3"><p class="text-sm font-semibold">{{ t('org.shareToken') }}</p><code class="mt-2 block break-all text-xs" dir="ltr">{{ token }}</code></div><p v-if="errorMessage" class="ls-error">{{ errorMessage }}</p></form></div></Teleport></div>
</template>

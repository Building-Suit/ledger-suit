<script setup lang="ts">
import type { Database } from '~~/types/database.types'
const supabase = useSupabaseClient<Database>()
const { loadOrganizations } = useTenant()
const { t } = useI18n()
const describeError = useErrorMessage()
const route = useRoute()
const name = ref('')
const currency = ref('EGP')
const invitationToken = ref('')
const pending = ref(false)
const errorMessage = ref<string | null>(null)

onMounted(() => {
  if (typeof route.query.invitation === 'string') invitationToken.value = route.query.invitation
})

async function createOrganization() {
  pending.value = true; errorMessage.value = null
  try {
    const { error } = await supabase.rpc('create_organization', { p_name: name.value, p_base_currency: currency.value })
    if (error) throw error
    await loadOrganizations(); await refreshNuxtData()
  }
  catch (error) { errorMessage.value = describeError(error) }
  finally { pending.value = false }
}

async function acceptInvitation() {
  pending.value = true; errorMessage.value = null
  try {
    const { error } = await supabase.rpc('accept_organization_invitation' as never, { p_token: invitationToken.value.trim() } as never)
    if (error) throw error
    await loadOrganizations(); await refreshNuxtData()
  }
  catch (error) { errorMessage.value = describeError(error) }
  finally { pending.value = false }
}
</script>

<template>
  <div class="mx-auto grid max-w-3xl gap-5 md:grid-cols-2">
    <form class="ls-card space-y-4 p-6" @submit.prevent="createOrganization"><h2 class="text-lg font-bold">{{ t('org.create') }}</h2><p class="text-sm text-fg-muted">{{ t('org.createHint') }}</p><div><label class="ls-label" for="org-name">{{ t('org.name') }}</label><input id="org-name" v-model="name" class="ls-input" required></div><div><label class="ls-label" for="org-currency">{{ t('accounts.currency') }}</label><select id="org-currency" v-model="currency" class="ls-input"><option v-for="code in ['EGP','USD','EUR','GBP','SAR','AED']" :key="code">{{ code }}</option></select></div><button class="ls-btn ls-btn-primary w-full" :disabled="pending">{{ t('org.create') }}</button></form>
    <form class="ls-card space-y-4 p-6" @submit.prevent="acceptInvitation"><h2 class="text-lg font-bold">{{ t('org.acceptInvite') }}</h2><p class="text-sm text-fg-muted">{{ t('org.acceptInviteHint') }}</p><div><label class="ls-label" for="invite-token">{{ t('org.inviteToken') }}</label><input id="invite-token" v-model="invitationToken" class="ls-input" dir="ltr" required></div><button class="ls-btn w-full" :disabled="pending">{{ t('org.acceptInvite') }}</button></form>
    <p v-if="errorMessage" class="ls-error md:col-span-2" role="alert">{{ errorMessage }}</p>
  </div>
</template>

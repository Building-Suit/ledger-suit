<script setup lang="ts">
definePageMeta({ layout: false })

const supabase = useSupabaseClient()
const user = useSupabaseUser()
const { t } = useI18n()
const { current, loadOrganizations } = useTenant()
const { checkoutRequired, loading, load } = useBilling()
const { restore } = useTheme()

useHead({ title: () => `${t('billing.title')} · ${t('app.name')}` })

await loadOrganizations()
await load()
onMounted(async () => {
  restore()
  if (!current.value) await loadOrganizations()
  await load()
})

watchEffect(() => {
  if (!user.value) navigateTo('/login')
  else if (current.value && !loading.value && !checkoutRequired.value) navigateTo('/dashboard')
})

async function signOut() {
  await supabase.auth.signOut()
  await navigateTo('/login')
}
</script>

<template>
  <main class="min-h-dvh bg-background px-4 py-6">
    <div class="mx-auto max-w-xl"><header class="flex items-center justify-between gap-4"><NuxtLink to="/" class="inline-flex" aria-label="Ledger Suit home"><AppLogo class="h-14 w-auto max-w-52" /></NuxtLink><div class="flex items-center gap-2"><SettingsMenu /><button type="button" class="ls-btn ls-btn-sm" @click="signOut">{{ t('common.signOut') }}</button></div></header>
      <div v-if="loading" class="py-16 text-center text-sm text-fg-muted">{{ t('app.loading') }}</div>
      <SubscriptionGate v-else-if="current && checkoutRequired" />
    </div>
  </main>
</template>

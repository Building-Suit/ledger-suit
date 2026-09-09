<script setup lang="ts">
definePageMeta({ layout: false })

const supabase = useSupabaseClient()
const { t } = useI18n()
const { current, loadOrganizations } = useTenant()
const { paymentRequired, loading, load } = useBilling()
const { restore } = useTheme()
const route = useRoute()
const redirecting = ref(false)
const checkoutConfirmationActive = ref(false)
const processing = computed(() => route.query.checkout === 'success')

useHead({ title: () => `${t('billing.title')} · ${t('app.name')}` })

await loadOrganizations()
await load()
onMounted(() => {
  restore()
  if (processing.value) {
    checkoutConfirmationActive.value = true
    void confirmCheckout()
  }
})
onBeforeUnmount(() => (checkoutConfirmationActive.value = false))

async function confirmCheckout() {
  // Stripe redirects before its webhook is guaranteed to have updated our
  // subscription row. Poll briefly, then leave an explicit retry button rather
  // than issuing unbounded background requests.
  for (let attempt = 0; attempt < 10 && paymentRequired.value && checkoutConfirmationActive.value; attempt++) {
    try {
      await load({ force: true })
    }
    catch {
      return
    }
    if (!paymentRequired.value) return
    if (attempt < 9) await new Promise(resolve => setTimeout(resolve, 1_500))
  }
}

watch([current, loading, paymentRequired], async () => {
  if (!current.value || loading.value || paymentRequired.value || redirecting.value) return
  redirecting.value = true
  await navigateTo('/dashboard', { replace: true })
}, { immediate: true })

async function signOut() {
  await supabase.auth.signOut()
  await navigateTo('/login')
}
</script>

<template>
  <main class="min-h-dvh bg-background px-4 py-6">
    <div class="mx-auto max-w-xl"><header class="flex flex-wrap items-center justify-between gap-4"><NuxtLink to="/" class="inline-flex" aria-label="Ledger Suit home"><AppLogo class="h-14 w-auto max-w-52" /></NuxtLink><div class="flex items-center gap-2"><SettingsMenu /><button type="button" class="ls-btn ls-btn-sm" @click="signOut">{{ t('common.signOut') }}</button></div><div v-if="current" class="w-full"><OrganizationSwitcher /></div></header>
      <div v-if="loading" class="py-16 text-center text-sm text-fg-muted">{{ t('app.loading') }}</div>
      <SubscriptionGate v-else-if="current && paymentRequired" />
    </div>
  </main>
</template>

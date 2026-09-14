<script setup lang="ts">
const { t } = useI18n()
const { accessState, subscription, load, paymentRequired } = useBilling()
const now = ref(Date.now())
const checkingExpiration = ref(false)

const remainingMilliseconds = computed(() => {
  if (accessState.value !== 'trialing' || !subscription.value?.trial_ends_at) return null
  return Math.max(0, new Date(subscription.value.trial_ends_at).getTime() - now.value)
})

const parts = computed(() => {
  const totalMinutes = Math.ceil((remainingMilliseconds.value ?? 0) / 60_000)
  return {
    days: Math.floor(totalMinutes / (24 * 60)),
    hours: Math.floor((totalMinutes % (24 * 60)) / 60),
    minutes: totalMinutes % 60,
  }
})

let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  now.value = Date.now()
  timer = setInterval(() => (now.value = Date.now()), 30_000)
})
onBeforeUnmount(() => clearInterval(timer))

watch(remainingMilliseconds, async (remaining) => {
  if (remaining !== 0 || checkingExpiration.value) return
  checkingExpiration.value = true
  try {
    await load({ force: true })
    if (paymentRequired.value) await navigateTo('/subscribe', { replace: true })
  }
  finally {
    checkingExpiration.value = false
  }
})
</script>

<template>
  <NuxtLink
    v-if="remainingMilliseconds !== null"
    to="/billing"
    class="inline-flex rounded-full border border-[var(--bs-border)] bg-surface-muted px-3 py-1.5 text-xs font-semibold text-fg"
    :aria-label="t('billing.trialCountdownLabel', parts)"
  >
    <span class="sm:hidden">{{ t('billing.trialCountdownCompact', parts) }}</span>
    <span class="hidden sm:inline">{{ t('billing.trialCountdown', parts) }}</span>
  </NuxtLink>
</template>

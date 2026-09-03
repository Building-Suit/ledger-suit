<script setup lang="ts">
definePageMeta({ layout: false })

const supabase = useSupabaseClient()
const route = useRoute()
const { t } = useI18n()
const { restore } = useTheme()

useHead({ title: () => `${t('onboarding.otpTitle')} · ${t('app.name')}` })

const email = computed(() => typeof route.query.email === 'string' ? route.query.email.trim().toLowerCase() : '')
const otp = ref('')
const pending = ref(false)
const errorMessage = ref('')
const expiresAt = ref(Date.now() + 60 * 60 * 1000)
const resendAvailableAt = ref(Date.now() + 60 * 1000)
const now = ref(Date.now())
const expired = computed(() => now.value >= expiresAt.value)
const resendIn = computed(() => Math.max(0, Math.ceil((resendAvailableAt.value - now.value) / 1000)))

function formatCountdown(seconds: number) {
  return `${Math.floor(seconds / 60).toString().padStart(2, '0')}:${(seconds % 60).toString().padStart(2, '0')}`
}

async function verify() {
  if (!email.value || otp.value.length !== 6 || expired.value) return
  pending.value = true
  errorMessage.value = ''
  try {
    const { data, error } = await supabase.auth.verifyOtp({
      email: email.value,
      token: otp.value,
      type: 'email',
    })
    if (error || !data.session) throw new Error(t('onboarding.otpInvalid'))
    await navigateTo('/dashboard')
  }
  catch (error) {
    errorMessage.value = error instanceof Error ? error.message : t('onboarding.otpInvalid')
    otp.value = ''
  }
  finally { pending.value = false }
}

async function resend() {
  if (!email.value || resendIn.value > 0) return
  pending.value = true
  errorMessage.value = ''
  try {
    const { error } = await supabase.auth.resend({ type: 'signup', email: email.value })
    if (error) throw error
    now.value = Date.now()
    expiresAt.value = now.value + 60 * 60 * 1000
    resendAvailableAt.value = now.value + 60 * 1000
  }
  catch { errorMessage.value = t('onboarding.otpResendFailed') }
  finally { pending.value = false }
}

let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  restore()
  if (!email.value) navigateTo('/login')
  timer = setInterval(() => (now.value = Date.now()), 1000)
})
onBeforeUnmount(() => clearInterval(timer))
</script>

<template>
  <main class="grid min-h-dvh bg-background px-4 py-6 lg:place-items-center">
    <div class="w-full max-w-xl">
      <header class="flex items-center justify-between gap-4"><NuxtLink to="/" class="inline-flex" aria-label="Ledger Suit home"><AppLogo class="h-14 w-auto max-w-52" /></NuxtLink><SettingsMenu /></header>
      <form class="ls-card mx-auto mt-10 p-6 sm:p-9" @submit.prevent="verify">
        <div class="mx-auto max-w-md text-center">
          <div class="mx-auto grid size-14 place-items-center rounded-full bg-surface-muted text-2xl" aria-hidden="true">✉</div>
          <p class="mt-6 text-xs font-bold uppercase tracking-[.18em] text-fg-muted">{{ t('onboarding.otpEyebrow') }}</p>
          <h1 class="mt-2 text-2xl font-black">{{ t('onboarding.otpTitle') }}</h1>
          <p class="mt-3 text-sm leading-6 text-fg-muted">{{ t('onboarding.otpDescription') }}</p>
          <p class="mt-1 break-all font-bold" dir="ltr">{{ email }}</p>
        </div>
        <div class="mx-auto mt-8 max-w-md">
          <OtpInput v-model="otp" :label="t('onboarding.otpLabel')" :disabled="pending || expired" />
          <div class="mt-4 flex items-center justify-between gap-4 text-xs text-fg-muted" aria-live="polite"><span v-if="!expired">{{ t('onboarding.otpExpiresIn', { time: formatCountdown(Math.max(0, Math.ceil((expiresAt - now) / 1000))) }) }}</span><span v-else class="font-semibold text-danger">{{ t('onboarding.otpExpired') }}</span><span>{{ t('onboarding.otpAttemptsHint') }}</span></div>
          <p v-if="errorMessage" class="ls-error mt-5" role="alert">{{ errorMessage }}</p>
          <button class="ls-btn ls-btn-primary mt-6 w-full" :disabled="pending || otp.length !== 6 || expired">{{ pending ? t('onboarding.otpVerifying') : t('onboarding.otpVerify') }}</button>
          <p class="mt-5 text-center text-sm text-fg-muted"><span>{{ t('onboarding.otpMissing') }}</span><button type="button" class="ms-1 font-bold text-link disabled:text-fg-muted" :disabled="pending || resendIn > 0" @click="resend">{{ resendIn > 0 ? t('onboarding.otpResendIn', { time: formatCountdown(resendIn) }) : t('onboarding.otpResend') }}</button></p>
          <div class="mt-7 rounded-card border border-[var(--bs-border)] bg-surface-muted p-4 text-sm text-fg-muted"><p class="font-bold text-fg">{{ t('onboarding.otpSecurityTitle') }}</p><p class="mt-1">{{ t('onboarding.otpSecurityBody') }}</p></div>
        </div>
      </form>
    </div>
  </main>
</template>

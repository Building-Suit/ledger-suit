<script setup lang="ts">
import type { Database } from '~~/types/database.types'

definePageMeta({ layout: false })

type InviteStep = 'loading' | 'ready' | 'otp' | 'password' | 'invalid'
interface InvitationPreview {
  email: string
  organization_name: string
  role: Database['public']['Enums']['organization_role']
  inviter_name: string
  inviter_job_title: string | null
  expires_at: string
  user_exists: boolean
}

const supabase = useSupabaseClient<Database>()
const route = useRoute()
const { t } = useI18n()
const { restore } = useTheme()
const tenant = useTenant()

const token = computed(() => typeof route.query.token === 'string' ? route.query.token.trim() : '')
const preview = ref<InvitationPreview | null>(null)
const step = ref<InviteStep>('loading')
const user = useSupabaseUser()
const fullName = ref('')
const phone = ref('')
const jobTitle = ref('')
const otp = ref('')
const password = ref('')
const confirmPassword = ref('')
const pending = ref(false)
const errorMessage = ref('')
const resendAvailableAt = ref(0)
const now = ref(Date.now())
const resendIn = computed(() => Math.max(0, Math.ceil((resendAvailableAt.value - now.value) / 1000)))

useHead({ title: () => `${preview.value?.organization_name ?? t('access.invitations')} · ${t('app.name')}` })

async function loadPreview() {
  if (!token.value) {
    step.value = 'invalid'
    return
  }
  const { data, error } = await supabase.rpc('preview_organization_invitation', { p_token: token.value })
  const invitation = (data as InvitationPreview[] | null)?.[0]
  if (error || !invitation) {
    step.value = 'invalid'
    return
  }
  preview.value = invitation

  if (invitation.user_exists) {
    if (user.value && user.value.email === invitation.email) {
      try {
        const { error: acceptError } = await supabase.rpc('accept_organization_invitation', { p_token: token.value })
        if (acceptError) throw acceptError
        await tenant.loadOrganizations(user.value.id, { force: true })
        await navigateTo('/dashboard')
        return
      }
      catch {
        step.value = 'invalid'
        return
      }
    } else {
      await navigateTo(`/login?redirect=${encodeURIComponent(route.fullPath)}`)
      return
    }
  }

  step.value = 'ready'
}

async function sendOtp() {
  if (!preview.value || (resendIn.value > 0 && step.value === 'otp')) return
  pending.value = true
  errorMessage.value = ''
  try {
    const { error } = await supabase.auth.signInWithOtp({
      email: preview.value.email,
      options: { shouldCreateUser: true },
    })
    if (error) throw error
    otp.value = ''
    step.value = 'otp'
    resendAvailableAt.value = Date.now() + 60 * 1000
  }
  catch { errorMessage.value = t('auth.failed') }
  finally { pending.value = false }
}

async function verifyOtp() {
  if (!preview.value || otp.value.length !== 6) return
  pending.value = true
  errorMessage.value = ''
  try {
    const { data, error } = await supabase.auth.verifyOtp({
      email: preview.value.email,
      token: otp.value,
      type: 'email',
    })
    if (error || !data.session) throw error ?? new Error('Session missing')
    step.value = 'password'
  }
  catch {
    otp.value = ''
    errorMessage.value = t('access.inviteFlow.otpFailed')
  }
  finally { pending.value = false }
}

async function finish() {
  if (!preview.value || password.value.length < 8) return
  if (password.value !== confirmPassword.value) {
    errorMessage.value = t('access.inviteFlow.passwordMismatch')
    return
  }
  if (!fullName.value || !phone.value || !jobTitle.value) {
    errorMessage.value = t('validation.required')
    return
  }
  pending.value = true
  errorMessage.value = ''
  try {
    const { error: passwordError } = await supabase.auth.updateUser({ password: password.value })
    if (passwordError) throw passwordError
    
    const { data: authData } = await supabase.auth.getUser()
    if (authData.user) {
      const { error: profileError } = await supabase.from('profiles').update({
        full_name: fullName.value,
        phone: phone.value,
        job_title: jobTitle.value
      }).eq('id', authData.user.id)
      if (profileError) throw profileError
    }
    
    const { error: invitationError } = await supabase.rpc('accept_organization_invitation', { p_token: token.value })
    if (invitationError) throw invitationError
    
    if (authData.user) await tenant.loadOrganizations(authData.user.id, { force: true })
    await navigateTo('/dashboard')
  }
  catch { errorMessage.value = t('auth.failed') }
  finally { pending.value = false }
}

let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  restore()
  void loadPreview()
  timer = setInterval(() => (now.value = Date.now()), 1000)
})
onBeforeUnmount(() => clearInterval(timer))
</script>

<template>
  <main class="ls-auth-page min-h-dvh lg:grid lg:grid-cols-[minmax(0,.92fr)_minmax(0,1.08fr)]">
    <section class="ls-auth-panel flex items-center justify-center px-5 py-10 sm:px-8 lg:px-12">
      <div class="w-full max-w-[30rem]">
        <NuxtLink to="/" class="mb-10 inline-flex lg:hidden" aria-label="Ledger Suit home"><AppLogo class="h-14 w-auto max-w-56" /></NuxtLink>

        <div v-if="step === 'loading'" aria-busy="true"><SectionSkeleton variant="table" :rows="4" /></div>

        <section v-else-if="step === 'invalid'" class="ls-auth-card p-8 text-center">
          <span class="mx-auto grid size-14 place-items-center rounded-full bg-[var(--bs-status-error-bg)] text-danger"><AppIcon name="close" :size="26" /></span>
          <h1 class="mt-5 text-2xl font-black">{{ t('access.inviteFlow.invalid') }}</h1>
          <NuxtLink to="/login" class="ls-btn ls-btn-primary mt-7">{{ t('access.inviteFlow.backToLogin') }}</NuxtLink>
        </section>

        <form v-else-if="preview" class="ls-auth-card p-6 sm:p-8" @submit.prevent="step === 'ready' ? sendOtp() : step === 'otp' ? verifyOtp() : finish()">
          <div class="text-center">
            <span class="mx-auto grid size-14 place-items-center rounded-full bg-surface-muted text-primary"><AppIcon :name="step === 'password' ? 'checkBadge' : 'mail'" :size="28" /></span>
            <p class="mt-6 text-xs font-bold uppercase tracking-[.18em] text-fg-muted">{{ t('access.inviteFlow.eyebrow') }}</p>
            <h1 v-if="step === 'ready'" class="mt-2 text-2xl font-black">{{ t('access.inviteFlow.title', { organization: preview.organization_name }) }}</h1>
            <h1 v-else-if="step === 'otp'" class="mt-2 text-2xl font-black">{{ t('access.inviteFlow.otpTitle') }}</h1>
            <h1 v-else class="mt-2 text-2xl font-black">{{ t('access.inviteFlow.passwordTitle') }}</h1>
            <p v-if="step === 'ready'" class="mt-3 text-sm leading-6 text-fg-muted">{{ t('access.inviteFlow.subtitle', { name: preview.inviter_name, jobTitle: preview.inviter_job_title || t('org.roles.admin'), role: t(`org.roles.${preview.role}`) }) }}</p>
            <p v-else-if="step === 'otp'" class="mt-3 text-sm leading-6 text-fg-muted">{{ t('access.inviteFlow.otpBody', { email: preview.email }) }}</p>
            <p v-else class="mt-3 text-sm leading-6 text-fg-muted">{{ t('access.inviteFlow.passwordBody') }}</p>
          </div>

          <div v-if="step === 'ready'" class="mt-8">
            <FloatingField :label="t('access.inviteFlow.emailLabel')"><input :value="preview.email" type="email" class="ls-input" readonly dir="ltr" aria-readonly="true"></FloatingField>
            <button class="ls-btn ls-btn-primary mt-5 w-full" :disabled="pending">{{ pending ? t('access.inviteFlow.sendingOtp') : t('access.inviteFlow.sendOtp') }}</button>
          </div>

          <div v-else-if="step === 'otp'" class="mt-8">
            <OtpInput v-model="otp" :label="t('onboarding.otpLabel')" :disabled="pending" />
            <button class="ls-btn ls-btn-primary mt-6 w-full" :disabled="pending || otp.length !== 6">{{ pending ? t('access.inviteFlow.verifyingOtp') : t('access.inviteFlow.verifyOtp') }}</button>
            <button type="button" class="mt-4 w-full text-center text-sm font-bold text-link disabled:text-fg-muted" :disabled="pending || resendIn > 0" @click="sendOtp">{{ resendIn ? t('onboarding.otpResendIn', { time: `00:${String(resendIn).padStart(2, '0')}` }) : t('access.inviteFlow.resend') }}</button>
          </div>

          <div v-else class="mt-8 space-y-4">
            <FloatingField :label="t('onboarding.fullNameLabel')"><input v-model="fullName" type="text" class="ls-input" required></FloatingField>
            <FloatingField :label="t('onboarding.phoneLabel')"><input v-model="phone" type="tel" class="ls-input" dir="ltr" required></FloatingField>
            <FloatingField :label="t('onboarding.jobTitleLabel')"><input v-model="jobTitle" type="text" class="ls-input" required></FloatingField>
            <div><FloatingField :label="t('access.inviteFlow.password')"><input v-model="password" type="password" minlength="8" autocomplete="new-password" class="ls-input" required dir="ltr"></FloatingField><p class="ls-hint">{{ t('access.inviteFlow.passwordHint') }}</p></div>
            <FloatingField :label="t('access.inviteFlow.confirmPassword')"><input v-model="confirmPassword" type="password" minlength="8" autocomplete="new-password" class="ls-input" required dir="ltr"></FloatingField>
            <button class="ls-btn ls-btn-primary w-full" :disabled="pending || password.length < 8 || confirmPassword.length < 8">{{ pending ? t('access.inviteFlow.finishing') : t('access.inviteFlow.finish') }}</button>
          </div>

          <p v-if="errorMessage" class="ls-error mt-5" role="alert">{{ errorMessage }}</p>
          <div class="mt-7 flex items-start gap-3 rounded-card border border-[var(--bs-border)] bg-surface-muted p-4 text-xs leading-5 text-fg-muted"><AppIcon name="checkBadge" :size="19" class="mt-0.5 shrink-0 text-success" /><p>{{ t('access.inviteFlow.security') }}</p></div>
        </form>
      </div>
    </section>

    <aside class="ls-brand-hero hidden items-center justify-center overflow-hidden px-12 py-16 lg:flex">
      <div class="relative z-10 max-w-lg">
        <AppLogo class="h-20 w-auto max-w-full" />
        <p class="mt-10 text-xs font-bold uppercase tracking-[.22em] text-brand-gold-highlight">{{ t('auth.welcomeEyebrow') }}</p>
        <h2 class="mt-4 text-4xl font-black tracking-[-.05em] text-white">{{ preview?.organization_name || t('app.name') }}</h2>
        <div class="mt-8 space-y-4 text-sm leading-6 text-white/75"><p class="flex items-start gap-3"><AppIcon name="check" class="mt-0.5 shrink-0 text-brand-gold" />{{ t('access.emailDeliveryHint') }}</p><p class="flex items-start gap-3"><AppIcon name="check" class="mt-0.5 shrink-0 text-brand-gold" />{{ t('access.inviteFlow.passwordBody') }}</p><p class="flex items-start gap-3"><AppIcon name="check" class="mt-0.5 shrink-0 text-brand-gold" />{{ t('access.inviteFlow.security') }}</p></div>
      </div>
    </aside>
    <SettingsMenu class="fixed end-4 top-4 z-20" />
  </main>
</template>

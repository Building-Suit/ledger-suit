<script setup lang="ts">
import type { Database } from '~~/types/database.types'

definePageMeta({ layout: false })

type InviteStep = 'loading' | 'ready' | 'otp' | 'password' | 'invalid'
interface InvitationPreview {
  email: string
  organization_name: string
  role: Database['public']['Enums']['organization_role']
  role_key: string | null
  role_name_en: string | null
  role_name_ar: string | null
  inviter_name: string
  inviter_job_title: string | null
  expires_at: string
  user_exists: boolean
}

const supabase = useSupabaseClient<Database>()
const route = useRoute()
const { t, locale } = useI18n()
const { restore } = useTheme()
const tenant = useTenant()

const token = computed(() => typeof route.query.token === 'string' ? route.query.token.trim() : '')
const preview = ref<InvitationPreview | null>(null)
const previewRoleLabel = computed(() => {
  if (!preview.value) return ''
  if (preview.value.role_name_en) return locale.value === 'ar' ? preview.value.role_name_ar : preview.value.role_name_en
  return t(`org.roles.${preview.value.role}`)
})
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
const hydrated = ref(false)
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
    if (user.value?.email?.toLowerCase() === invitation.email.toLowerCase()) {
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
    }
    if (user.value) await supabase.auth.signOut()
    await navigateTo(`/login?redirect=${encodeURIComponent(route.fullPath)}`)
    return
  }
  step.value = 'ready'
}

async function sendOtp() {
  if (!preview.value || (resendIn.value > 0 && step.value === 'otp')) return
  pending.value = true
  errorMessage.value = ''
  try {
    const { error } = await supabase.auth.signInWithOtp({ email: preview.value.email, options: { shouldCreateUser: true } })
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
    const { data, error } = await supabase.auth.verifyOtp({ email: preview.value.email, token: otp.value, type: 'email' })
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
    if (!authData.user || authData.user.email?.toLowerCase() !== preview.value.email.toLowerCase()) throw new Error('Invitation identity mismatch')
    const { error: profileError } = await supabase.from('profiles').update({
      full_name: fullName.value.trim(),
      phone: phone.value.trim(),
      job_title: jobTitle.value.trim(),
    }).eq('id', authData.user.id)
    if (profileError) throw profileError
    const { error: invitationError } = await supabase.rpc('accept_organization_invitation', { p_token: token.value })
    if (invitationError) throw invitationError
    await tenant.loadOrganizations(authData.user.id, { force: true })
    await navigateTo('/dashboard')
  }
  catch { errorMessage.value = t('auth.failed') }
  finally { pending.value = false }
}

let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  restore()
  hydrated.value = true
  void loadPreview()
  timer = setInterval(() => (now.value = Date.now()), 1000)
})
onBeforeUnmount(() => clearInterval(timer))
</script>

<template>
  <main class="ls-auth-page min-h-dvh lg:grid lg:grid-cols-[minmax(0,.92fr)_minmax(0,1.08fr)]">
    <section class="ls-auth-panel flex items-center justify-center px-5 py-10 sm:px-8 lg:px-12">
      <div class="ls-auth-form-shell flex w-full max-w-[27rem] flex-col items-center">
        <NuxtLink to="/" class="mb-12 inline-flex lg:hidden" aria-label="Ledger Suit home">
          <AppLogo class="h-14 w-auto max-w-56" />
        </NuxtLink>
        
        <div v-if="step === 'loading'" aria-busy="true" class="w-full">
          <SectionSkeleton variant="table" :rows="4" />
        </div>

        <section v-else-if="step === 'invalid'" class="ls-auth-card w-full p-8 text-center" :data-hydrated="hydrated">
          <span class="mx-auto grid size-14 place-items-center rounded-full bg-[var(--bs-status-error-bg)] text-danger">
            <AppIcon name="close" :size="26" />
          </span>
          <h1 class="mt-5 text-2xl font-black">{{ t('access.inviteFlow.invalid') }}</h1>
          <NuxtLink to="/login" class="ls-btn ls-btn-primary mt-7 w-full">{{ t('access.inviteFlow.backToLogin') }}</NuxtLink>
        </section>

        <form v-else-if="preview" class="ls-auth-card w-full space-y-5 p-6 text-start sm:p-8" :data-hydrated="hydrated" @submit.prevent="step === 'ready' ? sendOtp() : step === 'otp' ? verifyOtp() : finish()">
          <div class="text-center">
            <p class="ls-auth-eyebrow">{{ t('access.inviteFlow.eyebrow') }}</p>
            <h1 v-if="step === 'ready'" class="mt-2 text-xl font-extrabold tracking-[-.03em]" dir="ltr">{{ t('access.inviteFlow.title', { organization: preview.organization_name }) }}</h1>
            <h1 v-else-if="step === 'otp'" class="mt-2 text-xl font-extrabold tracking-[-.03em]">{{ t('access.inviteFlow.otpTitle') }}</h1>
            <h1 v-else class="mt-2 text-xl font-extrabold tracking-[-.03em]">{{ t('access.inviteFlow.passwordTitle') }}</h1>
            <p v-if="step === 'ready'" class="mt-2 text-sm text-fg-muted">{{ t('access.inviteFlow.subtitle', { name: preview.inviter_name, jobTitle: preview.inviter_job_title || t('org.roles.admin'), role: previewRoleLabel }) }}</p>
            <p v-else-if="step === 'otp'" class="mt-2 text-sm text-fg-muted">{{ t('access.inviteFlow.otpBody', { email: preview.email }) }}</p>
            <p v-else class="mt-2 text-sm text-fg-muted">{{ t('access.inviteFlow.passwordBody') }}</p>
          </div>
          
          <FloatingField :label="t('access.inviteFlow.emailLabel')">
            <input :value="preview.email" type="email" class="ls-input" readonly dir="ltr" aria-readonly="true">
          </FloatingField>
          
          <template v-if="step === 'ready'">
            <button class="ls-btn ls-btn-primary w-full" :disabled="pending">{{ pending ? t('access.inviteFlow.sendingOtp') : t('access.inviteFlow.sendOtp') }}</button>
          </template>
          <template v-else-if="step === 'otp'">
            <OtpInput v-model="otp" :label="t('onboarding.otpLabel')" :disabled="pending" />
            <button class="ls-btn ls-btn-primary w-full" :disabled="pending || otp.length !== 6">{{ pending ? t('access.inviteFlow.verifyingOtp') : t('access.inviteFlow.verifyOtp') }}</button>
            <button type="button" class="w-full text-center text-sm font-bold text-link disabled:text-fg-muted" :disabled="pending || resendIn > 0" @click="sendOtp">{{ resendIn ? t('onboarding.otpResendIn', { time: `00:${String(resendIn).padStart(2, '0')}` }) : t('access.inviteFlow.resend') }}</button>
          </template>
          <template v-else>
          <FloatingField :label="t('onboarding.fullName')">
            <input v-model="fullName" type="text" autocomplete="name" class="ls-input" required>
          </FloatingField>
          <FloatingField :label="t('onboarding.phone')">
            <input v-model="phone" type="tel" autocomplete="tel" class="ls-input" required dir="ltr">
          </FloatingField>
          <FloatingField :label="t('onboarding.jobTitle')">
            <input v-model="jobTitle" type="text" autocomplete="organization-title" class="ls-input" required>
          </FloatingField>
          <FloatingField :label="t('access.inviteFlow.password')">
            <input v-model="password" type="password" minlength="8" autocomplete="new-password" class="ls-input" required dir="ltr">
          </FloatingField>
          
          <FloatingField :label="t('access.inviteFlow.confirmPassword')">
            <input v-model="confirmPassword" type="password" minlength="8" autocomplete="new-password" class="ls-input" required dir="ltr">
          </FloatingField>
          <p v-if="errorMessage" role="alert" class="ls-error">{{ errorMessage }}</p>
          
          <button type="submit" :disabled="pending || password.length < 8 || confirmPassword.length < 8" class="ls-btn ls-btn-primary w-full">
            {{ pending ? t('access.inviteFlow.finishing') : t('access.inviteFlow.finish') }}
          </button>
          </template>
          
          <div class="mt-7 flex items-start gap-3 rounded-card border border-[var(--bs-border)] bg-surface-muted p-4 text-xs leading-5 text-fg-muted">
            <AppIcon name="checkBadge" :size="19" class="mt-0.5 shrink-0 text-success" />
            <p>{{ t('access.inviteFlow.security') }}</p>
          </div>
        </form>
        <div class="mt-5 flex justify-center"><SettingsMenu /></div>
      </div>
    </section>

    <section class="ls-auth-showcase relative hidden overflow-hidden lg:flex lg:items-center lg:justify-center" aria-label="Ledger Suit">
      <div class="ls-auth-orbit ls-auth-orbit-one" aria-hidden="true" />
      <div class="ls-auth-orbit ls-auth-orbit-two" aria-hidden="true" />
      <div class="ls-auth-showcase-content relative z-10 flex max-w-xl flex-col items-center px-12 text-center">
        <NuxtLink to="/" class="ls-auth-brand z-10 inline-flex" aria-label="Ledger Suit home">
          <AppLogo tone="light" class="h-20 w-auto max-w-80" />
        </NuxtLink>
        <h2 class="mt-5 text-5xl font-black leading-[1.25] tracking-[-.045em]">{{ preview?.organization_name || t('app.name') }}</h2>
        <p class="ls-brand-hero-muted mt-6 max-w-lg text-base leading-8">{{ t('auth.welcomeBody') }}</p>
        <div class="ls-auth-ledger mt-12" aria-hidden="true">
          <div class="ls-auth-ledger-top"><span /><span /><span /></div>
          <div class="ls-auth-ledger-row"><span /><i /></div>
          <div class="ls-auth-ledger-row"><span /><i /></div>
          <div class="ls-auth-ledger-row"><span /><i /></div>
        </div>
      </div>
    </section>
  </main>
</template>

<style scoped>
.ls-auth-page { background: var(--bs-bg); }
.ls-auth-panel { background: radial-gradient(circle at 50% 18%, color-mix(in oklab, var(--bs-accent) 9%, transparent), transparent 25rem), var(--bs-bg); }
.ls-auth-eyebrow, .ls-auth-showcase-eyebrow { color: var(--bs-accent); font-size: 11px; font-weight: var(--bs-weight-bold); letter-spacing: .12em; }
.ls-auth-card { border: 1px solid color-mix(in oklab, var(--bs-border) 88%, transparent); border-radius: 20px; background: color-mix(in oklab, var(--bs-surface) 94%, transparent); box-shadow: 0 24px 64px rgb(0 0 0 / .18), 0 1px 0 rgb(255 255 255 / .04) inset; }
.ls-auth-showcase { isolation: isolate; color: var(--bs-pearl-white); background: linear-gradient(135deg, rgb(22 41 59 / .88), rgb(13 27 40 / .98)), var(--bs-gradient-navy); }
.ls-auth-showcase::before { position: absolute; z-index: -1; inset: 0; content: ''; opacity: .75; background-image: linear-gradient(to right, rgb(235 180 90 / .08) 1px, transparent 1px), linear-gradient(to bottom, rgb(235 180 90 / .08) 1px, transparent 1px); background-size: 64px 64px; mask-image: linear-gradient(to bottom, black, transparent 82%); }
.ls-auth-orbit { position: absolute; z-index: -1; border: 1px solid rgb(235 180 90 / .15); border-radius: 999px; pointer-events: none; }
.ls-auth-orbit-one { width: 42rem; height: 42rem; top: 50%; left: 50%; transform: translate(-50%, -50%); }
.ls-auth-orbit-two { width: 28rem; height: 28rem; top: 50%; left: 50%; border-color: rgb(235 180 90 / .09); transform: translate(-50%, -50%); }
.ls-auth-ledger { width: min(100%, 27rem); padding: 20px; border: 1px solid rgb(220 230 241 / .13); border-radius: 18px; background: rgb(10 17 26 / .28); box-shadow: 0 20px 42px rgb(0 0 0 / .14); backdrop-filter: blur(10px); }
.ls-auth-ledger-top, .ls-auth-ledger-row { display: flex; align-items: center; gap: 8px; }
.ls-auth-ledger-top { padding-bottom: 16px; border-bottom: 1px solid rgb(220 230 241 / .1); }
.ls-auth-ledger-top span { width: 7px; height: 7px; border-radius: 999px; background: rgb(235 180 90 / .7); }
.ls-auth-ledger-row { justify-content: space-between; padding-top: 14px; }
.ls-auth-ledger-row span, .ls-auth-ledger-row i { display: block; height: 7px; border-radius: 999px; background: rgb(220 230 241 / .22); }
.ls-auth-ledger-row span { width: 46%; }.ls-auth-ledger-row i { width: 23%; background: rgb(235 180 90 / .72); }
@media (max-width: 1023px) { .ls-auth-card { box-shadow: var(--bs-elevation-2); } }
</style>

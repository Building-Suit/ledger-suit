<script setup lang="ts">
import type { Database } from '~~/types/database.types'

definePageMeta({ layout: false })

interface InvitationPreview {
  email: string
  organization_name: string
  role: Database['public']['Enums']['organization_role']
  inviter_name: string
  inviter_job_title: string | null
  expires_at: string
}

const supabase = useSupabaseClient<Database>()
const route = useRoute()
const { t } = useI18n()
const { restore } = useTheme()
const tenant = useTenant()

const token = computed(() => typeof route.query.token === 'string' ? route.query.token.trim() : '')
const preview = ref<InvitationPreview | null>(null)
const step = ref<'loading' | 'ready' | 'invalid'>('loading')
const password = ref('')
const confirmPassword = ref('')
const pending = ref(false)
const errorMessage = ref('')
const hydrated = ref(false)

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
  step.value = 'ready'
}

async function finish() {
  if (!preview.value || password.value.length < 8) return
  if (password.value !== confirmPassword.value) {
    errorMessage.value = t('access.inviteFlow.passwordMismatch')
    return
  }
  pending.value = true
  errorMessage.value = ''
  try {
    const { data: currentSession } = await supabase.auth.getSession()
    if (currentSession.session && currentSession.session.user.email !== preview.value.email) {
      await supabase.auth.signOut()
    }

    const { error: signUpError } = await supabase.auth.signUp({
      email: preview.value.email,
      password: password.value,
    })
    if (signUpError && !signUpError.message.toLowerCase().includes('already registered')) {
      throw signUpError
    }

    const { error: signInError } = await supabase.auth.signInWithPassword({
      email: preview.value.email,
      password: password.value,
    })
    
    if (signInError) {
      const { data: newSession } = await supabase.auth.getSession()
      if (!newSession.session || newSession.session.user.email !== preview.value.email) {
        throw signInError
      }
    }

    const { error: invitationError } = await supabase.rpc('accept_organization_invitation', { p_token: token.value })
    if (invitationError) throw invitationError
    
    const { data } = await supabase.auth.getUser()
    if (data.user) await tenant.loadOrganizations(data.user.id, { force: true })
    await navigateTo('/dashboard')
  }
  catch (err: any) { 
    errorMessage.value = err?.message || t('auth.failed') 
  }
  finally { pending.value = false }
}

onMounted(() => {
  restore()
  hydrated.value = true
  void loadPreview()
})
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

        <form v-else-if="preview" class="ls-auth-card w-full space-y-5 p-6 text-start sm:p-8" :data-hydrated="hydrated" @submit.prevent="finish">
          <div class="text-center">
            <p class="ls-auth-eyebrow">{{ t('access.inviteFlow.eyebrow') }}</p>
            <h1 class="mt-2 text-xl font-extrabold tracking-[-.03em]" dir="ltr">{{ t('access.inviteFlow.title', { organization: preview.organization_name }) }}</h1>
            <p class="mt-2 text-sm text-fg-muted">{{ t('access.inviteFlow.subtitle', { name: preview.inviter_name, jobTitle: preview.inviter_job_title || t('org.roles.admin'), role: t(`org.roles.${preview.role}`) }) }}</p>
          </div>
          
          <FloatingField :label="t('access.inviteFlow.emailLabel')">
            <input :value="preview.email" type="email" class="ls-input" readonly dir="ltr" aria-readonly="true">
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

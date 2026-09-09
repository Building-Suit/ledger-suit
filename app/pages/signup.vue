<script setup lang="ts">
import type { Database } from '~~/types/database.types'

definePageMeta({ layout: false })

const supabase = useSupabaseClient<Database>()
const { t } = useI18n()
const { restore } = useTheme()
const describeError = useErrorMessage()
const { currentId, loadOrganizations } = useTenant()

useHead({ title: () => `${t('onboarding.title')} · ${t('app.name')}` })

const step = ref(1)
const pending = ref(false)
const errorMessage = ref('')
const awaitingOtp = ref(false)
const otp = ref('')
const otpExpiresAt = ref(0)
const resendAvailableAt = ref(0)
const now = ref(Date.now())
const hydrated = ref(false)
const provisionedOrganizationId = ref<string | null>(null)
const existingAccountOnboarding = ref(false)
const ONBOARDING_STORAGE_KEY = 'ledger-suit.pending-onboarding'
const CHECKOUT_AFTER_VERIFICATION_KEY = 'ledger-suit.checkout-after-verification'
const OTP_EXPIRY_SECONDS = 60 * 60
const RESEND_SECONDS = 60
type BusinessType = Database['public']['Enums']['organization_business_type']
const form = reactive({
  fullName: '', phone: '', jobTitle: '', email: '', password: '',
  organizationName: '', legalName: '', businessType: 'limited_liability' as BusinessType,
  countryCode: 'EG', timezone: 'Africa/Cairo', currency: 'EGP',
  fiscalYearStartMonth: 1, taxIdentifier: '', interval: 'yearly' as 'monthly' | 'yearly',
})

const countries = [
  { code: 'EG', timezone: 'Africa/Cairo', currency: 'EGP' },
  { code: 'SA', timezone: 'Asia/Riyadh', currency: 'SAR' },
  { code: 'AE', timezone: 'Asia/Dubai', currency: 'AED' },
  { code: 'GB', timezone: 'Europe/London', currency: 'GBP' },
  { code: 'US', timezone: 'America/New_York', currency: 'USD' },
]
const supportedCurrencies = ['EGP', 'SAR', 'AED', 'USD', 'GBP', 'EUR'] as const
const businessTypes: BusinessType[] = ['sole_proprietorship', 'partnership', 'limited_liability', 'corporation', 'nonprofit', 'other']
const otpExpiresIn = computed(() => Math.max(0, Math.ceil((otpExpiresAt.value - now.value) / 1000)))
const resendIn = computed(() => Math.max(0, Math.ceil((resendAvailableAt.value - now.value) / 1000)))
const otpExpired = computed(() => awaitingOtp.value && otpExpiresIn.value === 0)

const submitButtonText = computed(() => {
  if (pending.value) {
    if (step.value === 1) return t('onboarding.checkingAvailability')
    if (step.value === 2) return t('onboarding.checkingLegalName')
    return t('onboarding.sendingOtp')
  }
  return step.value < 3 ? t('common.continue') : t('onboarding.continueToPayment')
})

function hasPersonalDetails() {
  return Boolean(form.fullName.trim() && form.phone.trim() && form.jobTitle.trim() && form.email.trim())
}

function hasBusinessDetails() {
  return Boolean(form.organizationName.trim() && form.legalName.trim())
}

function restoreFromUserMetadata(authenticatedUser: { email?: string; user_metadata?: Record<string, unknown> }) {
  const metadata = authenticatedUser.user_metadata ?? {}
  const onboarding = metadata.pending_onboarding
  const pendingOnboarding = onboarding && typeof onboarding === 'object'
    ? onboarding as Record<string, unknown>
    : {}

  form.email = authenticatedUser.email?.trim().toLowerCase() ?? form.email
  if (typeof metadata.full_name === 'string') form.fullName = metadata.full_name
  if (typeof metadata.phone === 'string') form.phone = metadata.phone
  if (typeof metadata.job_title === 'string') form.jobTitle = metadata.job_title
  if (typeof pendingOnboarding.organization_name === 'string') form.organizationName = pendingOnboarding.organization_name
  if (typeof pendingOnboarding.legal_name === 'string') form.legalName = pendingOnboarding.legal_name
  if (businessTypes.includes(pendingOnboarding.business_type as BusinessType)) form.businessType = pendingOnboarding.business_type as BusinessType
  if (countries.some(country => country.code === pendingOnboarding.country_code)) form.countryCode = String(pendingOnboarding.country_code)
  if (typeof pendingOnboarding.timezone === 'string') form.timezone = pendingOnboarding.timezone
  if (typeof pendingOnboarding.base_currency === 'string') {
    const currency = pendingOnboarding.base_currency.trim().toUpperCase()
    if (supportedCurrencies.includes(currency as typeof supportedCurrencies[number])) form.currency = currency
  }
  if (Number.isInteger(pendingOnboarding.fiscal_year_start_month) && Number(pendingOnboarding.fiscal_year_start_month) >= 1 && Number(pendingOnboarding.fiscal_year_start_month) <= 12) {
    form.fiscalYearStartMonth = Number(pendingOnboarding.fiscal_year_start_month)
  }
  if (typeof pendingOnboarding.tax_identifier === 'string') form.taxIdentifier = pendingOnboarding.tax_identifier
  if (pendingOnboarding.billing_interval === 'monthly' || pendingOnboarding.billing_interval === 'yearly') {
    form.interval = pendingOnboarding.billing_interval
  }
}

function formatCountdown(seconds: number) {
  const minutes = Math.floor(seconds / 60).toString().padStart(2, '0')
  const remainder = (seconds % 60).toString().padStart(2, '0')
  return `${minutes}:${remainder}`
}

function savePendingOnboarding() {
  if (!import.meta.client) return
  const { password: _password, ...safeForm } = form
  sessionStorage.setItem(ONBOARDING_STORAGE_KEY, JSON.stringify({
    form: safeForm,
    otpExpiresAt: otpExpiresAt.value,
    resendAvailableAt: resendAvailableAt.value,
    provisionedOrganizationId: provisionedOrganizationId.value,
  }))
}

function clearPendingOnboarding() {
  if (import.meta.client) sessionStorage.removeItem(ONBOARDING_STORAGE_KEY)
}

function showOtpVerification() {
  now.value = Date.now()
  awaitingOtp.value = true
  otp.value = ''
  otpExpiresAt.value = now.value + OTP_EXPIRY_SECONDS * 1000
  resendAvailableAt.value = now.value + RESEND_SECONDS * 1000
  savePendingOnboarding()
}

watch(() => form.countryCode, (code) => {
  const country = countries.find(item => item.code === code)
  if (country) { form.timezone = country.timezone; form.currency = country.currency }
})

async function next() {
  errorMessage.value = ''
  if (step.value === 1 && (!hasPersonalDetails() || (!existingAccountOnboarding.value && form.password.length < 8))) {
    errorMessage.value = t('onboarding.completeRequired')
    return
  }
  if (step.value === 2 && (!form.organizationName.trim() || !form.legalName.trim())) {
    errorMessage.value = t('onboarding.completeRequired')
    return
  }

  pending.value = true
  try {
    if (step.value === 1 && !existingAccountOnboarding.value) {
      const { data, error } = await supabase.rpc('check_owner_availability', {
        p_email: form.email.trim(),
        p_phone: form.phone.trim()
      })
      if (error) throw error
      if (data) {
        const { email_taken, phone_taken } = data as { email_taken: boolean, phone_taken: boolean }
        if (email_taken && phone_taken) {
          errorMessage.value = t('onboarding.bothTaken')
          return
        }
        if (email_taken) {
          errorMessage.value = t('onboarding.emailTaken')
          return
        }
        if (phone_taken) {
          errorMessage.value = t('onboarding.phoneTaken')
          return
        }
      }
    }

    if (step.value === 2) {
      const { data: isAvailable, error } = await supabase.rpc('check_legal_name_availability', {
        p_legal_name: form.legalName.trim()
      })
      if (error) throw error
      if (!isAvailable) {
        errorMessage.value = t('onboarding.legalNameTaken')
        return
      }
    }

    step.value++
  } catch (error) {
    errorMessage.value = error instanceof Error ? error.message : t('errors.generic')
  } finally {
    pending.value = false
  }
}

async function openCheckout(organizationId: string) {
  const { data: checkout, error: checkoutError } = await supabase.functions.invoke('stripe-checkout', {
    body: { organizationId, interval: form.interval },
  })
  if (checkoutError) {
    throw new Error(await edgeFunctionErrorMessage(checkoutError, t('billing.checkoutFailed')))
  }
  if (!checkout?.url) throw new Error(t('billing.checkoutFailed'))
  clearPendingOnboarding()
  window.location.assign(checkout.url)
}

async function provisionAndCheckout(authenticatedUserId?: string) {
  if (provisionedOrganizationId.value) {
    await openCheckout(provisionedOrganizationId.value)
    return
  }

  // New owner signups are provisioned by the auth-user database trigger
  // before the OTP is sent. Reload the membership after confirmation and use
  // the already-stored organization and billing interval.
  await loadOrganizations(authenticatedUserId, { force: true })
  if (currentId.value) {
    provisionedOrganizationId.value = currentId.value
    const { data: subscription, error: subscriptionError } = await supabase
      .from('subscriptions')
      .select('billing_interval')
      .eq('organization_id', currentId.value)
      .maybeSingle()
    if (subscriptionError) throw subscriptionError
    if (subscription?.billing_interval) form.interval = subscription.billing_interval
    await openCheckout(currentId.value)
    return
  }

  // Accounts created just before the durable trigger was deployed can still
  // rebuild from the same server-side metadata that survived the closed tab.
  const { data: resumedOrganizationId, error: resumeError } = await supabase.rpc('resume_saved_signup')
  if (resumeError) throw new Error(describeError(resumeError))
  if (resumedOrganizationId) {
    provisionedOrganizationId.value = resumedOrganizationId
    const { data: subscription, error: subscriptionError } = await supabase
      .from('subscriptions')
      .select('billing_interval')
      .eq('organization_id', resumedOrganizationId)
      .maybeSingle()
    if (subscriptionError) throw subscriptionError
    if (subscription?.billing_interval) form.interval = subscription.billing_interval
    savePendingOnboarding()
    await openCheckout(resumedOrganizationId)
    return
  }

  // Compatibility for older incomplete accounts that have no saved metadata.
  const { data: organizationId, error: onboardingError } = await supabase.rpc('complete_account_onboarding_with_plan', {
    p_full_name: form.fullName.trim(),
    p_phone: form.phone.trim(),
    p_job_title: form.jobTitle.trim(),
    p_organization_name: form.organizationName.trim(),
    p_legal_name: form.legalName.trim(),
    p_business_type: form.businessType,
    p_country_code: form.countryCode,
    p_timezone: form.timezone,
    p_base_currency: form.currency,
    p_fiscal_year_start_month: form.fiscalYearStartMonth,
    p_tax_identifier: form.taxIdentifier.trim() || null,
    p_billing_interval: form.interval,
  })
  if (onboardingError) throw new Error(describeError(onboardingError))
  if (!organizationId) throw new Error(t('errors.generic'))
  provisionedOrganizationId.value = organizationId
  savePendingOnboarding()
  await openCheckout(organizationId)
}

async function createAccount() {
  pending.value = true
  errorMessage.value = ''
  try {
    const { data: auth, error: authError } = await supabase.auth.signUp({
      email: form.email.trim().toLowerCase(),
      password: form.password,
      options: {
        data: {
          full_name: form.fullName.trim(),
          phone: form.phone.trim(),
          job_title: form.jobTitle.trim(),
          // This is recovery state, not authorization data. Keeping it with
          // the unconfirmed auth user lets a later tab finish onboarding after
          // sessionStorage from the original signup tab has disappeared.
          pending_onboarding: {
            organization_name: form.organizationName.trim(),
            legal_name: form.legalName.trim(),
            business_type: form.businessType,
            country_code: form.countryCode,
            timezone: form.timezone,
            base_currency: form.currency,
            fiscal_year_start_month: form.fiscalYearStartMonth,
            tax_identifier: form.taxIdentifier.trim(),
            billing_interval: form.interval,
          },
        },
      },
    })
    if (authError || !auth.user) throw new Error(t('auth.failed'))
    if (!auth.session) showOtpVerification()
    else await provisionAndCheckout(auth.user.id)
  }
  catch (error) {
    errorMessage.value = error instanceof Error ? error.message : t('errors.generic')
  }
  finally { pending.value = false }
}

async function finishOnboarding() {
  if (existingAccountOnboarding.value) {
    pending.value = true
    errorMessage.value = ''
    try { await provisionAndCheckout() }
    catch (error) { errorMessage.value = error instanceof Error ? error.message : t('errors.generic') }
    finally { pending.value = false }
    return
  }

  await createAccount()
}

async function verifyOtpAndContinue() {
  if (otp.value.length !== 6 || otpExpired.value) return
  pending.value = true
  errorMessage.value = ''
  try {
    const { data, error } = await supabase.auth.verifyOtp({
      email: form.email.trim().toLowerCase(),
      token: otp.value,
      type: 'email',
    })
    if (error || !data.session) throw new Error(t('onboarding.otpInvalid'))
    await provisionAndCheckout(data.session.user.id)
  }
  catch (error) {
    errorMessage.value = error instanceof Error ? error.message : t('errors.generic')
    otp.value = ''
  }
  finally { pending.value = false }
}

async function resendOtp() {
  if (resendIn.value > 0) return
  pending.value = true
  errorMessage.value = ''
  try {
    const { error } = await supabase.auth.resend({
      type: 'signup',
      email: form.email.trim().toLowerCase(),
    })
    if (error) throw new Error(t('onboarding.otpResendFailed'))
    showOtpVerification()
  }
  catch (error) { errorMessage.value = error instanceof Error ? error.message : t('errors.generic') }
  finally { pending.value = false }
}

let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  restore()
  hydrated.value = true
  timer = setInterval(() => (now.value = Date.now()), 1000)
  const stored = sessionStorage.getItem(ONBOARDING_STORAGE_KEY)
  if (stored) {
    try {
      const pendingOnboarding = JSON.parse(stored)
      Object.assign(form, pendingOnboarding.form, { password: '' })
      const restoredCurrency = String(form.currency ?? '').trim().toUpperCase()
      const countryDefault = countries.find(country => country.code === form.countryCode)?.currency ?? 'EGP'
      form.currency = supportedCurrencies.includes(restoredCurrency as typeof supportedCurrencies[number])
        ? restoredCurrency
        : countryDefault
      otpExpiresAt.value = Number(pendingOnboarding.otpExpiresAt) || 0
      resendAvailableAt.value = Number(pendingOnboarding.resendAvailableAt) || 0
      provisionedOrganizationId.value = pendingOnboarding.provisionedOrganizationId ?? null
      awaitingOtp.value = Boolean(form.email && (otpExpiresAt.value > Date.now() || provisionedOrganizationId.value))
    }
    catch { clearPendingOnboarding() }
  }

  void restoreAuthenticatedOnboarding()
})
onBeforeUnmount(() => clearInterval(timer))

async function restoreAuthenticatedOnboarding() {
  const { data } = await supabase.auth.getUser()
  if (!data.user) return

  existingAccountOnboarding.value = true
  awaitingOtp.value = false
  restoreFromUserMetadata(data.user)

  await loadOrganizations(data.user.id, { force: true })
  if (currentId.value) {
    const checkoutAfterVerification = sessionStorage.getItem(CHECKOUT_AFTER_VERIFICATION_KEY) === '1'
    sessionStorage.removeItem(CHECKOUT_AFTER_VERIFICATION_KEY)
    if (checkoutAfterVerification) {
      pending.value = true
      errorMessage.value = ''
      try { await provisionAndCheckout(data.user.id) }
      catch (error) { errorMessage.value = error instanceof Error ? error.message : t('errors.generic') }
      finally { pending.value = false }
      return
    }
    await navigateTo('/dashboard')
    return
  }

  step.value = hasBusinessDetails() ? 3 : (hasPersonalDetails() ? 2 : 1)
  if (!hasPersonalDetails() || !hasBusinessDetails()) return

  pending.value = true
  errorMessage.value = ''
  try {
    await provisionAndCheckout()
  }
  catch (error) {
    errorMessage.value = error instanceof Error ? error.message : t('errors.generic')
  }
  finally { pending.value = false }
}
</script>

<template>
  <main class="min-h-dvh bg-background px-4 py-6 lg:px-8">
    <div class="mx-auto max-w-6xl">
      <header class="flex items-center justify-between gap-4"><NuxtLink to="/" class="inline-flex" aria-label="Ledger Suit home">
        <AppLogo class="h-14 w-auto max-w-52" />
      </NuxtLink>
      <div class="flex items-center gap-2"><SettingsMenu /><NuxtLink to="/login" class="ls-btn ls-btn-sm">{{ t('auth.signIn') }}</NuxtLink></div></header>

      <div class="mx-auto mt-12 grid max-w-5xl gap-8 lg:grid-cols-[.72fr_1.28fr]">
        <aside class="ls-brand-hero rounded-modal p-8 lg:sticky lg:top-6 lg:self-start">
          <p class="ls-brand-hero-muted text-xs font-bold uppercase tracking-[.2em]">{{ t('onboarding.eyebrow') }}</p>
          <h1 class="mt-4 text-3xl font-black tracking-[-.04em]">{{ t('onboarding.title') }}</h1>
          <p class="ls-brand-hero-muted mt-3 text-sm leading-6">{{ t('onboarding.subtitle') }}</p>
          <ol class="mt-8 space-y-6">
            <li v-for="index in 3" :key="index" class="flex gap-3" :class="index > step ? 'opacity-40' : ''"><span class="grid size-8 shrink-0 place-items-center rounded-full border border-[var(--bs-steel-border)] text-xs font-bold" :class="index === step ? 'bg-[var(--bs-premium-gold)] text-[var(--bs-deep-structure-navy)]' : ''">{{ index }}</span><div><p class="font-bold">{{ t(`onboarding.steps.${index}.title`) }}</p><p class="ls-brand-hero-muted text-xs">{{ t(`onboarding.steps.${index}.body`) }}</p></div></li>
          </ol>
        </aside>

        <form v-if="!awaitingOtp" class="ls-card p-6 sm:p-8" :data-hydrated="hydrated" @submit.prevent="step < 3 ? next() : finishOnboarding()">
          <div class="mb-8 flex items-center justify-between"><div><p class="text-xs font-bold text-fg-muted">{{ t('onboarding.stepCount', { step }) }}</p><h2 class="mt-1 text-2xl font-black">{{ t(`onboarding.steps.${step}.title`) }}</h2></div><button v-if="step > 1" type="button" class="ls-btn ls-btn-sm" @click="step--">{{ t('common.back') }}</button></div>

          <div v-if="step === 1" class="grid gap-4 sm:grid-cols-2">
            <FloatingField class="sm:col-span-2" :label="t('onboarding.fullName')"><input id="owner-name" v-model="form.fullName" class="ls-input" autocomplete="name" required></FloatingField>
            <FloatingField :label="t('onboarding.phone')"><input id="owner-phone" v-model="form.phone" class="ls-input" autocomplete="tel" dir="ltr" required></FloatingField>
            <FloatingField :label="t('onboarding.jobTitle')"><input id="owner-role" v-model="form.jobTitle" class="ls-input" required></FloatingField>
            <FloatingField :label="t('auth.email')"><input id="owner-email" v-model="form.email" type="email" class="ls-input" autocomplete="email" dir="ltr" :readonly="existingAccountOnboarding" required></FloatingField>
            <div v-if="!existingAccountOnboarding"><FloatingField :label="t('auth.password')"><input id="owner-password" v-model="form.password" type="password" minlength="8" class="ls-input" autocomplete="new-password" dir="ltr" required></FloatingField><p class="ls-hint">{{ t('onboarding.passwordHint') }}</p></div>
          </div>

          <div v-else-if="step === 2" class="grid gap-4 sm:grid-cols-2">
            <FloatingField :label="t('org.name')"><input id="org-display-name" v-model="form.organizationName" class="ls-input" required></FloatingField>
            <FloatingField :label="t('onboarding.legalName')"><input id="org-legal-name" v-model="form.legalName" class="ls-input" required></FloatingField>
            <FloatingField :label="t('onboarding.businessType')"><select id="org-type" v-model="form.businessType" class="ls-input"><option v-for="type in businessTypes" :key="type" :value="type">{{ t(`onboarding.businessTypes.${type}`) }}</option></select></FloatingField>
            <FloatingField :label="t('onboarding.country')"><select id="org-country" v-model="form.countryCode" class="ls-input"><option v-for="country in countries" :key="country.code" :value="country.code">{{ t(`onboarding.countries.${country.code}`) }}</option></select></FloatingField>
              <FloatingField :label="t('accounts.currency')"><select id="org-currency" v-model="form.currency" class="ls-input"><option v-for="currency in supportedCurrencies" :key="currency">{{ currency }}</option></select></FloatingField>
            <FloatingField :label="t('onboarding.timezone')"><input id="org-timezone" v-model="form.timezone" class="ls-input" dir="ltr" required></FloatingField>
            <FloatingField :label="t('onboarding.fiscalYear')"><select id="org-fiscal" v-model.number="form.fiscalYearStartMonth" class="ls-input"><option v-for="month in 12" :key="month" :value="month">{{ t(`onboarding.months.${month}`) }}</option></select></FloatingField>
            <div><FloatingField :label="t('onboarding.taxIdentifier')"><input id="org-tax" v-model="form.taxIdentifier" class="ls-input"></FloatingField><p class="ls-hint">{{ t('onboarding.optional') }}</p></div>
          </div>

          <div v-else class="space-y-6">
            <div class="grid gap-3 sm:grid-cols-2">
              <label v-for="option in (['monthly','yearly'] as const)" :key="option" class="cursor-pointer rounded-card border p-6" :class="form.interval === option ? 'border-fg bg-surface-muted' : 'border-[var(--bs-border)]'"><input v-model="form.interval" type="radio" class="sr-only" :value="option"><span class="font-bold">{{ t(`billing.${option}`) }}</span><span class="mt-2 block text-2xl font-black">{{ t(`billing.${option}Price`) }}</span><span v-if="option === 'yearly'" class="mt-2 inline-block rounded-full bg-fg px-2 py-1 text-xs font-bold text-background">{{ t('landing.bestValue') }}</span></label>
            </div>
            <div class="rounded-card border border-[var(--bs-border)] bg-surface-muted p-6"><h3 class="font-bold">{{ t('onboarding.readyTitle') }}</h3><ul class="mt-3 grid gap-2 text-sm text-fg-muted sm:grid-cols-2"><li class="flex items-center gap-2"><AppIcon name="check" :size="18" class="text-[var(--bs-status-success)]" />{{ t('billing.featureAccounting') }}</li><li class="flex items-center gap-2"><AppIcon name="check" :size="18" class="text-[var(--bs-status-success)]" />{{ t('billing.featureAutomation') }}</li><li class="flex items-center gap-2"><AppIcon name="check" :size="18" class="text-[var(--bs-status-success)]" />{{ t('billing.featureTeam') }}</li><li class="flex items-center gap-2"><AppIcon name="check" :size="18" class="text-[var(--bs-status-success)]" />{{ t('onboarding.readyAccounts') }}</li></ul></div>
            <p class="text-sm text-fg-muted">{{ t('onboarding.paymentExplanation') }}</p>
          </div>

          <p v-if="errorMessage" class="ls-error mt-6" role="alert">{{ errorMessage }}</p>
          <button class="ls-btn ls-btn-primary mt-8 w-full" :disabled="pending">{{ submitButtonText }}</button>
          <p v-if="step === 3" class="mt-3 text-center text-xs text-fg-muted">{{ t('billing.paymentRequired') }}</p>
        </form>

        <form v-else class="ls-card p-6 sm:p-8" :data-hydrated="hydrated" @submit.prevent="verifyOtpAndContinue">
          <div class="mx-auto max-w-lg text-center">
            <div class="mx-auto grid size-14 place-items-center rounded-full bg-surface-muted text-primary"><AppIcon name="mail" :size="28" /></div>
            <p class="mt-6 text-xs font-bold uppercase tracking-[.18em] text-fg-muted">{{ t('onboarding.otpEyebrow') }}</p>
            <h2 class="mt-2 text-2xl font-black">{{ t('onboarding.otpTitle') }}</h2>
            <p class="mt-3 text-sm leading-6 text-fg-muted">{{ t('onboarding.otpDescription') }}</p>
            <p class="mt-1 break-all font-bold" dir="ltr">{{ form.email }}</p>
          </div>

          <div class="mx-auto mt-8 max-w-md">
            <OtpInput v-model="otp" :label="t('onboarding.otpLabel')" :disabled="pending || otpExpired" />

            <div class="mt-4 flex items-center justify-between gap-4 text-xs text-fg-muted" aria-live="polite">
              <span v-if="!otpExpired">{{ t('onboarding.otpExpiresIn', { time: formatCountdown(otpExpiresIn) }) }}</span>
              <span v-else class="font-semibold text-danger">{{ t('onboarding.otpExpired') }}</span>
              <span>{{ t('onboarding.otpAttemptsHint') }}</span>
            </div>

            <p v-if="errorMessage" class="ls-error mt-6" role="alert">{{ errorMessage }}</p>

            <button class="ls-btn ls-btn-primary mt-6 w-full" :disabled="pending || otp.length !== 6 || otpExpired">
              {{ pending ? t('onboarding.otpVerifying') : t('onboarding.otpVerify') }}
            </button>

            <div class="mt-6 text-center text-sm text-fg-muted">
              <span>{{ t('onboarding.otpMissing') }}</span>
              <button type="button" class="ms-1 font-bold text-fg underline underline-offset-4 disabled:no-underline disabled:opacity-50" :disabled="pending || resendIn > 0" @click="resendOtp">
                {{ resendIn > 0 ? t('onboarding.otpResendIn', { time: formatCountdown(resendIn) }) : t('onboarding.otpResend') }}
              </button>
            </div>

            <div class="mt-8 rounded-control border border-[var(--bs-border)] bg-surface-muted p-4 text-xs leading-5 text-fg-muted">
              <p class="font-bold text-fg">{{ t('onboarding.otpSecurityTitle') }}</p>
              <p class="mt-1">{{ t('onboarding.otpSecurityBody') }}</p>
            </div>
          </div>
        </form>
      </div>
    </div>
  </main>
</template>

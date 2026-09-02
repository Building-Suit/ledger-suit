<script setup lang="ts">
import type { Database } from '~~/types/database.types'

definePageMeta({ layout: false })

const supabase = useSupabaseClient<Database>()
const user = useSupabaseUser()
const { t } = useI18n()
const { restore } = useTheme()

useHead({ title: () => `${t('onboarding.title')} · ${t('app.name')}` })
onMounted(restore)

const step = ref(1)
const pending = ref(false)
const errorMessage = ref('')
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
const businessTypes: BusinessType[] = ['sole_proprietorship', 'partnership', 'limited_liability', 'corporation', 'nonprofit', 'other']

watch(() => form.countryCode, (code) => {
  const country = countries.find(item => item.code === code)
  if (country) { form.timezone = country.timezone; form.currency = country.currency }
})

function next() {
  errorMessage.value = ''
  if (step.value === 1 && (!form.fullName.trim() || !form.phone.trim() || !form.jobTitle.trim() || !form.email.trim() || form.password.length < 8)) {
    errorMessage.value = t('onboarding.completeRequired')
    return
  }
  if (step.value === 2 && (!form.organizationName.trim() || !form.legalName.trim())) {
    errorMessage.value = t('onboarding.completeRequired')
    return
  }
  step.value++
}

async function createAndCheckout() {
  pending.value = true
  errorMessage.value = ''
  try {
    const { data: auth, error: authError } = await supabase.auth.signUp({
      email: form.email.trim().toLowerCase(),
      password: form.password,
      options: { data: { full_name: form.fullName.trim(), phone: form.phone.trim(), job_title: form.jobTitle.trim() } },
    })
    if (authError || !auth.user) throw new Error(t('auth.failed'))
    if (!auth.session) throw new Error(t('onboarding.confirmEmailFirst'))

    const { data: organizationId, error: onboardingError } = await supabase.rpc('complete_account_onboarding', {
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
      p_tax_identifier: form.taxIdentifier.trim() || undefined,
    })
    if (onboardingError || !organizationId) throw onboardingError ?? new Error(t('errors.generic'))

    const { data: checkout, error: checkoutError } = await supabase.functions.invoke('stripe-checkout', {
      body: { organizationId, interval: form.interval },
    })
    if (checkoutError || !checkout?.url) throw checkoutError ?? new Error(t('billing.checkoutFailed'))
    window.location.assign(checkout.url)
  }
  catch (error) {
    errorMessage.value = error instanceof Error ? error.message : t('errors.generic')
  }
  finally { pending.value = false }
}

watchEffect(() => {
  if (user.value && step.value === 1) navigateTo('/dashboard')
})
</script>

<template>
  <main class="min-h-dvh bg-background px-4 py-6 lg:px-8">
    <div class="mx-auto max-w-6xl">
      <header class="flex items-center justify-between gap-4"><NuxtLink to="/" class="text-lg font-black tracking-[-.04em]" dir="ltr">
        Ledger Suit
        <span class="text-xs font-semibold" dir="ltr"> by Building Suit </span>
      </NuxtLink>
      <div class="flex items-center gap-2"><SettingsMenu /><NuxtLink to="/login" class="ls-btn ls-btn-sm">{{ t('auth.signIn') }}</NuxtLink></div></header>

      <div class="mx-auto mt-10 grid max-w-5xl gap-8 lg:grid-cols-[.72fr_1.28fr]">
        <aside class="rounded-modal bg-[var(--bs-ink)] p-7 text-[var(--bs-paper)] lg:sticky lg:top-6 lg:self-start">
          <p class="text-xs font-bold uppercase tracking-[.2em] text-[var(--bs-gray-400)]">{{ t('onboarding.eyebrow') }}</p>
          <h1 class="mt-4 text-3xl font-black tracking-[-.04em]">{{ t('onboarding.title') }}</h1>
          <p class="mt-3 text-sm leading-6 text-[var(--bs-gray-400)]">{{ t('onboarding.subtitle') }}</p>
          <ol class="mt-9 space-y-5">
            <li v-for="index in 3" :key="index" class="flex gap-3" :class="index > step ? 'opacity-40' : ''"><span class="grid h-7 w-7 shrink-0 place-items-center rounded-full border border-[var(--bs-gray-600)] text-xs font-bold" :class="index === step ? 'bg-[var(--bs-paper)] text-[var(--bs-ink)]' : ''">{{ index }}</span><div><p class="font-bold text-[var(--bs-paper)]">{{ t(`onboarding.steps.${index}.title`) }}</p><p class="text-xs text-[var(--bs-gray-400)]">{{ t(`onboarding.steps.${index}.body`) }}</p></div></li>
          </ol>
        </aside>

        <form class="ls-card p-6 sm:p-9" @submit.prevent="step < 3 ? next() : createAndCheckout()">
          <div class="mb-7 flex items-center justify-between"><div><p class="text-xs font-bold text-fg-muted">{{ t('onboarding.stepCount', { step }) }}</p><h2 class="mt-1 text-2xl font-black">{{ t(`onboarding.steps.${step}.title`) }}</h2></div><button v-if="step > 1" type="button" class="ls-btn ls-btn-sm" @click="step--">{{ t('common.back') }}</button></div>

          <div v-if="step === 1" class="grid gap-4 sm:grid-cols-2">
            <div class="sm:col-span-2"><label class="ls-label" for="owner-name">{{ t('onboarding.fullName') }}</label><input id="owner-name" v-model="form.fullName" class="ls-input" autocomplete="name" required></div>
            <div><label class="ls-label" for="owner-phone">{{ t('onboarding.phone') }}</label><input id="owner-phone" v-model="form.phone" class="ls-input" autocomplete="tel" dir="ltr" required></div>
            <div><label class="ls-label" for="owner-role">{{ t('onboarding.jobTitle') }}</label><input id="owner-role" v-model="form.jobTitle" class="ls-input" required></div>
            <div><label class="ls-label" for="owner-email">{{ t('auth.email') }}</label><input id="owner-email" v-model="form.email" type="email" class="ls-input" autocomplete="email" dir="ltr" required></div>
            <div><label class="ls-label" for="owner-password">{{ t('auth.password') }}</label><input id="owner-password" v-model="form.password" type="password" minlength="8" class="ls-input" autocomplete="new-password" dir="ltr" required><p class="ls-hint">{{ t('onboarding.passwordHint') }}</p></div>
          </div>

          <div v-else-if="step === 2" class="grid gap-4 sm:grid-cols-2">
            <div><label class="ls-label" for="org-display-name">{{ t('org.name') }}</label><input id="org-display-name" v-model="form.organizationName" class="ls-input" required></div>
            <div><label class="ls-label" for="org-legal-name">{{ t('onboarding.legalName') }}</label><input id="org-legal-name" v-model="form.legalName" class="ls-input" required></div>
            <div><label class="ls-label" for="org-type">{{ t('onboarding.businessType') }}</label><select id="org-type" v-model="form.businessType" class="ls-input"><option v-for="type in businessTypes" :key="type" :value="type">{{ t(`onboarding.businessTypes.${type}`) }}</option></select></div>
            <div><label class="ls-label" for="org-country">{{ t('onboarding.country') }}</label><select id="org-country" v-model="form.countryCode" class="ls-input"><option v-for="country in countries" :key="country.code" :value="country.code">{{ t(`onboarding.countries.${country.code}`) }}</option></select></div>
            <div><label class="ls-label" for="org-currency">{{ t('accounts.currency') }}</label><select id="org-currency" v-model="form.currency" class="ls-input"><option v-for="currency in ['EGP','SAR','AED','USD','GBP','EUR']" :key="currency">{{ currency }}</option></select></div>
            <div><label class="ls-label" for="org-timezone">{{ t('onboarding.timezone') }}</label><input id="org-timezone" v-model="form.timezone" class="ls-input" dir="ltr" required></div>
            <div><label class="ls-label" for="org-fiscal">{{ t('onboarding.fiscalYear') }}</label><select id="org-fiscal" v-model.number="form.fiscalYearStartMonth" class="ls-input"><option v-for="month in 12" :key="month" :value="month">{{ t(`onboarding.months.${month}`) }}</option></select></div>
            <div><label class="ls-label" for="org-tax">{{ t('onboarding.taxIdentifier') }}</label><input id="org-tax" v-model="form.taxIdentifier" class="ls-input"><p class="ls-hint">{{ t('onboarding.optional') }}</p></div>
          </div>

          <div v-else class="space-y-5">
            <div class="grid gap-3 sm:grid-cols-2">
              <label v-for="option in (['monthly','yearly'] as const)" :key="option" class="cursor-pointer rounded-card border p-5" :class="form.interval === option ? 'border-fg bg-surface-muted' : 'border-[var(--bs-border)]'"><input v-model="form.interval" type="radio" class="sr-only" :value="option"><span class="font-bold">{{ t(`billing.${option}`) }}</span><span class="mt-2 block text-2xl font-black">{{ t(`billing.${option}Price`) }}</span><span v-if="option === 'yearly'" class="mt-2 inline-block rounded-full bg-fg px-2 py-1 text-xs font-bold text-background">{{ t('landing.bestValue') }}</span></label>
            </div>
            <div class="rounded-card border border-[var(--bs-border)] bg-surface-muted p-5"><h3 class="font-bold">{{ t('onboarding.readyTitle') }}</h3><ul class="mt-3 grid gap-2 text-sm text-fg-muted sm:grid-cols-2"><li>✓ {{ t('billing.featureAccounting') }}</li><li>✓ {{ t('billing.featureAutomation') }}</li><li>✓ {{ t('billing.featureTeam') }}</li><li>✓ {{ t('onboarding.readyAccounts') }}</li></ul></div>
            <p class="text-sm text-fg-muted">{{ t('onboarding.paymentExplanation') }}</p>
          </div>

          <p v-if="errorMessage" class="ls-error mt-5" role="alert">{{ errorMessage }}</p>
          <button class="ls-btn ls-btn-primary mt-7 w-full" :disabled="pending">{{ pending ? t('onboarding.creating') : step < 3 ? t('common.continue') : t('onboarding.continueToPayment') }}</button>
          <p v-if="step === 3" class="mt-3 text-center text-xs text-fg-muted">{{ t('billing.paymentRequired') }}</p>
        </form>
      </div>
    </div>
  </main>
</template>

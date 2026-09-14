<script setup lang="ts">
import type { Database, Json } from '~~/types/database.types'
import type { LaunchPlanKey } from '~/composables/useBilling'

const { compact = false, surface = 'checkout' } = defineProps<{
  compact?: boolean
  surface?: 'checkout' | 'public' | 'display' | 'manage'
}>()
const supabase = useSupabaseClient<Database>()
const { currentId } = useTenant()
const { rows: usageRows } = usePlanUsage()
const { createCheckoutSession, accessState, subscription } = useBilling()
const { t, locale } = useI18n()
const interval = ref<'monthly' | 'yearly'>('monthly')
const pendingPlan = ref<LaunchPlanKey | null>(null)
const reviewingPlan = ref<LaunchPlanKey | null>(null)
const errorMessage = ref('')
const describeError = useErrorMessage()

type CatalogPlan = Database['public']['Functions']['subscription_plan_catalog']['Returns'][number]
type JsonObject = Record<string, Json | undefined>
interface PlanChangeImpact {
  current_plan_key: string
  current_interval: Database['public']['Enums']['billing_interval'] | null
  target_plan_key: string
  target_interval: Database['public']['Enums']['billing_interval']
  target_amount_minor: number
  change_direction: string
  provider_change_supported: boolean
  requires_manual_handoff: boolean
  would_block_new_activity: boolean
  audit_history_current_days: number | null
  audit_history_target_days: number
  audit_history_reduced: boolean
  quota_impacts: unknown
  feature_impacts: unknown
}
interface QuotaImpact {
  quota_key: string
  used_value: number
  current_limit_value: number | null
  target_limit_value: number | null
  is_over_target: boolean
  will_block_new_activity: boolean
}
interface FeatureImpact {
  feature_key: string
  current_enabled: boolean
  target_enabled: boolean
  will_gain: boolean
  will_lose: boolean
}

const planImpact = ref<PlanChangeImpact | null>(null)
const currentPlanKey = computed(() => usageRows.value[0]?.plan_key ?? null)
const currentPlanKind = computed(() => {
  if (currentPlanKey.value === null) return null
  if (currentPlanKey.value === 'trial') return 'trial'
  if (['solo', 'starter', 'business'].includes(currentPlanKey.value)) return 'launch'
  if (currentPlanKey.value === 'ledger_suit' || currentPlanKey.value.startsWith('legacy_')) return 'compatibility'
  return 'unknown'
})
const trialPlanCurrent = computed(() => currentPlanKind.value === 'trial')
const launchPlanCurrent = computed(() => currentPlanKind.value === 'launch')
const compatibilityPlanCurrent = computed(() => currentPlanKind.value === 'compatibility')

const { data: catalog, pending: catalogPending, error: catalogError, refresh } = await useAsyncData(
  'launch-plan-catalog',
  async () => {
    const { data, error } = await supabase.rpc('subscription_plan_catalog')
    if (error) throw error
    return data
  },
)

const plans = computed(() => (catalog.value ?? []).filter(
  plan => ['solo', 'starter', 'business', 'scale'].includes(plan.plan_key),
))

function object(value: Json | undefined): JsonObject {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as JsonObject : {}
}

function priceAmount(plan: CatalogPlan, billingInterval: 'monthly' | 'yearly'): number | null {
  const price = object(object(plan.prices)[billingInterval])
  return typeof price.amount_minor === 'number' ? price.amount_minor : null
}

function amount(plan: CatalogPlan): number | null {
  return priceAmount(plan, interval.value)
}

function yearlyOriginalAmount(plan: CatalogPlan): number | null {
  const monthly = priceAmount(plan, 'monthly')
  return monthly === null ? null : monthly * 12
}

function yearlyMonthlyAmount(plan: CatalogPlan): number | null {
  const yearly = priceAmount(plan, 'yearly')
  return yearly === null ? null : yearly / 12
}

function yearlyDiscount(plan: CatalogPlan): number | null {
  const original = yearlyOriginalAmount(plan)
  const yearly = priceAmount(plan, 'yearly')
  return original && yearly !== null ? Math.round((1 - yearly / original) * 100) : null
}

function formatAmount(amountMinor: number): string {
  return new Intl.NumberFormat(locale.value === 'ar' ? 'ar-EG' : 'en-US', {
    minimumFractionDigits: amountMinor % 100 === 0 ? 0 : 2,
    maximumFractionDigits: 2,
  }).format(amountMinor / 100)
}

function formatDate(value: string | null | undefined): string {
  return value
    ? new Intl.DateTimeFormat(locale.value, { dateStyle: 'long' }).format(new Date(value))
    : '—'
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat(locale.value === 'ar' ? 'ar-EG' : 'en-US', {
    maximumFractionDigits: 1,
  }).format(value)
}

function formatBytes(value: number): string {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'] as const
  let amount = value
  let index = 0
  while (amount >= 1024 && index < units.length - 1) {
    amount /= 1024
    index++
  }
  return `${formatNumber(amount)} ${t(`usage.units.${units[index]}`)}`
}

function formatQuota(quotaKey: string, value: number | null): string {
  if (value === null) return t('usage.unlimited')
  return quotaKey === 'max_storage_bytes' ? formatBytes(value) : formatNumber(value)
}

const quotaImpacts = computed<QuotaImpact[]>(() => {
  const value: unknown = planImpact.value?.quota_impacts
  return Array.isArray(value) ? value as QuotaImpact[] : []
})
const lostFeatures = computed<FeatureImpact[]>(() => {
  const value: unknown = planImpact.value?.feature_impacts
  return Array.isArray(value) ? (value as FeatureImpact[]).filter(feature => feature.will_lose) : []
})
const gainedFeatures = computed<FeatureImpact[]>(() => {
  const value: unknown = planImpact.value?.feature_impacts
  return Array.isArray(value) ? (value as FeatureImpact[]).filter(feature => feature.will_gain) : []
})
const auditHistoryIncreased = computed(() => planImpact.value?.audit_history_current_days !== null
  && planImpact.value?.audit_history_current_days !== undefined
  && planImpact.value.audit_history_target_days > planImpact.value.audit_history_current_days)

function featureName(key: string): string {
  const translationKey = key === 'multi_currency' ? 'multiCurrency' : key === 'priority_support' ? 'prioritySupport' : key
  return t(`billing.plans.features.${translationKey}`)
}

function limit(plan: CatalogPlan, key: string): number | null {
  const entitlement = object(object(plan.entitlements)[key])
  return typeof entitlement.limit_value === 'number' ? entitlement.limit_value : null
}

function included(plan: CatalogPlan, key: string): boolean {
  return object(object(plan.entitlements)[key]).is_enabled === true
}

function featureRows(plan: CatalogPlan) {
  if (plan.plan_key === 'scale') return []
  return [
    { key: 'members', included: true, text: t('billing.plans.features.members', { count: limit(plan, 'max_members') }) },
    { key: 'transactions', included: true, text: t('billing.plans.features.transactions', { count: limit(plan, 'max_monthly_transactions') }) },
    { key: 'reports', included: included(plan, 'core_reports'), text: t('billing.plans.features.reports') },
    { key: 'imports', included: included(plan, 'imports'), text: t('billing.plans.features.imports') },
    { key: 'multiCurrency', included: included(plan, 'multi_currency'), text: t('billing.plans.features.multiCurrency') },
    { key: 'prioritySupport', included: included(plan, 'priority_support'), text: t('billing.plans.features.prioritySupport') },
  ]
}

async function checkout(planKey: LaunchPlanKey) {
  if (!currentId.value || pendingPlan.value) return
  pendingPlan.value = planKey
  errorMessage.value = ''
  try {
    const url = await createCheckoutSession(currentId.value, planKey, interval.value, t('billing.checkoutFailed'))
    window.location.assign(url)
  }
  catch (error) {
    errorMessage.value = error instanceof Error ? error.message : t('billing.checkoutFailed')
  }
  finally {
    pendingPlan.value = null
  }
}

async function reviewChange(planKey: LaunchPlanKey) {
  if (!currentId.value || reviewingPlan.value) return
  reviewingPlan.value = planKey
  errorMessage.value = ''
  try {
    const { data, error } = await supabase.rpc('plan_change_impact', {
      p_organization_id: currentId.value,
      p_target_plan_key: planKey,
      p_target_interval: interval.value,
    }).single()
    if (error) throw error
    planImpact.value = data as PlanChangeImpact
  }
  catch (error) {
    errorMessage.value = describeError(error)
  }
  finally {
    reviewingPlan.value = null
  }
}
</script>

<template>
  <div :class="compact ? 'space-y-5' : 'space-y-8'" data-testid="plan-pricing">
    <section
      v-if="trialPlanCurrent && surface === 'checkout'"
      class="rounded-card border border-primary/40 bg-primary/5 p-5 text-start"
      data-testid="trial-summary"
    >
      <template v-if="accessState === 'trialing'">
        <h2 class="text-lg font-black">{{ t('billing.trial.activeTitle') }}</h2>
        <p class="mt-2 text-sm">{{ t('billing.trial.activeBenefits') }}</p>
        <p class="mt-2 text-sm text-fg-muted">{{ t('billing.trial.endsOn', { date: formatDate(subscription?.trial_ends_at) }) }}</p>
        <p class="mt-2 text-sm text-fg-muted">{{ t('billing.trial.optionalConversion') }}</p>
      </template>
      <template v-else-if="accessState === 'read_only'">
        <h2 class="text-lg font-black">{{ t('billing.trial.expiredTitle') }}</h2>
        <p class="mt-2 text-sm">{{ t('billing.trial.expiredBody', { date: formatDate(subscription?.trial_ends_at) }) }}</p>
        <p class="mt-2 text-sm font-semibold">{{ t('billing.trial.resumeWrites') }}</p>
      </template>
    </section>

    <fieldset class="mx-auto max-w-sm">
      <legend class="ls-label text-center">{{ t('billing.billingCycle') }}</legend>
      <div class="mx-auto grid max-w-xs grid-cols-2 rounded-full border border-[var(--bs-border)] bg-surface-muted p-1 shadow-inner" dir="ltr">
        <label class="relative cursor-pointer">
          <input v-model="interval" class="absolute inset-0 z-10 h-full w-full cursor-pointer appearance-none rounded-full focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary" type="radio" name="billing-cycle" value="monthly">
          <span class="block rounded-full px-6 py-2 text-center text-sm font-semibold transition" :class="interval === 'monthly' ? 'bg-surface text-fg shadow-sm' : 'text-fg-muted'">{{ t('billing.monthly') }}</span>
        </label>
        <label class="relative cursor-pointer">
          <input v-model="interval" class="absolute inset-0 z-10 h-full w-full cursor-pointer appearance-none rounded-full focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary" type="radio" name="billing-cycle" value="yearly">
          <span class="block rounded-full px-6 py-2 text-center text-sm font-semibold transition" :class="interval === 'yearly' ? 'bg-surface text-fg shadow-sm' : 'text-fg-muted'">{{ t('billing.yearly') }}</span>
        </label>
      </div>
      <p class="mt-2 text-center text-xs text-fg-muted">{{ t('billing.plans.annualDiscount') }}</p>
    </fieldset>

    <div v-if="catalogPending" class="py-8 text-center text-sm text-fg-muted" role="status">{{ t('billing.plans.loading') }}</div>
    <div v-else-if="catalogError" class="ls-error text-center" role="alert">
      <p>{{ t('billing.plans.loadFailed') }}</p>
      <button type="button" class="mt-2 text-link" @click="refresh()">{{ t('common.retry') }}</button>
    </div>
    <div v-else class="grid items-stretch gap-4 md:grid-cols-2 xl:grid-cols-4">
      <article
        v-for="plan in plans"
        :key="plan.plan_key"
        class="ls-card relative flex min-w-0 flex-col p-5 text-start"
        :class="{ 'border-primary shadow-card': plan.plan_key === 'starter', 'opacity-75': !plan.is_purchasable }"
        :data-plan="plan.plan_key"
      >
        <span v-if="plan.plan_key === 'starter'" class="absolute end-4 top-4 rounded-full bg-brand-gold px-2.5 py-1 text-xs font-bold text-brand-navy-deep">{{ t('billing.plans.mostPopular') }}</span>
        <span v-else-if="!plan.is_purchasable" class="absolute end-4 top-4 rounded-full bg-surface-muted px-2.5 py-1 text-xs font-bold">{{ t('billing.plans.comingSoon') }}</span>
        <h3 class="pe-24 text-xl font-black">{{ t(`billing.plans.${plan.plan_key}.name`) }}</h3>
        <p class="mt-2 min-h-12 text-sm text-fg-muted">{{ t(`billing.plans.${plan.plan_key}.description`) }}</p>

        <div v-if="amount(plan) !== null" class="mt-5">
          <template v-if="interval === 'yearly'">
            <div class="flex flex-wrap items-center gap-2 text-sm text-fg-muted" dir="ltr">
              <s>{{ t('billing.plans.price', { amount: formatAmount(yearlyOriginalAmount(plan) ?? 0) }) }}</s>
              <span class="rounded-full bg-[var(--bs-status-success-bg)] px-2 py-0.5 text-xs font-bold text-[var(--bs-status-success)]">{{ t('billing.plans.discount', { percent: yearlyDiscount(plan) }) }}</span>
            </div>
            <p class="mt-1 text-3xl font-black" dir="ltr">{{ t('billing.plans.price', { amount: formatAmount(amount(plan) ?? 0) }) }}</p>
            <p class="text-xs text-fg-muted">{{ t('billing.plans.yearlyEquivalent', {
              monthlyPrice: t('billing.plans.price', { amount: formatAmount(yearlyMonthlyAmount(plan) ?? 0) }),
              yearlyPrice: t('billing.plans.price', { amount: formatAmount(amount(plan) ?? 0) }),
            }) }}</p>
          </template>
          <template v-else>
            <p class="text-3xl font-black" dir="ltr">{{ t('billing.plans.price', { amount: formatAmount(amount(plan) ?? 0) }) }}</p>
            <p class="text-xs text-fg-muted">{{ t('billing.plans.perMonth') }}</p>
          </template>
        </div>
        <p v-else class="mt-5 text-lg font-bold">{{ t('billing.plans.pricingComingSoon') }}</p>

        <ul v-if="featureRows(plan).length" class="mt-5 flex-1 space-y-2 text-sm">
          <li v-for="feature in featureRows(plan)" :key="feature.key" class="flex items-start gap-2">
            <AppIcon :name="feature.included ? 'check' : 'close'" :size="17" :class="feature.included ? 'text-[var(--bs-status-success)]' : 'text-fg-muted'" />
            <span :class="{ 'text-fg-muted': !feature.included }">{{ feature.text }} <span class="sr-only">({{ feature.included ? t('billing.plans.included') : t('billing.plans.notIncluded') }})</span></span>
          </li>
        </ul>
        <p v-else class="mt-5 flex-1 text-sm text-fg-muted">{{ t('billing.plans.scale.preview') }}</p>

        <button v-if="surface === 'checkout' && plan.is_purchasable" type="button" class="ls-btn ls-btn-primary mt-6 w-full" :disabled="Boolean(pendingPlan)" @click="checkout(plan.plan_key as LaunchPlanKey)">
          {{ pendingPlan === plan.plan_key ? t('billing.openingCheckout') : t('billing.plans.choose', { plan: t(`billing.plans.${plan.plan_key}.name`) }) }}
        </button>
        <button v-else-if="surface === 'manage' && plan.is_purchasable && launchPlanCurrent" type="button" class="ls-btn mt-6 w-full" :disabled="Boolean(reviewingPlan)" @click="reviewChange(plan.plan_key as LaunchPlanKey)">
          {{ reviewingPlan === plan.plan_key ? t('billing.planChange.reviewing') : t('billing.planChange.review', { plan: t(`billing.plans.${plan.plan_key}.name`) }) }}
        </button>
        <NuxtLink v-else-if="surface === 'public' && plan.is_purchasable" to="/signup" class="ls-btn ls-btn-primary mt-6 w-full">{{ t('landing.startTrial') }}</NuxtLink>
        <button v-else-if="!plan.is_purchasable" type="button" class="ls-btn mt-6 w-full" disabled>{{ t('billing.plans.comingSoon') }}</button>
      </article>
    </div>

    <section
      v-if="surface === 'checkout'"
      class="rounded-card border border-[var(--bs-border)] bg-surface-muted p-4 text-center text-sm leading-6 text-fg-muted"
      data-testid="checkout-policy-review"
      role="note"
    >
      <i18n-t keypath="billing.policyReview" tag="p" scope="global">
        <template #terms>
          <NuxtLink to="/terms" target="_blank" rel="noopener" class="font-semibold text-link underline underline-offset-4">{{ t('marketing.terms') }}</NuxtLink>
        </template>
        <template #refund>
          <NuxtLink to="/refund-cancellation" target="_blank" rel="noopener" class="font-semibold text-link underline underline-offset-4">{{ t('marketing.refundCancellation') }}</NuxtLink>
        </template>
        <template #privacy>
          <NuxtLink to="/privacy" target="_blank" rel="noopener" class="font-semibold text-link underline underline-offset-4">{{ t('marketing.privacy') }}</NuxtLink>
        </template>
      </i18n-t>
    </section>

    <section
      v-if="surface === 'checkout' || surface === 'public'"
      class="text-center text-xs font-semibold text-fg-muted"
      data-testid="payment-method-branding"
      role="note"
    >
      {{ t('billing.securePayments') }}
    </section>

    <section class="ls-card-flat flex flex-col gap-4 p-5 text-start sm:flex-row sm:items-center">
      <div class="flex-1">
        <div class="flex flex-wrap items-center gap-2"><h3 class="text-lg font-black">{{ t('billing.plans.enterprise.name') }}</h3><span class="rounded-full bg-surface-muted px-2.5 py-1 text-xs font-bold">{{ t('billing.plans.comingSoon') }}</span></div>
        <p class="mt-1 text-sm text-fg-muted">{{ t('billing.plans.enterprise.description') }}</p>
      </div>
      <span class="ls-btn shrink-0 opacity-70" aria-disabled="true">{{ t('billing.plans.contactUs') }}</span>
    </section>

    <section class="rounded-card border border-dashed border-[var(--bs-border-strong)] p-5 text-start">
      <h3 class="font-bold">{{ t('billing.plans.futureTitle') }}</h3>
      <p class="mt-1 text-sm text-fg-muted">{{ t('billing.plans.futureBody') }}</p>
      <ul class="mt-3 grid gap-2 text-sm sm:grid-cols-3">
        <li>{{ t('billing.plans.future.branches') }}</li>
        <li>{{ t('billing.plans.future.analytics') }}</li>
        <li>{{ t('billing.plans.future.api') }}</li>
      </ul>
    </section>

    <p v-if="surface === 'checkout'" class="text-center text-xs text-fg-muted">{{ t('billing.paymentRequired') }}</p>
    <p v-if="surface === 'manage' && compatibilityPlanCurrent" class="rounded-card border border-[var(--bs-border-strong)] p-4 text-sm text-fg-muted" role="note">{{ t('billing.planChange.legacyGrandfathered') }}</p>
    <p v-if="errorMessage" class="ls-error" role="alert">{{ errorMessage }}</p>

    <Teleport to="body">
      <div v-if="planImpact" class="fixed inset-0 z-[80] grid place-items-center ls-scrim p-4" role="dialog" aria-modal="true" :aria-labelledby="'plan-change-title'" @click.self="planImpact = null">
        <section class="ls-card max-h-[90vh] w-full max-w-3xl overflow-y-auto p-6" data-testid="plan-change-impact">
          <div class="flex items-start justify-between gap-4">
            <div>
              <h2 id="plan-change-title" class="text-xl font-black">{{ t('billing.planChange.title') }}</h2>
              <p class="mt-1 text-sm text-fg-muted">{{ t('billing.planChange.summary', {
                current: t(`billing.plans.${planImpact.current_plan_key}.name`),
                target: t(`billing.plans.${planImpact.target_plan_key}.name`),
              }) }}</p>
            </div>
            <button type="button" class="ls-btn-icon" :aria-label="t('common.close')" @click="planImpact = null"><AppIcon name="close" :size="20" /></button>
          </div>

          <div class="mt-5 rounded-card bg-surface-muted p-4 text-sm">
            <p class="font-bold">{{ t('billing.planChange.noDeletion') }}</p>
            <p class="mt-1 text-fg-muted">{{ t('billing.planChange.targetPrice', {
              price: t('billing.plans.price', { amount: formatAmount(planImpact.target_amount_minor) }),
              interval: t(`billing.${planImpact.target_interval}`),
            }) }}</p>
          </div>

          <h3 class="mt-6 font-bold">{{ t('billing.planChange.capacityTitle') }}</h3>
          <ul class="mt-3 grid gap-2 sm:grid-cols-2">
            <li v-for="quota in quotaImpacts" :key="quota.quota_key" class="rounded-card border border-[var(--bs-border)] p-3 text-sm" :data-impact-quota="quota.quota_key">
              <div class="flex items-start justify-between gap-3">
                <span class="font-semibold">{{ t(`usage.quotas.${quota.quota_key}`) }}</span>
                <span v-if="quota.will_block_new_activity" class="text-xs font-bold text-[var(--bs-status-danger)]">{{ t('billing.planChange.blocked') }}</span>
                <span v-else class="text-xs font-bold text-[var(--bs-status-success)]">{{ t('billing.planChange.available') }}</span>
              </div>
              <p class="mt-1 text-fg-muted">{{ t('billing.planChange.usageLimit', {
                used: formatQuota(quota.quota_key, quota.used_value),
                limit: formatQuota(quota.quota_key, quota.target_limit_value),
              }) }}</p>
            </li>
          </ul>

          <div v-if="gainedFeatures.length || auditHistoryIncreased" class="mt-6">
            <h3 class="font-bold">{{ t('billing.planChange.gainedTitle') }}</h3>
            <ul class="mt-2 list-disc space-y-1 ps-5 text-sm text-[var(--bs-status-success)]">
              <li v-for="feature in gainedFeatures" :key="feature.feature_key">{{ featureName(feature.feature_key) }}</li>
              <li v-if="auditHistoryIncreased">{{ t('billing.planChange.auditHistoryIncreased', { days: formatNumber(planImpact.audit_history_target_days) }) }}</li>
            </ul>
          </div>

          <div v-if="lostFeatures.length || planImpact.audit_history_reduced" class="mt-6">
            <h3 class="font-bold">{{ t('billing.planChange.lostTitle') }}</h3>
            <ul class="mt-2 list-disc space-y-1 ps-5 text-sm text-fg-muted">
              <li v-for="feature in lostFeatures" :key="feature.feature_key">{{ featureName(feature.feature_key) }}</li>
              <li v-if="planImpact.audit_history_reduced">{{ t('billing.planChange.auditHistoryReduced', { days: formatNumber(planImpact.audit_history_target_days) }) }}</li>
            </ul>
          </div>

          <div v-if="planImpact.requires_manual_handoff" class="mt-6 rounded-card border border-[var(--bs-border-strong)] p-4 text-sm" role="note">
            <p class="font-bold">{{ t('billing.planChange.handoffTitle') }}</p>
            <p class="mt-1 text-fg-muted">{{ t('billing.planChange.handoffBody') }}</p>
          </div>
          <p v-else class="mt-6 text-sm text-fg-muted">{{ t('billing.planChange.noChange') }}</p>

          <div class="mt-6 flex justify-end">
            <button type="button" class="ls-btn ls-btn-primary" @click="planImpact = null">{{ t('common.close') }}</button>
          </div>
        </section>
      </div>
    </Teleport>
  </div>
</template>

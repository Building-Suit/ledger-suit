<script setup lang="ts">
import type { Database, Json } from '~~/types/database.types'
import type { LaunchPlanKey } from '~/composables/useBilling'

const { compact = false, surface = 'checkout' } = defineProps<{
  compact?: boolean
  surface?: 'checkout' | 'public' | 'display'
}>()
const supabase = useSupabaseClient<Database>()
const { currentId } = useTenant()
const { createCheckoutSession } = useBilling()
const { t, locale } = useI18n()
const interval = ref<'monthly' | 'yearly'>('monthly')
const pendingPlan = ref<LaunchPlanKey | null>(null)
const errorMessage = ref('')

type CatalogPlan = Database['public']['Functions']['subscription_plan_catalog']['Returns'][number]
type JsonObject = Record<string, Json | undefined>

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

function amount(plan: CatalogPlan): number | null {
  const price = object(object(plan.prices)[interval.value])
  return typeof price.amount_minor === 'number' ? price.amount_minor : null
}

function formatAmount(amountMinor: number): string {
  return new Intl.NumberFormat(locale.value === 'ar' ? 'ar-EG' : 'en-US', {
    minimumFractionDigits: amountMinor % 100 === 0 ? 0 : 2,
    maximumFractionDigits: 2,
  }).format(amountMinor / 100)
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
</script>

<template>
  <div :class="compact ? 'space-y-5' : 'space-y-8'" data-testid="plan-pricing">
    <fieldset class="mx-auto max-w-sm">
      <legend class="ls-label text-center">{{ t('billing.billingCycle') }}</legend>
      <div class="grid grid-cols-2 gap-2" dir="ltr">
        <button type="button" class="ls-card-flat cursor-pointer p-3 text-center font-semibold" :aria-pressed="interval === 'monthly'" :class="{ 'border-primary': interval === 'monthly' }" @click="interval = 'monthly'">
          {{ t('billing.monthly') }}
        </button>
        <button type="button" class="ls-card-flat cursor-pointer p-3 text-center font-semibold" :aria-pressed="interval === 'yearly'" :class="{ 'border-primary': interval === 'yearly' }" @click="interval = 'yearly'">
          {{ t('billing.yearly') }}
        </button>
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
          <p class="text-3xl font-black" dir="ltr">{{ t('billing.plans.price', { amount: formatAmount(amount(plan) ?? 0) }) }}</p>
          <p class="text-xs text-fg-muted">{{ interval === 'monthly' ? t('billing.plans.perMonth') : t('billing.plans.perYear') }}</p>
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
        <NuxtLink v-else-if="surface === 'public' && plan.is_purchasable" to="/signup" class="ls-btn ls-btn-primary mt-6 w-full">{{ t('landing.startTrial') }}</NuxtLink>
        <button v-else-if="!plan.is_purchasable" type="button" class="ls-btn mt-6 w-full" disabled>{{ t('billing.plans.comingSoon') }}</button>
      </article>
    </div>

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
    <p v-if="errorMessage" class="ls-error" role="alert">{{ errorMessage }}</p>
  </div>
</template>

<script setup lang="ts">
const { t, te, locale } = useI18n()
const { accessState, subscription } = useBilling()
const { rows: usageRows } = usePlanUsage()

useHead({ title: () => `${t('billing.title')} · ${t('app.name')}` })

function displayDate(value: string | null | undefined) {
  return value ? new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium' }).format(new Date(value)) : '—'
}

const renewalDate = computed(() => accessState.value === 'trialing'
  ? subscription.value?.trial_ends_at
  : subscription.value?.current_period_end)
const checkoutEnabled = computed(() => ['trialing', 'checkout_required', 'read_only'].includes(accessState.value))
const pricingSurface = computed(() => checkoutEnabled.value
  ? 'checkout' as const
  : ['active', 'grace_period'].includes(accessState.value)
    ? 'manage' as const
    : 'display' as const)
const currentPlanKey = computed(() => usageRows.value[0]?.plan_key ?? null)
const currentPlanName = computed(() => {
  const key = currentPlanKey.value
  if (!key) return t('billing.singlePlan')
  const translation = `billing.plans.${key}.name`
  return te(translation) ? t(translation) : t('billing.singlePlan')
})

// The global entitlement middleware owns the initial load. Loading again from
// onMounted made the layout remove and remount this page on every request.
</script>

<template>
  <div class="space-y-6">
    <header>
      <h1 class="text-h1 font-extrabold">{{ t('billing.title') }}</h1>
      <p class="mt-1 text-sm text-fg-muted">{{ t('billing.subtitle') }}</p>
    </header>

    <div class="ls-card space-y-6 p-6">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p class="text-xs text-fg-muted">{{ t('billing.currentPlan') }}</p>
          <p class="text-lg font-bold">{{ currentPlanName }}</p>
          <p class="text-sm text-fg-muted">{{ t(`billing.states.${accessState}`) }}</p>
        </div>
        <StatusBadge :status="accessState" />
      </div>

      <dl class="grid gap-4 sm:grid-cols-2">
        <div><dt class="text-xs text-fg-muted">{{ t('billing.billingCycle') }}</dt><dd class="font-semibold">{{ subscription?.billing_interval ? t(`billing.${subscription.billing_interval}`) : '—' }}</dd></div>
        <div><dt class="text-xs text-fg-muted">{{ t('billing.nextDate') }}</dt><dd class="font-semibold">{{ displayDate(renewalDate) }}</dd></div>
      </dl>

      <p v-if="subscription?.provider_status" class="text-sm text-fg-muted">
        {{ t('billing.managedByPaymob') }}
      </p>
      <div id="plans"><BillingCheckout :surface="pricingSurface" compact /></div>
    </div>
    <UsageMeters />
  </div>
</template>

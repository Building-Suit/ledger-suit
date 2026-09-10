<script setup lang="ts">
const { t } = useI18n()
const { current } = useTenant()
const { load, loading } = useBilling()
const route = useRoute()
const paymentFailed = computed(() => route.query.checkout === 'complete' && route.query.success === 'false')
const processing = computed(() => route.query.checkout === 'complete' && !paymentFailed.value)

function checkAgain() {
  return load({ force: true })
}
</script>

<template>
  <section class="mx-auto max-w-xl py-8">
    <div class="ls-card space-y-6 p-6 md:p-8">
      <div>
        <p class="text-sm font-semibold text-accent">{{ t('billing.singlePlan') }}</p>
        <h1 class="mt-1 text-h1 font-bold">{{ t('billing.unlock', { organization: current?.name }) }}</h1>
        <p class="mt-2 text-sm text-fg-muted">{{ t('billing.gateDescription') }}</p>
      </div>
      <ul class="grid gap-2 text-sm">
        <li class="flex items-center gap-2"><AppIcon name="check" :size="18" class="text-[var(--bs-status-success)]" />{{ t('billing.featureAccounting') }}</li>
        <li class="flex items-center gap-2"><AppIcon name="check" :size="18" class="text-[var(--bs-status-success)]" />{{ t('billing.featureAutomation') }}</li>
        <li class="flex items-center gap-2"><AppIcon name="check" :size="18" class="text-[var(--bs-status-success)]" />{{ t('billing.featureTeam') }}</li>
      </ul>
      <div v-if="processing" class="rounded-control bg-surface-muted p-3 text-sm" role="status">
        <p class="font-semibold">{{ t('billing.confirming') }}</p>
        <button type="button" class="mt-2 text-link" :disabled="loading" @click="checkAgain">
          {{ t('billing.checkAgain') }}
        </button>
      </div>
      <div v-else-if="paymentFailed" class="ls-error" role="alert">
        {{ t('billing.paymentFailed') }}
      </div>
      <BillingCheckout />
    </div>
  </section>
</template>

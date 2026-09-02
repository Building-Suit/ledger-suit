<script setup lang="ts">
const { t } = useI18n()
const { current } = useTenant()
const { load, loading } = useBilling()
const route = useRoute()
const processing = computed(() => route.query.checkout === 'success')
</script>

<template>
  <section class="mx-auto max-w-xl py-8">
    <div class="ls-card space-y-6 p-6 md:p-8">
      <div>
        <p class="text-sm font-semibold text-accent">{{ t('billing.singlePlan') }}</p>
        <h1 class="mt-1 text-2xl font-extrabold">{{ t('billing.unlock', { organization: current?.name }) }}</h1>
        <p class="mt-2 text-sm text-fg-muted">{{ t('billing.gateDescription') }}</p>
      </div>
      <ul class="grid gap-2 text-sm">
        <li>✓ {{ t('billing.featureAccounting') }}</li>
        <li>✓ {{ t('billing.featureAutomation') }}</li>
        <li>✓ {{ t('billing.featureTeam') }}</li>
      </ul>
      <div v-if="processing" class="rounded-control bg-surface-muted p-3 text-sm" role="status">
        <p class="font-semibold">{{ t('billing.confirming') }}</p>
        <button type="button" class="mt-2 text-link" :disabled="loading" @click="load">
          {{ t('billing.checkAgain') }}
        </button>
      </div>
      <BillingCheckout />
    </div>
  </section>
</template>

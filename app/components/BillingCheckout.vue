<script setup lang="ts">
const { compact = false } = defineProps<{ compact?: boolean }>()
const supabase = useSupabaseClient()
const { currentId } = useTenant()
const { t } = useI18n()
const interval = ref<'monthly' | 'yearly'>('monthly')
const pending = ref(false)
const errorMessage = ref('')

async function checkout() {
  if (!currentId.value) return
  pending.value = true
  errorMessage.value = ''
  try {
    const { data, error } = await supabase.functions.invoke('stripe-checkout', {
      body: { organizationId: currentId.value, interval: interval.value },
    })
    if (error) throw new Error(await edgeFunctionErrorMessage(error, t('billing.checkoutFailed')))
    if (!data?.url) throw new Error(data?.error ?? t('billing.checkoutFailed'))
    window.location.assign(data.url)
  }
  catch (error) {
    errorMessage.value = error instanceof Error ? error.message : t('billing.checkoutFailed')
  }
  finally {
    pending.value = false
  }
}
</script>

<template>
  <div :class="compact ? 'space-y-3' : 'space-y-5'">
    <fieldset>
      <legend class="ls-label">{{ t('billing.billingCycle') }}</legend>
      <div class="grid grid-cols-2 gap-2" dir="ltr">
        <label class="ls-card-flat cursor-pointer p-3 text-center" :class="{ 'border-primary': interval === 'monthly' }">
          <input v-model="interval" class="sr-only" type="radio" value="monthly">
          <span class="font-semibold">{{ t('billing.monthly') }}</span>
        </label>
        <label class="ls-card-flat cursor-pointer p-3 text-center" :class="{ 'border-primary': interval === 'yearly' }">
          <input v-model="interval" class="sr-only" type="radio" value="yearly">
          <span class="font-semibold">{{ t('billing.yearly') }}</span>
        </label>
      </div>
    </fieldset>
    <p class="text-center text-xl font-bold text-fg">
      {{ interval === 'monthly' ? t('billing.monthlyPrice') : t('billing.yearlyPrice') }}
    </p>
    <p class="text-sm text-fg-muted">{{ t('billing.priceAtCheckout') }}</p>
    <button type="button" class="ls-btn ls-btn-accent w-full" :disabled="pending" @click="checkout">
      {{ pending ? t('billing.openingCheckout') : t('billing.startTrial') }}
    </button>
    <p class="text-xs text-fg-muted">{{ t('billing.paymentRequired') }}</p>
    <p v-if="errorMessage" class="ls-error" role="alert">{{ errorMessage }}</p>
  </div>
</template>

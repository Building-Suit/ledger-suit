<script setup lang="ts">
const supabase = useSupabaseClient()
const { t, locale } = useI18n()
const { currentId } = useTenant()
const { accessState, subscription, load } = useBilling()
const pending = ref(false)
const errorMessage = ref('')

useHead({ title: () => `${t('billing.title')} · ${t('app.name')}` })

function displayDate(value: string | null | undefined) {
  return value ? new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium' }).format(new Date(value)) : '—'
}

const renewalDate = computed(() => subscription.value?.trial_ends_at ?? subscription.value?.current_period_end)

async function openPortal() {
  if (!currentId.value) return
  pending.value = true
  errorMessage.value = ''
  try {
    const { data, error } = await supabase.functions.invoke('stripe-portal', {
      body: { organizationId: currentId.value },
    })
    if (error) throw error
    if (!data?.url) throw new Error(data?.error ?? t('billing.portalFailed'))
    window.location.assign(data.url)
  }
  catch (error) {
    errorMessage.value = error instanceof Error ? error.message : t('billing.portalFailed')
  }
  finally { pending.value = false }
}

onMounted(load)
</script>

<template>
  <div class="space-y-6">
    <header>
      <h1 class="text-h1 font-extrabold">{{ t('billing.title') }}</h1>
      <p class="mt-1 text-sm text-fg-muted">{{ t('billing.subtitle') }}</p>
    </header>

    <div class="ls-card max-w-2xl space-y-5 p-6">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p class="text-lg font-bold">{{ t('billing.singlePlan') }}</p>
          <p class="text-sm text-fg-muted">{{ t(`billing.states.${accessState}`) }}</p>
        </div>
        <StatusBadge :status="accessState" />
      </div>

      <dl class="grid gap-4 sm:grid-cols-2">
        <div><dt class="text-xs text-fg-muted">{{ t('billing.billingCycle') }}</dt><dd class="font-semibold">{{ subscription?.billing_interval ? t(`billing.${subscription.billing_interval}`) : '—' }}</dd></div>
        <div><dt class="text-xs text-fg-muted">{{ t('billing.nextDate') }}</dt><dd class="font-semibold">{{ displayDate(renewalDate) }}</dd></div>
      </dl>

      <button v-if="subscription?.provider_status" type="button" class="ls-btn ls-btn-primary" :disabled="pending" @click="openPortal">
        {{ t('billing.manageStripe') }}
      </button>
      <BillingCheckout v-else compact />
      <p v-if="errorMessage" class="ls-error" role="alert">{{ errorMessage }}</p>
    </div>
  </div>
</template>

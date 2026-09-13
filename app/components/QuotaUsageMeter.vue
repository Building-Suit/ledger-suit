<script setup lang="ts">
import type { QuotaKey } from '~/composables/usePlanUsage'

const props = defineProps<{ quotaKey: QuotaKey, compact?: boolean }>()
const { t, te, locale } = useI18n()
const { rowFor, nextPlanFor, refresh } = usePlanUsage()
const row = computed(() => rowFor(props.quotaKey))
const nextPlan = computed(() => nextPlanFor(props.quotaKey))
const percentage = computed(() => {
  if (!row.value || row.value.is_unlimited) return 0
  if (!row.value.limit_value) return row.value.is_at_limit ? 100 : 0
  return row.value.used_value / row.value.limit_value * 100
})
const ratio = computed(() => Math.min(100, Math.round(percentage.value)))
const state = computed(() => percentage.value >= 100 ? 'reached' : percentage.value >= 95 ? 'critical' : percentage.value >= 80 ? 'warning' : 'normal')
const meterColor = computed(() => state.value === 'reached' ? 'bg-[var(--bs-status-error)]' : state.value === 'critical' ? 'bg-[var(--bs-status-warning)]' : state.value === 'warning' ? 'bg-brand-gold' : 'bg-[var(--bs-status-success)]')

function number(value: number) {
  return new Intl.NumberFormat(locale.value === 'ar' ? 'ar-EG' : 'en-US', { maximumFractionDigits: 1 }).format(value)
}

function value(value: number | null) {
  if (value === null) return t('usage.unlimited')
  if (props.quotaKey !== 'max_storage_bytes') return number(value)
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  let size = value
  let index = 0
  while (size >= 1024 && index < units.length - 1) { size /= 1024; index++ }
  return `${number(size)} ${t(`usage.units.${units[index]}`)}`
}

function planName(key: string, fallback: string) {
  const translation = `billing.plans.${key}.name`
  return te(translation) ? t(translation) : fallback
}

function money(amountMinor: number) {
  return new Intl.NumberFormat(locale.value === 'ar' ? 'ar-EG' : 'en-US', {
    style: 'currency', currency: 'EGP', minimumFractionDigits: 0, maximumFractionDigits: 2,
  }).format(amountMinor / 100)
}

onMounted(() => void refresh())
</script>

<template>
  <article v-if="row" class="rounded-card border border-[var(--bs-border)] bg-surface" :class="compact ? 'p-3' : 'p-4'" :data-quota="quotaKey">
    <div class="flex items-start justify-between gap-3">
      <div>
        <h3 class="text-sm font-bold">{{ t(`usage.quotas.${quotaKey}`) }}</h3>
        <p class="text-xs text-fg-muted">{{ t('usage.currentPlan', { plan: planName(row.plan_key, row.plan_key) }) }}</p>
      </div>
      <span v-if="!row.is_unlimited" class="text-xs font-bold" :class="state === 'reached' ? 'text-[var(--bs-status-error)]' : state === 'normal' ? 'text-fg-muted' : 'text-[var(--bs-status-warning)]'">{{ t(`usage.states.${state}`) }}</span>
    </div>
    <p class="mt-2 font-bold" dir="ltr">{{ row.is_unlimited ? t('usage.unlimited') : t('usage.value', { used: value(row.used_value), limit: value(row.limit_value) }) }}</p>
    <div v-if="!row.is_unlimited" class="mt-2 h-2 overflow-hidden rounded-full bg-surface-muted" role="progressbar" :aria-label="t(`usage.quotas.${quotaKey}`)" aria-valuemin="0" aria-valuemax="100" :aria-valuenow="ratio">
      <div class="h-full rounded-full transition-all" :class="meterColor" :style="{ width: `${ratio}%` }" />
    </div>
    <div v-if="nextPlan" class="mt-3 text-xs text-fg-muted">
      <p>{{ t('usage.nextAllowance', { plan: planName(nextPlan.key, nextPlan.name), allowance: value(nextPlan.limit) }) }}</p>
      <p v-if="nextPlan.monthlyPriceMinor !== null">{{ t('usage.nextPrice', { price: money(nextPlan.monthlyPriceMinor) }) }}</p>
      <NuxtLink to="/billing#plans" class="mt-1 inline-block font-semibold text-link">{{ t('usage.viewPlans') }}</NuxtLink>
    </div>
  </article>
</template>

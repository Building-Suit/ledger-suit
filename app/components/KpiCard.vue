<script setup lang="ts">
const props = withDefaults(defineProps<{
  title: string
  amountMinor: number | null | undefined
  previousMinor?: number | null
  /** Which direction is good news. Expenses going up is not an improvement. */
  goodDirection?: 'up' | 'down' | 'neutral'
  hint?: string
}>(), {
  previousMinor: null,
  goodDirection: 'up',
  hint: undefined,
})

const { t, locale } = useI18n()

const current = computed(() => Number(props.amountMinor ?? 0))

// A percentage against a zero base is not a percentage — show nothing rather
// than an infinity or a misleading 100%.
const change = computed(() => {
  const previous = props.previousMinor
  if (previous === null || previous === undefined || previous === 0) return null
  return ((current.value - previous) / Math.abs(previous)) * 100
})

const tone = computed(() => {
  if (change.value === null || props.goodDirection === 'neutral') return 'text-fg-muted'
  if (Math.abs(change.value) < 0.05) return 'text-fg-muted'
  const improving = props.goodDirection === 'up' ? change.value > 0 : change.value < 0
  return improving ? 'text-[var(--bs-status-success)]' : 'text-[var(--bs-status-error)]'
})

const changeLabel = computed(() => {
  if (change.value === null) return null
  return t('dashboard.changeVsLastMonth', {
    change: formatPercent(change.value, locale.value),
  })
})
</script>

<template>
  <article class="ls-card p-5">
    <p class="text-sm text-fg-muted">{{ title }}</p>
    <p class="mt-2 text-2xl font-extrabold">
      <MoneyText :amount-minor="current" />
    </p>
    <p v-if="changeLabel" class="mt-1 text-xs font-medium" :class="tone">{{ changeLabel }}</p>
    <p v-else-if="hint" class="mt-1 text-xs text-fg-muted">{{ hint }}</p>
  </article>
</template>

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

const current = computed(() => Number(props.amountMinor ?? 0))

// A percentage against a zero base is not a percentage — show nothing rather
// than an infinity or a misleading 100%.
const change = computed(() => {
  const previous = props.previousMinor
  if (previous === null || previous === undefined || previous === 0) return null
  return ((current.value - previous) / Math.abs(previous)) * 100
})

const tone = computed(() => {
  if (change.value === null || props.goodDirection === 'neutral') {
    return 'text-neutral-500'
  }
  const improving = props.goodDirection === 'up' ? change.value > 0 : change.value < 0
  if (Math.abs(change.value) < 0.05) return 'text-neutral-500'
  return improving
    ? 'text-emerald-700 dark:text-emerald-400'
    : 'text-red-700 dark:text-red-400'
})

const changeLabel = computed(() => {
  if (change.value === null) return null
  const sign = change.value > 0 ? '+' : ''
  return `${sign}${change.value.toFixed(1)}% vs last month`
})
</script>

<template>
  <article class="ls-card p-4">
    <p class="text-sm text-neutral-500">{{ title }}</p>
    <p class="mt-2 text-2xl font-semibold">
      <MoneyText :amount-minor="current" />
    </p>
    <p v-if="changeLabel" class="mt-1 text-xs" :class="tone">{{ changeLabel }}</p>
    <p v-else-if="hint" class="mt-1 text-xs text-neutral-500">{{ hint }}</p>
  </article>
</template>

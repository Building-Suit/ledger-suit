<script setup lang="ts">
/**
 * Renders an integer minor-unit amount. The division to a decimal happens here
 * and nowhere else — no component performs arithmetic on money.
 */
const props = withDefaults(defineProps<{
  amountMinor: number | string | null | undefined
  /** Falls back to the organization base currency when absent. */
  currency?: string | null
  /** Colour positive green and negative red. Off by default: most figures are
   *  neutral, and colouring everything makes nothing stand out. */
  signed?: boolean
  /** Show a + in front of positive values. Only meaningful with `signed`. */
  explicitSign?: boolean
}>(), {
  currency: undefined,
  signed: false,
  explicitSign: false,
})

const { baseCurrency } = useTenant()

const value = computed(() => Number(props.amountMinor ?? 0))
const code = computed(() => props.currency ?? baseCurrency.value)

const formatted = computed(() => {
  const text = formatMoney(value.value, code.value)
  return props.explicitSign && value.value > 0 ? `+${text}` : text
})

const tone = computed(() => {
  if (!props.signed || value.value === 0) return ''
  return value.value > 0
    ? 'text-emerald-700 dark:text-emerald-400'
    : 'text-red-700 dark:text-red-400'
})
</script>

<template>
  <span class="tabular-nums" :class="tone">{{ formatted }}</span>
</template>

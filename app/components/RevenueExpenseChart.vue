<script setup lang="ts">
export interface SeriesPoint {
  month: string
  revenue_minor: number
  expense_minor: number
  net_minor: number
}

const props = defineProps<{ series: SeriesPoint[] }>()

const { baseCurrency } = useTenant()

// Hand-drawn SVG rather than a charting library: it keeps the bundle small and
// the markup accessible, and a paired bar chart needs nothing more.
const CHART_HEIGHT = 160

const max = computed(() =>
  Math.max(
    1,
    ...props.series.flatMap(p => [Number(p.revenue_minor), Number(p.expense_minor)]),
  ),
)

const bars = computed(() =>
  props.series.map((point) => {
    const revenue = Number(point.revenue_minor)
    const expense = Number(point.expense_minor)
    return {
      month: point.month,
      label: new Date(point.month).toLocaleDateString('en', { month: 'short' }),
      revenue,
      expense,
      net: Number(point.net_minor),
      revenueHeight: Math.round((revenue / max.value) * CHART_HEIGHT),
      expenseHeight: Math.round((expense / max.value) * CHART_HEIGHT),
    }
  }),
)
</script>

<template>
  <div>
    <div class="mb-3 flex items-center gap-4 text-xs text-neutral-500">
      <span class="flex items-center gap-1.5">
        <span class="inline-block size-2.5 rounded-sm bg-emerald-500" aria-hidden="true" />
        Revenue
      </span>
      <span class="flex items-center gap-1.5">
        <span class="inline-block size-2.5 rounded-sm bg-neutral-400" aria-hidden="true" />
        Expenses
      </span>
    </div>

    <div class="overflow-x-auto">
      <div class="flex min-w-full items-end gap-4" :style="{ height: `${CHART_HEIGHT + 8}px` }">
        <div
          v-for="bar in bars"
          :key="bar.month"
          class="flex min-w-12 flex-1 flex-col justify-end"
        >
          <div class="flex items-end justify-center gap-1" :style="{ height: `${CHART_HEIGHT}px` }">
            <div
              class="w-4 rounded-t bg-emerald-500"
              :style="{ height: `${bar.revenueHeight}px` }"
              :title="`Revenue ${formatMoney(bar.revenue, baseCurrency)}`"
            />
            <div
              class="w-4 rounded-t bg-neutral-400"
              :style="{ height: `${bar.expenseHeight}px` }"
              :title="`Expenses ${formatMoney(bar.expense, baseCurrency)}`"
            />
          </div>
        </div>
      </div>
    </div>

    <div class="mt-2 flex gap-4">
      <div v-for="bar in bars" :key="`${bar.month}-label`" class="min-w-12 flex-1 text-center text-xs text-neutral-500">
        {{ bar.label }}
      </div>
    </div>

    <!-- The same numbers, readable by a screen reader and by anyone who prefers
         a table to a chart. -->
    <details class="mt-4">
      <summary class="cursor-pointer text-xs text-neutral-500">Show as a table</summary>
      <table class="ls-table mt-2">
        <thead>
          <tr>
            <th scope="col">Month</th>
            <th scope="col" class="text-right">Revenue</th>
            <th scope="col" class="text-right">Expenses</th>
            <th scope="col" class="text-right">Net</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="bar in bars" :key="`${bar.month}-row`">
            <td>{{ bar.label }}</td>
            <td class="ls-num"><MoneyText :amount-minor="bar.revenue" /></td>
            <td class="ls-num"><MoneyText :amount-minor="bar.expense" /></td>
            <td class="ls-num"><MoneyText :amount-minor="bar.net" signed /></td>
          </tr>
        </tbody>
      </table>
    </details>
  </div>
</template>

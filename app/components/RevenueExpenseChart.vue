<script setup lang="ts">
export interface SeriesPoint {
  month: string
  revenue_minor: number
  expense_minor: number
  net_minor: number
}

const props = defineProps<{ series: SeriesPoint[] }>()

const { baseCurrency } = useTenant()
const { t, locale } = useI18n()

// Hand-drawn rather than a charting library: it keeps the bundle small and the
// markup accessible, and a paired bar chart needs nothing more.
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
      label: formatMonth(point.month, locale.value),
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
    <div class="mb-4 flex items-center gap-4 text-xs text-fg-muted">
      <span class="flex items-center gap-1.5">
        <span class="inline-block size-2.5 rounded-sm bg-[var(--bs-success)]" aria-hidden="true" />
        {{ t('dashboard.revenue') }}
      </span>
      <span class="flex items-center gap-1.5">
        <span class="inline-block size-2.5 rounded-sm bg-[var(--bs-sky-steel)]" aria-hidden="true" />
        {{ t('dashboard.expenses') }}
      </span>
    </div>

    <!-- Bars and axis labels share one scroll container. Two separate scrollers
         would let the labels drift out of alignment with the bars they name,
         and a label row without a scroller overflows the page on narrow
         screens — which is exactly what it did. -->
    <div class="overflow-x-auto">
      <div class="min-w-max">
        <div class="flex items-end gap-4" :style="{ height: `${CHART_HEIGHT + 8}px` }">
          <div
            v-for="bar in bars"
            :key="bar.month"
            class="flex min-w-12 flex-1 flex-col justify-end"
          >
            <div class="flex items-end justify-center gap-1" :style="{ height: `${CHART_HEIGHT}px` }">
              <div
                class="w-4 rounded-t-chip bg-[var(--bs-success)]"
                :style="{ height: `${bar.revenueHeight}px` }"
                :title="`${t('dashboard.revenue')} ${formatMoney(bar.revenue, baseCurrency, locale)}`"
              />
              <div
                class="w-4 rounded-t-chip bg-[var(--bs-sky-steel)]"
                :style="{ height: `${bar.expenseHeight}px` }"
                :title="`${t('dashboard.expenses')} ${formatMoney(bar.expense, baseCurrency, locale)}`"
              />
            </div>
          </div>
        </div>

        <div class="mt-2 flex gap-4">
          <div
            v-for="bar in bars"
            :key="`${bar.month}-label`"
            class="min-w-12 flex-1 text-center text-xs text-fg-muted"
          >
            {{ bar.label }}
          </div>
        </div>
      </div>
    </div>

    <!-- The same numbers, readable by a screen reader and by anyone who prefers
         a table to a chart. -->
    <details class="mt-4">
      <summary class="cursor-pointer text-xs text-fg-muted">{{ t('common.showAsTable') }}</summary>
      <!-- Its own scroll container: wide content must never make the page
           scroll horizontally, and Arabic headers are wider than the English. -->
      <div class="mt-2 overflow-x-auto">
        <table class="ls-table">
        <thead>
          <tr>
            <th scope="col">{{ t('dashboard.month') }}</th>
            <th scope="col" class="text-end">{{ t('dashboard.revenue') }}</th>
            <th scope="col" class="text-end">{{ t('dashboard.expenses') }}</th>
            <th scope="col" class="text-end">{{ t('dashboard.net') }}</th>
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
      </div>
    </details>
  </div>
</template>

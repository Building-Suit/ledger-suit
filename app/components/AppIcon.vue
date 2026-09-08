<script setup lang="ts">
import { HugeiconsIcon } from '@hugeicons/vue'
import {
  Add01Icon,
  AnalyticsUpIcon,
  ArrowDown01Icon,
  ArrowReloadHorizontalIcon,
  ArrowRight01Icon,
  Cancel01Icon,
  Cash02Icon,
  ChartBreakoutSquareIcon,
  CheckmarkBadge01Icon,
  CheckmarkCircle02Icon,
  DashboardSquare01Icon,
  Delete02Icon,
  FileChartLineIcon,
  Invoice01Icon,
  Mail02Icon,
  Menu01Icon,
  Notification02Icon,
  RepeatIcon,
  Settings01Icon,
  TransactionIcon,
  UserGroupIcon,
  Wallet04Icon,
} from '@hugeicons/core-free-icons'

const icons = {
  add: Add01Icon,
  analytics: AnalyticsUpIcon,
  arrowDown: ArrowDown01Icon,
  arrowRight: ArrowRight01Icon,
  automation: ArrowReloadHorizontalIcon,
  cash: Cash02Icon,
  check: CheckmarkCircle02Icon,
  checkBadge: CheckmarkBadge01Icon,
  close: Cancel01Icon,
  dashboard: DashboardSquare01Icon,
  delete: Delete02Icon,
  invoice: Invoice01Icon,
  ledger: TransactionIcon,
  mail: Mail02Icon,
  menu: Menu01Icon,
  notification: Notification02Icon,
  reports: FileChartLineIcon,
  settings: Settings01Icon,
  team: UserGroupIcon,
  transactions: TransactionIcon,
  wallet: Wallet04Icon,
  chart: ChartBreakoutSquareIcon,
  repeat: RepeatIcon,
} as const

const props = withDefaults(defineProps<{
  name: string
  size?: number
  directional?: boolean
}>(), { size: 20, directional: false })

const icon = computed(() => icons[props.name as keyof typeof icons] ?? DashboardSquare01Icon)
</script>

<template>
  <HugeiconsIcon
    :icon="icon"
    :size="props.size"
    color="currentColor"
    :stroke-width="2"
    :absolute-stroke-width="true"
    aria-hidden="true"
    :class="{ 'rtl:-scale-x-100': props.directional }"
  />
</template>

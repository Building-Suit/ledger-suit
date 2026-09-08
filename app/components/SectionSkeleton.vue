<script setup lang="ts">
const props = withDefaults(defineProps<{
  variant?: 'cards' | 'chart' | 'table'
  rows?: number
}>(), {
  variant: 'table',
  rows: 5,
})

const { t } = useI18n()
const rowIndexes = computed(() => Array.from({ length: props.rows }, (_, index) => index))
</script>

<template>
  <div data-testid="section-skeleton" aria-busy="true" aria-live="polite">
    <span class="sr-only">{{ t('app.loading') }}</span>

    <div v-if="variant === 'cards'" class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <div v-for="index in 8" :key="index" class="ls-card space-y-4 p-6">
        <div class="ls-skeleton h-3 w-2/3 rounded-full" />
        <div class="ls-skeleton h-7 w-1/2 rounded-control" />
        <div class="ls-skeleton h-3 w-1/3 rounded-full" />
      </div>
    </div>

    <div v-else-if="variant === 'chart'" class="ls-card space-y-6 p-6">
      <div class="flex items-center justify-between gap-4">
        <div class="ls-skeleton h-4 w-40 rounded-full" />
        <div class="ls-skeleton h-8 w-32 rounded-control" />
      </div>
      <div class="ls-skeleton h-64 w-full rounded-control" />
    </div>

    <div v-else class="ls-card overflow-hidden">
      <div class="flex items-center justify-between border-b border-[var(--bs-border)] px-6 py-4">
        <div class="ls-skeleton h-4 w-40 rounded-full" />
        <div class="ls-skeleton h-4 w-20 rounded-full" />
      </div>
      <div v-for="index in rowIndexes" :key="index" class="grid grid-cols-4 gap-6 border-b border-[var(--bs-border)] px-6 py-4 last:border-b-0">
        <div class="ls-skeleton h-3 rounded-full" />
        <div class="ls-skeleton col-span-2 h-3 rounded-full" />
        <div class="ls-skeleton h-3 rounded-full" />
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
// Status is always spelled out in words. Colour is a secondary cue only, so the
// table stays readable without colour vision.
// Nullable because the summary views expose columns as nullable; an unknown
// status renders as "unknown" rather than silently as a draft.
const props = defineProps<{ status: string | null | undefined }>()

const styles: Record<string, string> = {
  posted: 'bg-emerald-50 text-emerald-700 ring-emerald-600/20 dark:bg-emerald-500/10 dark:text-emerald-400',
  draft: 'bg-neutral-100 text-neutral-600 ring-neutral-500/20 dark:bg-neutral-800 dark:text-neutral-300',
  scheduled: 'bg-blue-50 text-blue-700 ring-blue-600/20 dark:bg-blue-500/10 dark:text-blue-400',
  pending: 'bg-amber-50 text-amber-700 ring-amber-600/20 dark:bg-amber-500/10 dark:text-amber-400',
  pending_approval: 'bg-amber-50 text-amber-700 ring-amber-600/20 dark:bg-amber-500/10 dark:text-amber-400',
  reversed: 'bg-purple-50 text-purple-700 ring-purple-600/20 dark:bg-purple-500/10 dark:text-purple-400',
  voided: 'bg-neutral-100 text-neutral-500 ring-neutral-500/20 dark:bg-neutral-800 dark:text-neutral-400',
  failed: 'bg-red-50 text-red-700 ring-red-600/20 dark:bg-red-500/10 dark:text-red-400',
}

const label = computed(() => (props.status ?? 'unknown').replace(/_/g, ' '))
const klass = computed(() => styles[props.status ?? ''] ?? styles.draft)
</script>

<template>
  <span class="ls-badge capitalize" :class="klass">{{ label }}</span>
</template>

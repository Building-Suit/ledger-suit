<script setup lang="ts">
/**
 * Status is always spelled out in words; colour is a secondary cue only, so the
 * table stays readable without colour vision.
 *
 * Gold is deliberately absent: per the brand guidelines gold is not a status
 * colour, it marks the single focal point of a screen.
 */
const props = defineProps<{ status: string | null | undefined }>()

const { t, te } = useI18n()

const TONES: Record<string, string> = {
  posted: 'bg-[var(--bs-success-bg)] text-[var(--bs-success)]',
  scheduled: 'bg-[var(--bs-info-bg)] text-[var(--bs-info)]',
  pending: 'bg-[var(--bs-warning-bg)] text-[var(--bs-warning)]',
  pending_approval: 'bg-[var(--bs-warning-bg)] text-[var(--bs-warning)]',
  reversed: 'bg-[var(--bs-info-bg)] text-[var(--bs-info)]',
  failed: 'bg-[var(--bs-error-bg)] text-[var(--bs-error)]',
  draft: 'bg-[var(--bs-surface-muted)] text-[var(--bs-text-muted)]',
  voided: 'bg-[var(--bs-surface-muted)] text-[var(--bs-text-muted)]',
}

const key = computed(() => props.status ?? 'unknown')
const label = computed(() =>
  te(`status.${key.value}`) ? t(`status.${key.value}`) : key.value.replace(/_/g, ' '),
)
const klass = computed(() => TONES[key.value] ?? TONES.draft)
</script>

<template>
  <span class="ls-badge" :class="klass">{{ label }}</span>
</template>

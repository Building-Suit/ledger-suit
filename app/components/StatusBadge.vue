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
  posted: 'bg-[var(--bs-status-success-bg)] text-[var(--bs-status-success)]',
  paid: 'bg-[var(--bs-status-success-bg)] text-[var(--bs-status-success)]',
  active: 'bg-[var(--bs-status-success-bg)] text-[var(--bs-status-success)]',
  trialing: 'bg-[var(--bs-status-info-bg)] text-[var(--bs-status-info)]',
  grace_period: 'bg-[var(--bs-status-warning-bg)] text-[var(--bs-status-warning)]',
  checkout_required: 'bg-[var(--bs-status-warning-bg)] text-[var(--bs-status-warning)]',
  read_only: 'bg-[var(--bs-status-error-bg)] text-[var(--bs-status-error)]',
  scheduled: 'bg-[var(--bs-status-info-bg)] text-[var(--bs-status-info)]',
  pending: 'bg-[var(--bs-status-warning-bg)] text-[var(--bs-status-warning)]',
  pending_approval: 'bg-[var(--bs-status-warning-bg)] text-[var(--bs-status-warning)]',
  due: 'bg-[var(--bs-status-warning-bg)] text-[var(--bs-status-warning)]',
  due_soon: 'bg-[var(--bs-status-warning-bg)] text-[var(--bs-status-warning)]',
  partially_paid: 'bg-[var(--bs-status-warning-bg)] text-[var(--bs-status-warning)]',
  reversed: 'bg-[var(--bs-status-info-bg)] text-[var(--bs-status-info)]',
  failed: 'bg-[var(--bs-status-error-bg)] text-[var(--bs-status-error)]',
  overdue: 'bg-[var(--bs-status-error-bg)] text-[var(--bs-status-error)]',
  draft: 'bg-[var(--bs-surface-muted)] text-[var(--bs-text-muted)]',
  voided: 'bg-[var(--bs-surface-muted)] text-[var(--bs-text-muted)]',
  cancelled: 'bg-[var(--bs-surface-muted)] text-[var(--bs-text-muted)]',
  paused: 'bg-[var(--bs-surface-muted)] text-[var(--bs-text-muted)]',
  skipped: 'bg-[var(--bs-surface-muted)] text-[var(--bs-text-muted)]',
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

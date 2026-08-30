<script setup lang="ts">
// Calm and instructive, never apologetic. Anatomy per the brand guidelines:
// short headline, one line of guidance, one primary action — and gold only on
// that single action.
defineProps<{
  title: string
  description?: string
  actionLabel?: string
}>()

defineEmits<{ action: [] }>()
</script>

<template>
  <div class="flex flex-col items-center justify-center rounded-card border border-dashed border-[var(--bs-border)] px-6 py-14 text-center">
    <p class="text-base font-semibold">{{ title }}</p>
    <p v-if="description" class="mt-2 max-w-sm text-sm text-fg-muted">
      {{ description }}
    </p>
    <button
      v-if="actionLabel"
      type="button"
      class="ls-btn ls-btn-accent mt-6"
      @click="$emit('action')"
    >
      {{ actionLabel }}
    </button>
  </div>
</template>

<script setup lang="ts">
const { toasts, dismiss } = useToasts()
const { t } = useI18n()

const tones: Record<string, string> = {
  success: 'border-[var(--bs-status-success)]',
  error: 'border-[var(--bs-status-error)]',
  info: 'border-[var(--bs-sky-steel)]',
}
</script>

<template>
  <div
    class="pointer-events-none fixed inset-x-0 bottom-0 z-50 flex flex-col items-center gap-2 p-4 sm:items-end"
    role="status"
    aria-live="polite"
  >
    <div
      v-for="toast in toasts"
      :key="toast.id"
      class="pointer-events-auto w-full max-w-sm rounded-control border bg-[var(--bs-deep-structure-navy)] px-4 py-3 text-[var(--bs-pearl-white)] shadow-overlay"
      :class="tones[toast.tone]"
    >
      <div class="flex items-start gap-3">
        <div class="min-w-0 flex-1">
          <p class="text-sm font-semibold">{{ toast.title }}</p>
          <p v-if="toast.description" class="mt-0.5 text-sm opacity-80">
            {{ toast.description }}
          </p>
        </div>
        <button
          type="button"
          class="shrink-0 text-sm opacity-60 hover:opacity-100"
          :aria-label="t('common.dismiss')"
          @click="dismiss(toast.id)"
        >
          <AppIcon name="close" :size="18" />
        </button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
const { toasts, dismiss } = useToasts()

const tones: Record<string, string> = {
  success: 'border-emerald-300 bg-emerald-50 text-emerald-900 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-200',
  error: 'border-red-300 bg-red-50 text-red-900 dark:border-red-500/30 dark:bg-red-500/10 dark:text-red-200',
  info: 'border-neutral-300 bg-white text-neutral-900 dark:border-neutral-700 dark:bg-neutral-900 dark:text-neutral-100',
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
      class="pointer-events-auto w-full max-w-sm rounded-lg border px-4 py-3 shadow-lg"
      :class="tones[toast.tone]"
    >
      <div class="flex items-start gap-3">
        <div class="min-w-0 flex-1">
          <p class="text-sm font-medium">{{ toast.title }}</p>
          <p v-if="toast.description" class="mt-0.5 text-sm opacity-80">
            {{ toast.description }}
          </p>
        </div>
        <button
          type="button"
          class="shrink-0 text-sm opacity-60 hover:opacity-100"
          aria-label="Dismiss"
          @click="dismiss(toast.id)"
        >
          ✕
        </button>
      </div>
    </div>
  </div>
</template>

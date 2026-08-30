<script setup lang="ts">
// Every primary page uses this. An empty state always names one obvious next
// action rather than leaving the user staring at nothing.
defineProps<{
  title: string
  description?: string
  actionLabel?: string
}>()

defineEmits<{ action: [] }>()
</script>

<template>
  <div class="flex flex-col items-center justify-center rounded-xl border border-dashed border-neutral-300 px-6 py-14 text-center dark:border-neutral-700">
    <p class="text-base font-medium">{{ title }}</p>
    <p v-if="description" class="mt-1 max-w-sm text-sm text-neutral-500">
      {{ description }}
    </p>
    <button
      v-if="actionLabel"
      type="button"
      class="ls-btn ls-btn-primary mt-5"
      @click="$emit('action')"
    >
      {{ actionLabel }}
    </button>
  </div>
</template>

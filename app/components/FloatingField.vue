<script setup lang="ts">
defineProps<{
  /** Visible field name, kept in the control after it receives a value. */
  label: string
}>()
</script>

<template>
  <label class="ls-floating-field">
    <slot />
    <span class="ls-floating-field__label">{{ label }}</span>
  </label>
</template>

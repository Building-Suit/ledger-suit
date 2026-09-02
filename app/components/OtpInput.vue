<script setup lang="ts">
const props = defineProps<{
  modelValue: string
  label: string
  disabled?: boolean
}>()

const emit = defineEmits<{ 'update:modelValue': [value: string] }>()
const inputs = ref<HTMLInputElement[]>([])
const digits = computed(() => Array.from({ length: 6 }, (_, index) => props.modelValue[index] ?? ''))

function updateDigit(index: number, event: Event) {
  const input = event.target as HTMLInputElement
  const value = input.value
  const next = [...digits.value]
  next[index] = value.replace(/\D/g, '').slice(-1)
  input.value = next[index]
  emit('update:modelValue', next.join(''))
  if (next[index] && index < 5) inputs.value[index + 1]?.focus()
}

function onKeydown(index: number, event: KeyboardEvent) {
  if (event.key === 'Backspace' && !digits.value[index] && index > 0) {
    inputs.value[index - 1]?.focus()
  }
  else if (event.key === 'ArrowLeft' && index > 0) {
    inputs.value[index - 1]?.focus()
  }
  else if (event.key === 'ArrowRight' && index < 5) {
    inputs.value[index + 1]?.focus()
  }
}

function onPaste(event: ClipboardEvent) {
  const value = event.clipboardData?.getData('text').replace(/\D/g, '').slice(0, 6) ?? ''
  if (!value) return
  event.preventDefault()
  emit('update:modelValue', value)
  inputs.value[Math.min(value.length, 6) - 1]?.focus()
}

onMounted(() => nextTick(() => inputs.value[0]?.focus()))
</script>

<template>
  <fieldset :aria-label="label" class="grid grid-cols-6 gap-2" dir="ltr">
    <legend class="sr-only">{{ label }}</legend>
    <input
      v-for="(_, index) in 6"
      :key="index"
      :ref="element => { if (element) inputs[index] = element as HTMLInputElement }"
      :value="digits[index]"
      type="text"
      inputmode="numeric"
      pattern="[0-9]*"
      maxlength="1"
      :autocomplete="index === 0 ? 'one-time-code' : 'off'"
      :aria-label="`${label} ${index + 1}`"
      :disabled="disabled"
      class="h-14 min-w-0 rounded-control border border-[var(--bs-border)] bg-surface text-center text-xl font-black tabular-nums outline-none transition-colors focus:border-[var(--bs-border-strong)] focus:ring-2 focus:ring-[var(--bs-focus-ring)] sm:h-16 sm:text-2xl"
      @input="updateDigit(index, $event)"
      @keydown="onKeydown(index, $event)"
      @paste="onPaste"
    >
  </fieldset>
</template>

<script setup lang="ts">
const { can } = useTenant()
const { start } = useAddTransaction()

const open = ref(false)
const root = ref<HTMLElement | null>(null)

useClickOutside(root, () => (open.value = false))

// Only offer what the caller is actually allowed to do. The database refuses it
// regardless; hiding it just avoids inviting a failure.
const flows = computed(() => ADD_FLOWS.filter(f => can(FLOW_CAPABILITY[f.key])))

function choose(flow: AddFlow) {
  open.value = false
  start(flow)
}
</script>

<template>
  <div v-if="flows.length" ref="root" class="relative">
    <button
      type="button"
      class="ls-btn ls-btn-primary"
      :aria-expanded="open"
      aria-haspopup="menu"
      @click="open = !open"
    >
      <span aria-hidden="true">+</span>
      <span>Add</span>
    </button>

    <div
      v-if="open"
      class="ls-card absolute right-0 z-30 mt-1 w-64 p-1 shadow-lg"
      role="menu"
    >
      <button
        v-for="flow in flows"
        :key="flow.key"
        type="button"
        role="menuitem"
        class="w-full rounded-md px-3 py-2 text-left hover:bg-neutral-100 dark:hover:bg-neutral-800"
        @click="choose(flow.key)"
      >
        <span class="block text-sm font-medium">{{ flow.label }}</span>
        <span class="block text-xs text-neutral-500">{{ flow.hint }}</span>
      </button>
    </div>
  </div>
</template>

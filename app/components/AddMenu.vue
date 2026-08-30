<script setup lang="ts">
const { can } = useTenant()
const { start } = useAddTransaction()
const { t } = useI18n()

const open = ref(false)
const root = ref<HTMLElement | null>(null)

useClickOutside(root, () => (open.value = false))

// Only offer what the caller is actually allowed to do. The database refuses it
// regardless; hiding it just avoids inviting a failure.
const flows = computed(() => ADD_FLOWS.filter(flow => can(FLOW_CAPABILITY[flow])))

function choose(flow: AddFlow) {
  open.value = false
  start(flow)
}
</script>

<template>
  <!-- The one gold action on the screen. -->
  <div v-if="flows.length" ref="root" class="relative">
    <button
      type="button"
      class="ls-btn ls-btn-accent"
      :aria-expanded="open"
      aria-haspopup="menu"
      @click="open = !open"
    >
      <span aria-hidden="true">+</span>
      <span>{{ t('add.title') }}</span>
    </button>

    <div
      v-if="open"
      class="ls-card absolute end-0 z-30 mt-1 w-64 p-1 shadow-overlay"
      role="menu"
    >
      <button
        v-for="flow in flows"
        :key="flow"
        type="button"
        role="menuitem"
        class="w-full rounded-chip px-3 py-2 text-start hover:bg-surface-muted"
        @click="choose(flow)"
      >
        <span class="block text-sm font-semibold">{{ t(`add.flows.${flow}`) }}</span>
        <span class="block text-xs text-fg-muted">{{ t(`add.hints.${flow}`) }}</span>
      </button>
    </div>
  </div>
</template>

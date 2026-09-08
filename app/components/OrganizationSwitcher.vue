<script setup lang="ts">
const { organizations, current, setOrganization } = useTenant()
const { t } = useI18n()

const open = ref(false)
const root = ref<HTMLElement | null>(null)

useClickOutside(root, () => (open.value = false))

async function choose(id: string) {
  open.value = false
  await setOrganization(id)
}
</script>

<template>
  <div ref="root" class="relative">
    <button
      type="button"
      class="ls-btn w-full justify-between"
      :aria-expanded="open"
      aria-haspopup="listbox"
      :aria-label="t('org.switcher')"
      @click="open = !open"
    >
      <span class="flex flex-col min-w-0 text-start">
        <span class="truncate">{{ current?.name ?? t('org.none') }}</span>
        <span v-if="current?.legal_name" class="truncate text-[10px] text-fg-muted">{{ current.legal_name }}</span>
      </span>
      <AppIcon name="arrowDown" class="text-fg-muted" />
    </button>

    <ul
      v-if="open"
      class="ls-card absolute z-30 mt-1 w-full overflow-hidden p-1 shadow-overlay"
      role="listbox"
    >
      <li v-for="org in organizations" :key="org.id">
        <button
          type="button"
          role="option"
          :aria-selected="org.id === current?.id"
          class="flex w-full items-center justify-between gap-2 rounded-chip px-2 py-2 text-start text-sm hover:bg-surface-muted"
          @click="choose(org.id)"
        >
          <span class="min-w-0">
            <span class="block truncate">{{ org.name }}</span>
            <span v-if="org.legal_name" class="block truncate text-[10px] text-fg-muted">{{ org.legal_name }}</span>
            <span class="block text-xs text-fg-muted">
              {{ t(`org.roles.${org.role}`) }} · {{ org.base_currency }}
            </span>
          </span>
          <AppIcon v-if="org.id === current?.id" name="check" class="text-[var(--bs-status-success)]" />
        </button>
      </li>
    </ul>
  </div>
</template>

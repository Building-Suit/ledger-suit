<script setup lang="ts">
const { organizations, current, setOrganization } = useTenant()

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
      @click="open = !open"
    >
      <span class="min-w-0 truncate text-left">
        {{ current?.name ?? 'No organization' }}
      </span>
      <span aria-hidden="true" class="text-neutral-400">▾</span>
    </button>

    <ul
      v-if="open"
      class="ls-card absolute z-30 mt-1 w-full overflow-hidden p-1 shadow-lg"
      role="listbox"
    >
      <li v-for="org in organizations" :key="org.id">
        <button
          type="button"
          role="option"
          :aria-selected="org.id === current?.id"
          class="flex w-full items-center justify-between gap-2 rounded-md px-2 py-2 text-left text-sm hover:bg-neutral-100 dark:hover:bg-neutral-800"
          @click="choose(org.id)"
        >
          <span class="min-w-0">
            <span class="block truncate">{{ org.name }}</span>
            <span class="block text-xs text-neutral-500 capitalize">
              {{ org.role.replace('_', ' ') }} · {{ org.base_currency }}
            </span>
          </span>
          <span v-if="org.id === current?.id" aria-hidden="true">✓</span>
        </button>
      </li>
    </ul>
  </div>
</template>

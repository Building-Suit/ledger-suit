<script setup lang="ts">
const { t, locale, locales, setLocale } = useI18n()
const { preference, set: setTheme } = useTheme()

const open = ref(false)
const root = ref<HTMLElement | null>(null)

const position = ref<'top' | 'bottom'>('bottom')

let resizeTimer: ReturnType<typeof setTimeout> | undefined

function updatePosition() {
  if (!root.value) return

  const menuElement = root.value.querySelector('.ls-card') as HTMLElement | null

  if (!menuElement)
    return

  const rootRect = root.value.getBoundingClientRect()

  // Because v-show makes the element display:none while closed,
  // only measure it after it has been opened.
  const menuHeight = menuElement.offsetHeight

  const viewportHeight = window.innerHeight

  const spaceBelow = viewportHeight - rootRect.bottom
  const spaceAbove = rootRect.top

  // Prefer opening downward.
  // Only flip upward if there isn't enough space below
  // and there is more room above.
  if (spaceBelow >= menuHeight) {
    position.value = 'bottom'
  }
  else if (spaceAbove >= menuHeight) {
    position.value = 'top'
  }
  else {
    // Neither direction fits completely.
    // Use whichever side has more available space.
    position.value = spaceBelow >= spaceAbove ? 'bottom' : 'top'
  }
}

useClickOutside(root, () => {
  open.value = false
})

const available = computed(() =>
  (locales.value as Array<{ code: string, name?: string }>).map(l => ({
    code: l.code,
    name: l.name ?? l.code,
  })),
)

const THEMES: Array<{ value: ThemePreference, labelKey: string }> = [
  { value: 'light', labelKey: 'common.themeLight' },
  { value: 'dark', labelKey: 'common.themeDark' },
  { value: 'system', labelKey: 'common.themeSystem' },
]

async function openMenu() {
  open.value = !open.value

  if (!open.value)
    return

  // Wait until v-show has actually rendered the menu.
  await nextTick()

  updatePosition()
}

function handleResize() {
  if (!open.value)
    return

  if (resizeTimer)
    clearTimeout(resizeTimer)

  resizeTimer = setTimeout(() => {
    updatePosition()
  }, 150)
}

onMounted(() => {
  window.addEventListener('resize', handleResize)
})

onBeforeUnmount(() => {
  window.removeEventListener('resize', handleResize)

  if (resizeTimer)
    clearTimeout(resizeTimer)
})
</script>

<template>
  <div
    ref="root"
    class="relative"
  >
    <button
      type="button"
      class="ls-btn ls-btn-sm w-full"
      :aria-expanded="open"
      aria-haspopup="menu"
      @click="openMenu"
    >
      <AppIcon name="settings" />

      <span class="hidden sm:inline">
        {{ t('common.language') }} · {{ t('common.theme') }}
      </span>
    </button>

    <div
      v-show="open"
      :class="[
        'ls-card absolute start-0 z-30 my-1 w-56 p-2 shadow-overlay',
        position === 'bottom'
          ? 'top-full'
          : 'bottom-full',
      ]"
      role="menu"
    >
      <p class="px-2 pb-1 text-xs font-semibold text-fg-muted">
        {{ t('common.language') }}
      </p>

      <button
        v-for="option in available"
        :key="option.code"
        type="button"
        role="menuitemradio"
        :aria-checked="locale === option.code"
        class="flex w-full items-center justify-between rounded-chip px-2 py-2 text-start text-sm hover:bg-surface-muted"
        @click="setLocale(option.code as typeof locale); open = false"
      >
        <span>{{ option.name }}</span>
        <AppIcon
          v-if="locale === option.code"
          name="check"
          class="text-[var(--bs-status-success)]"
        />
      </button>

      <hr class="my-2 border-[var(--bs-border)]">

      <p class="px-2 pb-1 text-xs font-semibold text-fg-muted">
        {{ t('common.theme') }}
      </p>

      <button
        v-for="option in THEMES"
        :key="option.value"
        type="button"
        role="menuitemradio"
        :aria-checked="preference === option.value"
        class="flex w-full items-center justify-between rounded-chip px-2 py-2 text-start text-sm hover:bg-surface-muted"
        @click="setTheme(option.value)"
      >
        <span>{{ t(option.labelKey) }}</span>

        <AppIcon
          v-if="preference === option.value"
          name="check"
          class="text-[var(--bs-status-success)]"
        />
      </button>
    </div>
  </div>
</template>

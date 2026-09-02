<script setup lang="ts">
/** Language and theme. Both are user preferences, so they live in a menu rather
 *  than taking space in the primary navigation. */
const { t, locale, locales, setLocale } = useI18n()
const { preference, set: setTheme } = useTheme()

const open = ref(false)
const root = ref<HTMLElement | null>(null)

useClickOutside(root, () => (open.value = false))

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
</script>

<template>
  <div ref="root" class="relative">
    <button
      type="button"
      class="ls-btn ls-btn-sm w-full"
      :aria-expanded="open"
      aria-haspopup="menu"
      @click="open = !open"
    >
      <span aria-hidden="true">⚙</span>
      <span>{{ t('common.language') }} · {{ t('common.theme') }}</span>
    </button>

    <div
      v-if="open"
      class="ls-card absolute top-full start-0 z-30 my-1 w-56 p-2 shadow-overlay"
      role="menu"
    >
      <p class="px-2 pb-1 text-xs font-semibold text-fg-muted">{{ t('common.language') }}</p>
      <button
        v-for="option in available"
        :key="option.code"
        type="button"
        role="menuitemradio"
        :aria-checked="locale === option.code"
        class="flex w-full items-center justify-between rounded-chip px-2 py-1.5 text-start text-sm hover:bg-surface-muted"
        @click="setLocale(option.code as typeof locale); open = false"
      >
        <span>{{ option.name }}</span>
        <span v-if="locale === option.code" aria-hidden="true">✓</span>
      </button>

      <hr class="my-2 border-[var(--bs-border)]">

      <p class="px-2 pb-1 text-xs font-semibold text-fg-muted">{{ t('common.theme') }}</p>
      <button
        v-for="option in THEMES"
        :key="option.value"
        type="button"
        role="menuitemradio"
        :aria-checked="preference === option.value"
        class="flex w-full items-center justify-between rounded-chip px-2 py-1.5 text-start text-sm hover:bg-surface-muted"
        @click="setTheme(option.value)"
      >
        <span>{{ t(option.labelKey) }}</span>
        <span v-if="preference === option.value" aria-hidden="true">✓</span>
      </button>
    </div>
  </div>
</template>

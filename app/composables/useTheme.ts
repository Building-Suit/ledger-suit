export type ThemePreference = 'light' | 'dark' | 'system'

export const STORAGE_KEY = 'ledger-suit.theme'

/**
 * Light / dark / follow-the-system.
 *
 * Writes `data-theme` on <html>, which is what the token layer keys off. When
 * the preference is "system" the attribute is removed entirely so the
 * prefers-color-scheme fallback in tokens.css takes over.
 *
 * On first load the attribute is set before paint by the inline script in
 * nuxt.config.ts, so the stored theme is visible from the very first frame
 * with no flash in either direction.
 */
export function useTheme() {
  const preference = useState<ThemePreference>('theme', () => 'system')

  function apply(value: ThemePreference) {
    if (!import.meta.client) return

    const root = document.documentElement
    if (value === 'system') root.removeAttribute('data-theme')
    else root.setAttribute('data-theme', value)
  }

  function set(value: ThemePreference) {
    preference.value = value
    if (import.meta.client) localStorage.setItem(STORAGE_KEY, value)
    apply(value)
  }

  function restore() {
    if (!import.meta.client) return
    const stored = localStorage.getItem(STORAGE_KEY) as ThemePreference | null
    preference.value = stored ?? 'system'
    // The inline head script already set the attribute pre-paint; re-apply
    // synchronously to cover clients where it did not run (private mode,
    // storage disabled) or when the two could disagree.
    apply(preference.value)
  }

  return { preference, set, restore }
}

export type ThemePreference = 'light' | 'dark' | 'system'

export const STORAGE_KEY = 'ledger-suit.theme'

/**
 * Light / dark / follow-the-system.
 *
 * Writes `data-theme` on <html>, which is what the token layer keys off. When
 * the preference is "system" the attribute is removed entirely so the
 * prefers-color-scheme fallback in tokens.css takes over.
 */
export function useTheme() {
  const preference = useState<ThemePreference>('theme', () => 'system')

  function apply(value: ThemePreference) {
    if (!import.meta.client) return

    const root = document.documentElement

    // Force dark mode first for light theme users to avoid flash of light mode
    const currentTheme = root.getAttribute('data-theme') as ThemePreference | null
    const shouldForceDarkFirst = value === 'light' && currentTheme !== 'dark'

    if (shouldForceDarkFirst) {
      // Briefly apply dark first, then switch to light with CSS transition
      root.setAttribute('data-theme', 'dark')

      // Wait for transition to complete, then apply the actual theme
      setTimeout(() => {
        root.setAttribute('data-theme', value)
      }, 50) // Match CSS transition duration
    }
    else {
      root.setAttribute('data-theme', value)
    }
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
    // Delay the actual application to allow dark-first transition
    setTimeout(() => apply(preference.value), 50)
  }

  return { preference, set, restore }
}

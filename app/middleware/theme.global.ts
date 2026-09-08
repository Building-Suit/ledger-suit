import { STORAGE_KEY } from '~/composables/useTheme'
/**
 * Apply only the root theme attribute before the page mounts. Component state is
 * restored in onMounted so SSR and the first client render remain identical.
 *
 * On the very first load the inline head script in nuxt.config.ts has already
 * set the attribute pre-paint; this middleware re-applies it on every client
 * navigation so route changes respect a preference changed in another tab.
 */
export default defineNuxtRouteMiddleware(() => {
  if (!import.meta.client) return

  const preference = localStorage.getItem(STORAGE_KEY)
  const theme: 'light' | 'dark' | 'system'
    = preference === 'light' || preference === 'dark' || preference === 'system'
      ? preference
      : 'system'

  if (theme === 'system') document.documentElement.removeAttribute('data-theme')
  else document.documentElement.setAttribute('data-theme', theme)
})

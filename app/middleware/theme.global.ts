/**
 * Apply only the root theme attribute before the page mounts. Component state is
 * restored in onMounted so SSR and the first client render remain identical.
 */
export default defineNuxtRouteMiddleware(() => {
  if (!import.meta.client) return

  const preference = localStorage.getItem('ledger-suit.theme')
  const theme: 'light' | 'dark' | 'system'
    = preference === 'light' || preference === 'dark' || preference === 'system'
      ? preference
      : 'system'

  if (theme === 'system') document.documentElement.removeAttribute('data-theme')
  else document.documentElement.setAttribute('data-theme', theme)
})

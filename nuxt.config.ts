import tailwindcss from '@tailwindcss/vite'

export default defineNuxtConfig({
  compatibilityDate: '2026-08-30',
  devtools: { enabled: true },

  modules: ['@nuxtjs/supabase', '@nuxtjs/i18n', '@nuxt/eslint'],

  css: ['~/assets/css/main.css'],

  vite: {
    plugins: [tailwindcss()],
  },

  // Only the publishable (anon) key ever reaches the browser. The service role
  // key is deliberately absent from this config — it must never be bundled.
  supabase: {
    redirectOptions: {
      login: '/login',
      callback: '/confirm',
      exclude: ['/', '/login', '/signup'],
    },
  },

  i18n: {
    baseUrl: import.meta.env.APP_BASE_URL || 'http://localhost:3000',
    defaultLocale: 'en',
    // No URL prefix: this is an application, not a marketing site, and the
    // chosen language is a user preference rather than a route.
    strategy: 'no_prefix',
    locales: [
      { code: 'en', language: 'en-US', name: 'English', dir: 'ltr', file: 'en.json' },
      { code: 'ar', language: 'ar-EG', name: 'العربية', dir: 'rtl', file: 'ar.json' },
    ],
    detectBrowserLanguage: {
      useCookie: true,
      cookieKey: 'ledger-suit-locale',
      alwaysRedirect: false,
      fallbackLocale: 'en',
    },
  },

  typescript: {
    strict: true,
  },

  future: {
    compatibilityVersion: 4,
  },
})

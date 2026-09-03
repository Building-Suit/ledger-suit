import tailwindcss from '@tailwindcss/vite'

export default defineNuxtConfig({
  compatibilityDate: '2026-08-30',
  devtools: { enabled: true },

  app: {
    head: {
      link: [
        { rel: 'icon', type: 'image/svg+xml', href: '/brand/ledger-suit-app-icon.svg' },
      ],
    },
  },

  modules: ['@nuxtjs/supabase', '@nuxtjs/i18n', '@nuxt/eslint'],

  css: ['~/assets/css/main.css'],

  vite: {
    plugins: [tailwindcss()],
  },

  // Only the publishable (anon) key ever reaches the browser. The service role
  // key is deliberately absent from this config — it must never be bundled.
  supabase: {
    // Authentication and billing access are handled by the application-wide
    // entitlement middleware. The module's generic redirect cannot distinguish
    // an unpaid member from an unauthenticated visitor.
    redirect: false,
    redirectOptions: {
      login: '/login',
      callback: '/confirm',
      // Verification is intentionally reachable before a confirmed session,
      // while /subscribe is protected by our entitlement middleware so it can
      // distinguish unpaid workspaces from unauthenticated visitors.
      exclude: ['/', '/login', '/signup', '/verify-email', '/subscribe', '/dashboard', '/transactions', '/accounts', '/reports', '/billing'],
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

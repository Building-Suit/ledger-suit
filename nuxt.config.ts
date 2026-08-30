import tailwindcss from '@tailwindcss/vite'

export default defineNuxtConfig({
  compatibilityDate: '2026-08-30',
  devtools: { enabled: true },

  modules: ['@nuxtjs/supabase', '@nuxt/eslint'],

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
      exclude: ['/login'],
    },
  },

  typescript: {
    strict: true,
  },

  future: {
    compatibilityVersion: 4,
  },
})

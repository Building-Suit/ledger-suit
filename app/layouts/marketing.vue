<script setup lang="ts">
const { t } = useI18n()
const route = useRoute()
const user = useSupabaseUser()
const { restore } = useTheme()

const hydrated = ref(false)
const mobileNavOpen = ref(false)

const navigation = [
  { to: '/#features', label: 'landing.navFeatures' },
  { to: '/#workflow', label: 'landing.navWorkflow' },
  { to: '/#pricing', label: 'landing.navPricing' },
  { to: '/about', label: 'marketing.about' },
  { to: '/contact', label: 'marketing.contact' },
] as const

const legalLinks = [
  { to: '/about', label: 'marketing.about' },
  { to: '/contact', label: 'marketing.contact' },
  { to: '/terms', label: 'marketing.terms' },
  { to: '/privacy', label: 'marketing.privacy' },
  { to: '/delivery-shipping', label: 'marketing.deliveryShipping' },
  { to: '/refund-cancellation', label: 'marketing.refundCancellation' },
] as const

onMounted(() => {
  restore()
  hydrated.value = true
})

watch(() => route.fullPath, () => (mobileNavOpen.value = false))
</script>

<template>
  <div class="min-h-dvh bg-background text-fg" :data-hydrated="hydrated">
    <header class="sticky top-0 z-30 border-b-2 border-brand-gold bg-background/90 backdrop-blur-xl">
      <div class="mx-auto flex min-h-16 max-w-7xl items-center gap-3 px-4 lg:px-8">
        <NuxtLink to="/" class="inline-flex shrink-0" :aria-label="t('marketing.home')">
          <AppLogo class="my-2 h-auto w-auto max-w-36 sm:max-w-52" />
        </NuxtLink>

        <nav class="ms-auto hidden items-center gap-6 text-sm text-fg-muted xl:flex" :aria-label="t('landing.navigation')">
          <NuxtLink v-for="item in navigation" :key="item.to" :to="item.to" class="hover:text-fg">
            {{ t(item.label) }}
          </NuxtLink>
        </nav>

        <div class="ms-auto flex items-center gap-2 xl:ms-0">
          <SettingsMenu />
          <NuxtLink :to="user ? '/dashboard' : '/login'" class="ls-btn ls-btn-sm hidden xl:inline-flex">
            {{ user ? t('landing.openApp') : t('auth.signIn') }}
          </NuxtLink>
          <NuxtLink v-if="!user" to="/signup" class="ls-btn ls-btn-primary ls-btn-sm hidden xl:inline-flex">
            {{ t('landing.startTrial') }}
          </NuxtLink>
          <button
            type="button"
            class="ls-btn ls-btn-sm xl:hidden"
            :aria-label="mobileNavOpen ? t('nav.close') : t('nav.open')"
            :aria-expanded="mobileNavOpen"
            aria-controls="marketing-mobile-navigation"
            @click="mobileNavOpen = !mobileNavOpen"
          >
            <AppIcon :name="mobileNavOpen ? 'close' : 'menu'" />
          </button>
        </div>
      </div>

      <div v-show="mobileNavOpen" id="marketing-mobile-navigation" class="border-t border-[var(--bs-border)] bg-background xl:hidden">
        <div class="mx-auto max-w-7xl px-4 py-4 lg:px-8">
          <nav class="grid gap-1 text-sm" :aria-label="t('landing.navigation')">
            <NuxtLink
              v-for="item in navigation"
              :key="`mobile-${item.to}`"
              :to="item.to"
              class="rounded-control px-3 py-2 font-semibold text-fg-muted hover:bg-surface-muted hover:text-fg"
            >
              {{ t(item.label) }}
            </NuxtLink>
          </nav>
          <div class="mt-4 flex flex-wrap gap-2 border-t border-[var(--bs-border)] pt-4">
            <NuxtLink :to="user ? '/dashboard' : '/login'" class="ls-btn ls-btn-sm">
              {{ user ? t('landing.openApp') : t('auth.signIn') }}
            </NuxtLink>
            <NuxtLink v-if="!user" to="/signup" class="ls-btn ls-btn-primary ls-btn-sm">
              {{ t('landing.startTrial') }}
            </NuxtLink>
          </div>
        </div>
      </div>
    </header>

    <slot />

    <footer class="border-t border-[var(--bs-border)] py-8">
      <div class="mx-auto flex max-w-7xl flex-col gap-4 px-4 text-xs text-fg-muted lg:px-8">
        <div class="flex flex-wrap items-center justify-between gap-4">
          <span dir="ltr">© 2026 Building Suit</span>
          <span>{{ t('landing.footer') }}</span>
        </div>

        <nav class="flex flex-wrap gap-x-5 gap-y-2" :aria-label="t('marketing.footerNavigation')">
          <NuxtLink v-for="item in legalLinks" :key="item.to" :to="item.to" class="hover:text-fg">
            {{ t(item.label) }}
          </NuxtLink>
        </nav>
      </div>
    </footer>
  </div>
</template>

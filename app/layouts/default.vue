<script setup lang="ts">
// The four primary financial pages, and nothing else. Everything secondary
// (categories, members, currencies, audit log, subscription) belongs in
// Settings or a contextual panel — see spec section 4.
const NAV = [
  { to: '/', key: 'dashboard', icon: '◧' },
  { to: '/transactions', key: 'transactions', icon: '≡' },
  { to: '/accounts', key: 'accounts', icon: '▤' },
  { to: '/reports', key: 'reports', icon: '◔' },
]

const supabase = useSupabaseClient()
const user = useSupabaseUser()
const route = useRoute()
const { t } = useI18n()
const { current, loadOrganizations, loading } = useTenant()
const { can } = useTenant()
const { show: showOperations } = useOperationsCenter()
const { restore } = useTheme()

const mobileNavOpen = ref(false)

await loadOrganizations()
onMounted(restore)

// Collapse the mobile drawer on navigation, otherwise it covers the page the
// user just asked for.
watch(() => route.fullPath, () => (mobileNavOpen.value = false))

function isActive(to: string) {
  return to === '/' ? route.path === '/' : route.path.startsWith(to)
}

async function signOut() {
  await supabase.auth.signOut()
  await navigateTo('/login')
}
</script>

<template>
  <div class="min-h-dvh lg:grid lg:grid-cols-[16rem_1fr]">
    <!-- Shown/hidden rather than slid off-screen with a transform: a translate
         utility that silently fails to apply leaves the drawer sitting on top
         of the page on every phone, which is exactly what happened here. -->
    <aside
      class="fixed inset-y-0 start-0 z-40 w-64 border-e border-[var(--bs-border)] bg-surface lg:static lg:block"
      :class="mobileNavOpen ? 'block' : 'hidden'"
    >
      <div class="flex h-full flex-col gap-6 p-4">
        <div class="flex items-center justify-between">
          <!-- The product name stays Latin even in Arabic copy. -->
          <NuxtLink to="/" class="text-base font-extrabold tracking-tight" dir="ltr">
            {{ t('app.name') }}
          </NuxtLink>
          <button
            type="button"
            class="ls-btn ls-btn-sm lg:hidden"
            :aria-label="t('nav.close')"
            @click="mobileNavOpen = false"
          >
            ✕
          </button>
        </div>

        <OrganizationSwitcher />

        <nav :aria-label="t('nav.primary')" class="flex flex-col gap-1">
          <NuxtLink
            v-for="item in NAV"
            :key="item.to"
            :to="item.to"
            class="ls-nav-link"
            :class="{ 'ls-nav-link-active': isActive(item.to) }"
            :aria-current="isActive(item.to) ? 'page' : undefined"
          >
            <span aria-hidden="true" class="w-4 text-center">{{ item.icon }}</span>
            <span>{{ t(`nav.${item.key}`) }}</span>
          </NuxtLink>
        </nav>

        <div class="mt-auto space-y-2 border-t border-[var(--bs-border)] pt-3">
          <TeamMenu />
          <SettingsMenu />
          <p class="truncate px-1 text-xs text-fg-muted">{{ user?.email }}</p>
          <button type="button" class="ls-btn ls-btn-sm w-full" @click="signOut">
            {{ t('common.signOut') }}
          </button>
        </div>
      </div>
    </aside>

    <div
      v-if="mobileNavOpen"
      class="fixed inset-0 z-30 ls-scrim lg:hidden"
      aria-hidden="true"
      @click="mobileNavOpen = false"
    />

    <div class="flex min-w-0 flex-col">
      <header class="sticky top-0 z-20 flex items-center gap-3 border-b border-[var(--bs-border)] bg-background/90 px-4 py-3 backdrop-blur lg:px-8">
        <button
          type="button"
          class="ls-btn ls-btn-sm lg:hidden"
          :aria-label="t('nav.open')"
          @click="mobileNavOpen = true"
        >
          ☰
        </button>

        <div class="min-w-0 flex-1">
          <p class="truncate text-sm font-semibold">{{ current?.name }}</p>
        </div>

        <button
          v-if="can('commitments.read') || can('recurring.read')"
          type="button" class="ls-btn ls-btn-sm" @click="showOperations('commitments')"
        >{{ t('operations.title') }}</button>
        <NotificationMenu />
        <AddMenu />
      </header>

      <main class="mx-auto w-full max-w-[1280px] min-w-0 flex-1 px-4 py-6 lg:px-8">
        <div v-if="loading" class="text-sm text-fg-muted">{{ t('app.loading') }}</div>

        <OrganizationSetup v-else-if="!current" />

        <slot v-else />
      </main>
    </div>

    <AddTransactionDialog />
    <OperationsCenter />
    <ToastHost />
  </div>
</template>

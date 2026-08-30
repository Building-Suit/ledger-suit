<script setup lang="ts">
// The four primary financial pages, and nothing else. Everything secondary
// (categories, members, currencies, audit log, subscription) belongs in
// Settings or a contextual panel — see spec section 4.
const NAV = [
  { to: '/', label: 'Dashboard', icon: '◧' },
  { to: '/transactions', label: 'Transactions', icon: '≡' },
  { to: '/accounts', label: 'Accounts', icon: '▤' },
  { to: '/reports', label: 'Reports', icon: '◔' },
]

const supabase = useSupabaseClient()
const user = useSupabaseUser()
const route = useRoute()
const { current, loadOrganizations, loading } = useTenant()

const mobileNavOpen = ref(false)

await loadOrganizations()

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
    <!-- Sidebar -->
    <!-- Shown/hidden rather than slid off-screen with a transform: a translate
         utility that silently fails to apply leaves the drawer sitting on top
         of the page on every phone, which is exactly what happened here. -->
    <aside
      class="fixed inset-y-0 left-0 z-40 w-64 border-r border-neutral-200 bg-white lg:static lg:block dark:border-neutral-800 dark:bg-neutral-900"
      :class="mobileNavOpen ? 'block' : 'hidden'"
    >
      <div class="flex h-full flex-col gap-4 p-4">
        <div class="flex items-center justify-between">
          <NuxtLink to="/" class="text-base font-semibold">Ledger Suit</NuxtLink>
          <button
            type="button"
            class="ls-btn ls-btn-sm lg:hidden"
            aria-label="Close navigation"
            @click="mobileNavOpen = false"
          >
            ✕
          </button>
        </div>

        <OrganizationSwitcher />

        <nav aria-label="Primary" class="flex flex-col gap-1">
          <NuxtLink
            v-for="item in NAV"
            :key="item.to"
            :to="item.to"
            class="ls-nav-link"
            :class="{ 'ls-nav-link-active': isActive(item.to) }"
            :aria-current="isActive(item.to) ? 'page' : undefined"
          >
            <span aria-hidden="true" class="w-4 text-center">{{ item.icon }}</span>
            <span>{{ item.label }}</span>
          </NuxtLink>
        </nav>

        <div class="mt-auto border-t border-neutral-200 pt-3 dark:border-neutral-800">
          <p class="truncate text-xs text-neutral-500">{{ user?.email }}</p>
          <button type="button" class="ls-btn ls-btn-sm mt-2 w-full" @click="signOut">
            Sign out
          </button>
        </div>
      </div>
    </aside>

    <div
      v-if="mobileNavOpen"
      class="fixed inset-0 z-30 bg-black/40 lg:hidden"
      aria-hidden="true"
      @click="mobileNavOpen = false"
    />

    <!-- Content -->
    <div class="flex min-w-0 flex-col">
      <header class="sticky top-0 z-20 flex items-center gap-3 border-b border-neutral-200 bg-neutral-50/90 px-4 py-3 backdrop-blur lg:px-8 dark:border-neutral-800 dark:bg-neutral-950/90">
        <button
          type="button"
          class="ls-btn ls-btn-sm lg:hidden"
          aria-label="Open navigation"
          @click="mobileNavOpen = true"
        >
          ☰
        </button>

        <div class="min-w-0 flex-1">
          <p class="truncate text-sm font-medium">{{ current?.name }}</p>
        </div>

        <AddMenu />
      </header>

      <main class="min-w-0 flex-1 px-4 py-6 lg:px-8">
        <div v-if="loading" class="text-sm text-neutral-500">Loading…</div>

        <EmptyState
          v-else-if="!current"
          title="You are not a member of any organization yet."
          description="Ask an owner to invite you, or create one to start tracking your finances."
        />

        <slot v-else />
      </main>
    </div>

    <AddTransactionDialog />
    <ToastHost />
  </div>
</template>

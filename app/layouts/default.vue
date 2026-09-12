<script setup lang="ts">
const PRIMARY_NAV = [
  { to: '/dashboard', key: 'dashboard', icon: 'dashboard' },
  { to: '/transactions', key: 'transactions', icon: 'transactions' },
  { to: '/accounts', key: 'accounts', icon: 'wallet' },
  { to: '/reports', key: 'reports', icon: 'reports' },
] as const

const TRANSACTION_LINKS = ADD_FLOWS.map(flow => ({
  to: `/records/${flow}`,
  label: `add.flows.${flow}`,
}))

const NAV_GROUPS = computed(() => [
  {
    key: 'transactions',
    links: [
      ...(can('transactions.read') ? [{ to: '/transactions', label: 'nav.allTransactions' }] : []),
      ...(can('imports.create') ? [{ to: '/imports', label: 'nav.importTransactions' }] : []),
      ...(can('transactions.create') ? TRANSACTION_LINKS : []),
    ],
  },
  {
    key: 'ledger',
    links: can('accounts.read') ? [{ to: '/accounts', label: 'nav.accounts' }] : [],
  },
  {
    key: 'operations',
    links: [
      ...(can('commitments.read') ? [{ to: '/records/commitments', label: 'operations.tabs.commitments' }] : []),
      ...(can('recurring.read') ? [{ to: '/records/recurring', label: 'add.items.recurring' }] : []),
    ],
  },
  {
    key: 'directory',
    links: [
      ...(can('counterparties.read') ? [{ to: '/records/counterparties', label: 'operations.tabs.counterparties' }] : []),
      ...(can('tags.read') ? [{ to: '/records/tags', label: 'operations.tabs.tags' }] : []),
    ],
  },
  {
    key: 'workspace',
    links: can('members.read') ? [{ to: '/team', label: 'nav.teamInvitations' }] : [],
  },
  {
    key: 'insights',
    links: can('reports.read') ? [{ to: '/reports', label: 'nav.reports' }] : [],
  },
].filter(group => group.links.length))

const route = useRoute()
const { t } = useI18n()
const { current, currentId, loadOrganizations, loading } = useTenant()
const { can } = useTenant()
const {
  accessState,
  paymentRequired,
  readOnly,
  load: loadBilling,
} = useBilling()
const { restore } = useTheme()

const mobileNavOpen = ref(false)

await loadOrganizations()
await loadBilling()
onMounted(restore)

watch(currentId, async (value, previous) => {
  if (value !== previous) await loadBilling()
})

// Collapse the mobile drawer on navigation, otherwise it covers the page the
// user just asked for.
watch(() => route.fullPath, () => (mobileNavOpen.value = false))

function isActive(to: string) {
  return route.path === to || route.path.startsWith(`${to}/`)
}

</script>

<template>
  <div v-if="accessState === 'loading' || paymentRequired" class="min-h-dvh bg-background" aria-busy="true" />
  <div v-else class="min-h-dvh bg-background lg:grid lg:grid-cols-[17rem_1fr] lg:gap-4 lg:p-4">
    <!-- Shown/hidden rather than slid off-screen with a transform: a translate
         utility that silently fails to apply leaves the drawer sitting on top
         of the page on every phone, which is exactly what happened here. -->
    <aside
      class="fixed inset-y-0 start-0 z-40 w-64 border-e border-[var(--bs-border)] bg-surface lg:sticky lg:top-4 lg:block lg:h-[calc(100dvh-2rem)] lg:w-auto lg:rounded-modal lg:border lg:shadow-card"
      :class="mobileNavOpen ? 'block' : 'hidden'"
    >
      <div class="flex h-full min-h-0 flex-col gap-4 p-4">
        <div class="flex items-center justify-between">
          <NuxtLink to="/dashboard" class="inline-flex" :aria-label="t('app.name')">
            <AppLogo class="h-14 w-auto max-w-52" />
          </NuxtLink>
          <button
            type="button"
            class="ls-btn ls-btn-sm lg:hidden"
            :aria-label="t('nav.close')"
            @click="mobileNavOpen = false"
          >
            <AppIcon name="close" />
          </button>
        </div>

        <hr class="my-2 border-[var(--bs-border)]">

        <nav :aria-label="t('nav.primary')" class="min-h-0 flex-1 space-y-5 overflow-y-auto pe-1">
          <NuxtLink
            to="/dashboard"
            class="ls-nav-link"
            :class="{ 'ls-nav-link-active': isActive('/dashboard') }"
            :aria-current="isActive('/dashboard') ? 'page' : undefined"
          >
            <AppIcon name="dashboard" />
            <span>{{ t('nav.dashboard') }}</span>
          </NuxtLink>
          <section v-for="group in NAV_GROUPS" :key="group.key">
            <h2 class="mb-1.5 px-3 text-md font-bold uppercase tracking-[0.16em]">
              {{ t(`nav.groups.${group.key}`) }}
            </h2>
            <div class="flex flex-col gap-0.5 ms-6">
              <NuxtLink
                v-for="item in group.links"
                :key="item.to"
                :to="item.to"
                class="ls-nav-link py-2"
                :class="{ 'ls-nav-link-active': isActive(item.to) }"
                :aria-current="isActive(item.to) ? 'page' : undefined"
              >
                <span>{{ t(item.label) }}</span>
              </NuxtLink>
            </div>
          </section>
        </nav>

      </div>
    </aside>

    <div
      v-if="mobileNavOpen"
      class="fixed inset-0 z-30 ls-scrim lg:hidden"
      aria-hidden="true"
      @click="mobileNavOpen = false"
    />

    <div class="flex min-w-0 flex-col">
      <header class="sticky top-0 z-20 flex items-center gap-3 border-b border-[var(--bs-border)] bg-surface/90 px-4 py-3 backdrop-blur lg:top-4 lg:rounded-card lg:border lg:px-6 lg:shadow-card">
        <button
          type="button"
          class="ls-btn ls-btn-sm lg:hidden"
          :aria-label="t('nav.open')"
          @click="mobileNavOpen = true"
        >
          <AppIcon name="menu" />
        </button>

        <div class="min-w-0 flex-1" />

        <TrialCountdown />
        <NotificationMenu />
        <AccountMenu />
        <OrganizationSwitcher class="w-64" />
      </header>

      <main class="mx-auto w-full max-w-[1280px] min-w-0 flex-1 px-4 py-6 pb-24 lg:px-8 lg:pb-6">
        <div v-if="loading" class="text-sm text-fg-muted">{{ t('app.loading') }}</div>

        <OrganizationSetup v-else-if="!current" />

        <template v-else>
          <div v-if="readOnly" class="mb-6 rounded-control border border-warning bg-[var(--bs-status-warning-bg)] p-4 text-sm" role="status">
            <p class="font-semibold">{{ t('billing.readOnlyTitle') }}</p>
            <p>{{ t('billing.readOnlyBody') }}</p>
            <NuxtLink v-if="can('billing.manage')" to="/billing" class="mt-2 inline-block text-link">{{ t('billing.fixBilling') }}</NuxtLink>
          </div>
          <slot />
        </template>
      </main>
    </div>

    <nav class="fixed inset-x-0 bottom-0 z-30 grid grid-cols-4 border-t border-[var(--bs-border)] bg-surface px-2 pb-[env(safe-area-inset-bottom)] shadow-raised lg:hidden" :aria-label="t('nav.primary')">
      <NuxtLink
        v-for="item in PRIMARY_NAV"
        :key="`mobile-${item.to}`"
        :to="item.to"
        class="flex min-h-16 flex-col items-center justify-center gap-1 text-xs font-medium text-fg-muted"
        :class="{ 'text-accent': isActive(item.to) }"
        :aria-current="isActive(item.to) ? 'page' : undefined"
      >
        <AppIcon :name="item.icon" :size="22" />
        <span>{{ t(`nav.${item.key}`) }}</span>
      </NuxtLink>
    </nav>

    <AddTransactionDialog />
    <OperationsCenter />
    <FinancialSystemMap />
    <ToastHost />
  </div>
</template>

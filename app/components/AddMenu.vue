<script setup lang="ts">
const { can } = useTenant()
const { start } = useAddTransaction()
const { show: showOperations } = useOperationsCenter()
const { show: showInvitation } = useTeamInvitation()
const { t } = useI18n()
const route = useRoute()

const open = ref(false)
const flows = computed(() => ADD_FLOWS.filter(flow => can(FLOW_CAPABILITY[flow])))
interface AddItem { key: string; label: string; hint: string; action: () => unknown }

const groups = computed(() => [
  {
    key: 'transactions',
    items: flows.value.map(flow => ({
      key: flow,
      label: t(`add.flows.${flow}`),
      hint: t(`add.hints.${flow}`),
      action: () => start(flow),
    })),
  },
  {
    key: 'accounts',
    items: can('accounts.create')
      ? [{ key: 'account', label: t('add.items.account'), hint: t('add.itemHints.account'), action: () => navigateTo('/accounts?create=account') }]
      : [],
  },
  {
    key: 'operations',
    items: [
      ...(can('commitments.create') ? [{ key: 'commitment', label: t('add.items.commitment'), hint: t('add.itemHints.commitment'), action: () => showOperations('commitments') }] : []),
      ...(can('recurring.manage') ? [{ key: 'recurring', label: t('add.items.recurring'), hint: t('add.itemHints.recurring'), action: () => showOperations('recurring') }] : []),
      ...(can('counterparties.manage') ? [{ key: 'counterparty', label: t('add.items.counterparty'), hint: t('add.itemHints.counterparty'), action: () => showOperations('counterparties') }] : []),
      ...(can('tags.manage') ? [{ key: 'tag', label: t('add.items.tag'), hint: t('add.itemHints.tag'), action: () => showOperations('tags') }] : []),
    ] as AddItem[],
  },
  {
    key: 'workspace',
    items: can('members.invite')
      ? [{ key: 'invitation', label: t('add.items.invitation'), hint: t('add.itemHints.invitation'), action: showInvitation }]
      : [],
  },
].filter(group => group.items.length))

function choose(action: () => unknown) {
  open.value = false
  void action()
}

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') open.value = false
}

watch(() => route.fullPath, () => (open.value = false))
onMounted(() => document.addEventListener('keydown', onKeydown))
onBeforeUnmount(() => document.removeEventListener('keydown', onKeydown))
</script>

<template>
  <div v-if="groups.length">
    <button
      type="button"
      class="fixed bottom-5 end-5 z-40 grid size-14 place-items-center rounded-full border border-white/10 bg-[var(--bs-ink)] text-2xl text-white shadow-overlay transition-transform hover:scale-105 lg:bottom-8 lg:end-8"
      :aria-label="t('add.title')"
      :aria-expanded="open"
      aria-haspopup="dialog"
      @click="open = true"
    >
      <span aria-hidden="true">+</span>
    </button>

    <Teleport to="body">
      <div v-if="open" class="fixed inset-0 z-[60] ls-scrim" @click.self="open = false">
        <aside
          class="absolute inset-y-0 end-0 flex w-full max-w-md flex-col border-s border-[var(--bs-border)] bg-surface shadow-overlay"
          role="dialog"
          aria-modal="true"
          :aria-label="t('add.title')"
        >
          <header class="flex items-start justify-between border-b border-[var(--bs-border)] p-6">
            <div>
              <p class="text-xs font-bold uppercase tracking-[0.18em] text-fg-muted">{{ t('add.eyebrow') }}</p>
              <h2 class="mt-1 text-2xl font-extrabold">{{ t('add.title') }}</h2>
            </div>
            <button type="button" class="ls-btn ls-btn-sm" :aria-label="t('common.close')" @click="open = false">✕</button>
          </header>

          <div class="flex-1 space-y-7 overflow-y-auto p-6">
            <section v-for="group in groups" :key="group.key">
              <h3 class="mb-2 text-xs font-bold uppercase tracking-[0.15em] text-fg-muted">{{ t(`add.groups.${group.key}`) }}</h3>
              <div class="grid gap-2">
                <button
                  v-for="item in group.items"
                  :key="item.key"
                  type="button"
                  class="group rounded-control border border-[var(--bs-border)] bg-surface-raised p-4 text-start transition-colors hover:border-[var(--bs-border-strong)] hover:bg-surface-muted"
                  @click="choose(item.action)"
                >
                  <span class="block font-bold">{{ item.label }}</span>
                  <span class="mt-1 block text-xs text-fg-muted">{{ item.hint }}</span>
                </button>
              </div>
            </section>
          </div>
        </aside>
      </div>
    </Teleport>
  </div>
</template>

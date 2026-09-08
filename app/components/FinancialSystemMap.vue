<script setup lang="ts">
const { t } = useI18n()
const route = useRoute()
const open = ref(false)
const closeButton = ref<HTMLButtonElement | null>(null)
let previousBodyOverflow = ''

const manualFlows = [
  'income',
  'expense',
  'transfer',
  'asset',
  'liability',
  'repayment',
  'owner',
  'adjustment',
] as const

const postingChecks = ['access', 'period', 'accounts', 'balance', 'atomic'] as const
const reports = ['profitLoss', 'balanceSheet', 'cashFlow', 'trialBalance', 'generalLedger'] as const

function show() {
  open.value = true
}

function close() {
  open.value = false
}

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape' && open.value) close()
}

watch(open, async (isOpen) => {
  if (!import.meta.client) return
  if (isOpen) {
    previousBodyOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    await nextTick()
    closeButton.value?.focus()
  }
  else {
    document.body.style.overflow = previousBodyOverflow
  }
})

watch(() => route.fullPath, close)

onMounted(() => window.addEventListener('keydown', onKeydown))
onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKeydown)
  document.body.style.overflow = previousBodyOverflow
})
</script>

<template>
  <button
    type="button"
    class="financial-map-fab fixed bottom-20 end-4 z-20 flex items-center gap-2 rounded-full border border-[var(--bs-border)] bg-surface px-4 py-3 font-semibold text-fg shadow-raised transition hover:-translate-y-0.5 hover:border-[var(--bs-primary)] hover:text-primary lg:bottom-6 lg:end-6"
    :aria-label="t('financialMap.open')"
    @click="show"
  >
    <AppIcon name="chart" :size="22" />
    <span class="hidden sm:inline">{{ t('financialMap.button') }}</span>
  </button>

  <Teleport to="body">
    <Transition name="ls-modal">
      <div
        v-if="open"
        class="fixed inset-0 z-[70] grid place-items-center ls-scrim p-0 sm:p-4"
        role="dialog"
        aria-modal="true"
        aria-labelledby="financial-map-title"
        @click.self="close"
      >
        <section class="ls-modal-panel flex h-dvh w-full flex-col overflow-hidden bg-background shadow-overlay sm:h-[94dvh] sm:max-w-[1500px] sm:rounded-modal sm:border sm:border-[var(--bs-border)]">
          <header class="flex shrink-0 items-start gap-4 border-b border-[var(--bs-border)] bg-surface px-4 py-4 sm:px-6">
            <div class="min-w-0 flex-1">
              <p class="text-xs font-bold uppercase tracking-[0.14em] text-primary">{{ t('financialMap.eyebrow') }}</p>
              <h2 id="financial-map-title" class="mt-1 text-xl font-bold sm:text-2xl">{{ t('financialMap.title') }}</h2>
              <p class="mt-1 max-w-4xl text-sm text-fg-muted">{{ t('financialMap.subtitle') }}</p>
            </div>
            <button ref="closeButton" type="button" class="ls-btn ls-btn-sm shrink-0" :aria-label="t('common.close')" @click="close">
              <AppIcon name="close" />
            </button>
          </header>

          <div class="min-h-0 flex-1 overflow-auto px-4 py-6 sm:px-6 lg:px-10">
            <div class="financial-tree mx-auto max-w-[1280px] pb-4">
              <section class="tree-node tree-node-start mx-auto max-w-3xl">
                <div class="tree-step">{{ t('financialMap.steps.setup') }}</div>
                <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
                  <div>
                    <h3 class="text-lg font-bold">{{ t('financialMap.setup.title') }}</h3>
                    <p class="mt-1 text-sm text-fg-muted">{{ t('financialMap.setup.body') }}</p>
                  </div>
                  <div class="flex shrink-0 flex-wrap gap-2">
                    <NuxtLink to="/accounts" class="ls-btn ls-btn-sm ls-btn-secondary" @click="close">{{ t('financialMap.setup.reviewAccounts') }}</NuxtLink>
                    <NuxtLink to="/records/expense" class="ls-btn ls-btn-sm ls-btn-primary" @click="close">{{ t('financialMap.setup.firstEntry') }}</NuxtLink>
                  </div>
                </div>
                <div class="mt-4 grid gap-2 sm:grid-cols-3">
                  <div class="tree-mini"><strong>{{ t('financialMap.setup.organization') }}</strong><span>{{ t('financialMap.setup.organizationHint') }}</span></div>
                  <div class="tree-mini"><strong>{{ t('financialMap.setup.accounts') }}</strong><span>{{ t('financialMap.setup.accountsHint') }}</span></div>
                  <div class="tree-mini"><strong>{{ t('financialMap.setup.categories') }}</strong><span>{{ t('financialMap.setup.categoriesHint') }}</span></div>
                </div>
              </section>

              <div class="tree-arrow" aria-hidden="true"><span>↓</span></div>

              <section aria-labelledby="financial-map-inputs">
                <div class="tree-stage-heading">
                  <span class="tree-step">{{ t('financialMap.steps.record') }}</span>
                  <h3 id="financial-map-inputs">{{ t('financialMap.sourcesTitle') }}</h3>
                  <p>{{ t('financialMap.sourcesHint') }}</p>
                </div>

                <div class="tree-branches tree-branches-three">
                  <article class="tree-node">
                    <div class="tree-node-icon"><AppIcon name="transactions" /></div>
                    <h3>{{ t('financialMap.manual.title') }}</h3>
                    <p>{{ t('financialMap.manual.body') }}</p>
                    <div class="mt-3 flex flex-wrap gap-1.5">
                      <span v-for="flow in manualFlows" :key="flow" class="tree-pill">{{ t(`financialMap.manual.flows.${flow}`) }}</span>
                    </div>
                    <NuxtLink to="/transactions" class="tree-link" @click="close">{{ t('financialMap.manual.link') }} <AppIcon name="arrowRight" :size="15" directional /></NuxtLink>
                  </article>

                  <article class="tree-node tree-node-waiting">
                    <div class="tree-node-icon"><AppIcon name="invoice" /></div>
                    <h3>{{ t('financialMap.commitments.title') }}</h3>
                    <p>{{ t('financialMap.commitments.body') }}</p>
                    <div class="tree-callout">{{ t('financialMap.commitments.rule') }}</div>
                    <NuxtLink to="/records/commitments" class="tree-link" @click="close">{{ t('financialMap.commitments.link') }} <AppIcon name="arrowRight" :size="15" directional /></NuxtLink>
                  </article>

                  <article class="tree-node tree-node-waiting">
                    <div class="tree-node-icon"><AppIcon name="repeat" /></div>
                    <h3>{{ t('financialMap.recurring.title') }}</h3>
                    <p>{{ t('financialMap.recurring.body') }}</p>
                    <div class="tree-callout">{{ t('financialMap.recurring.rule') }}</div>
                    <NuxtLink to="/records/recurring" class="tree-link" @click="close">{{ t('financialMap.recurring.link') }} <AppIcon name="arrowRight" :size="15" directional /></NuxtLink>
                  </article>
                </div>
              </section>

              <div class="tree-merge" aria-hidden="true"><span>{{ t('financialMap.converges') }}</span></div>

              <section class="tree-node tree-node-engine mx-auto max-w-4xl">
                <div class="tree-step">{{ t('financialMap.steps.validate') }}</div>
                <div class="flex items-start gap-3">
                  <div class="tree-node-icon"><AppIcon name="checkBadge" :size="24" /></div>
                  <div>
                    <h3 class="text-lg font-bold">{{ t('financialMap.engine.title') }}</h3>
                    <p class="mt-1 text-sm opacity-80">{{ t('financialMap.engine.body') }}</p>
                  </div>
                </div>
                <ol class="mt-4 grid gap-2 sm:grid-cols-2 lg:grid-cols-5">
                  <li v-for="(check, index) in postingChecks" :key="check" class="tree-engine-check">
                    <span>{{ index + 1 }}</span>{{ t(`financialMap.engine.checks.${check}`) }}
                  </li>
                </ol>
              </section>

              <div class="tree-arrow" aria-hidden="true"><span>↓</span></div>

              <section class="tree-node tree-node-ledger mx-auto max-w-3xl">
                <div class="tree-step">{{ t('financialMap.steps.ledger') }}</div>
                <div class="grid gap-4 sm:grid-cols-[1fr_auto_1fr] sm:items-center">
                  <div>
                    <p class="text-xs font-bold uppercase tracking-[0.12em] text-primary">{{ t('financialMap.ledger.eventLabel') }}</p>
                    <h3>{{ t('financialMap.ledger.event') }}</h3>
                    <p>{{ t('financialMap.ledger.eventHint') }}</p>
                  </div>
                  <div class="hidden text-2xl text-primary sm:block" aria-hidden="true">+</div>
                  <div>
                    <p class="text-xs font-bold uppercase tracking-[0.12em] text-primary">{{ t('financialMap.ledger.linesLabel') }}</p>
                    <h3>{{ t('financialMap.ledger.lines') }}</h3>
                    <p>{{ t('financialMap.ledger.linesHint') }}</p>
                  </div>
                </div>
                <div class="tree-ledger-rule"><AppIcon name="ledger" :size="18" /> {{ t('financialMap.ledger.rule') }}</div>
              </section>

              <div class="tree-split" aria-hidden="true"><span>{{ t('financialMap.resultsFrom') }}</span></div>

              <section aria-labelledby="financial-map-results">
                <div class="tree-stage-heading">
                  <span class="tree-step">{{ t('financialMap.steps.results') }}</span>
                  <h3 id="financial-map-results">{{ t('financialMap.resultsTitle') }}</h3>
                  <p>{{ t('financialMap.resultsHint') }}</p>
                </div>

                <div class="tree-branches tree-branches-four">
                  <NuxtLink to="/accounts" class="tree-node tree-result" @click="close">
                    <div class="tree-node-icon"><AppIcon name="wallet" /></div>
                    <h3>{{ t('financialMap.results.accounts.title') }}</h3>
                    <p>{{ t('financialMap.results.accounts.body') }}</p>
                    <span class="tree-link">{{ t('financialMap.results.open') }} <AppIcon name="arrowRight" :size="15" directional /></span>
                  </NuxtLink>
                  <NuxtLink to="/dashboard" class="tree-node tree-result" @click="close">
                    <div class="tree-node-icon"><AppIcon name="dashboard" /></div>
                    <h3>{{ t('financialMap.results.dashboard.title') }}</h3>
                    <p>{{ t('financialMap.results.dashboard.body') }}</p>
                    <span class="tree-link">{{ t('financialMap.results.open') }} <AppIcon name="arrowRight" :size="15" directional /></span>
                  </NuxtLink>
                  <NuxtLink to="/reports" class="tree-node tree-result" @click="close">
                    <div class="tree-node-icon"><AppIcon name="reports" /></div>
                    <h3>{{ t('financialMap.results.reports.title') }}</h3>
                    <p>{{ t('financialMap.results.reports.body') }}</p>
                    <div class="mt-2 flex flex-wrap gap-1.5"><span v-for="report in reports" :key="report" class="tree-pill">{{ t(`financialMap.results.reports.items.${report}`) }}</span></div>
                    <span class="tree-link">{{ t('financialMap.results.open') }} <AppIcon name="arrowRight" :size="15" directional /></span>
                  </NuxtLink>
                  <NuxtLink to="/transactions" class="tree-node tree-result" @click="close">
                    <div class="tree-node-icon"><AppIcon name="automation" /></div>
                    <h3>{{ t('financialMap.results.audit.title') }}</h3>
                    <p>{{ t('financialMap.results.audit.body') }}</p>
                    <span class="tree-link">{{ t('financialMap.results.open') }} <AppIcon name="arrowRight" :size="15" directional /></span>
                  </NuxtLink>
                </div>
              </section>

              <aside class="mt-6 rounded-card border border-[var(--bs-border)] bg-surface-muted p-4 text-sm">
                <strong>{{ t('financialMap.boundary.title') }}</strong>
                <span class="ms-1 text-fg-muted">{{ t('financialMap.boundary.body') }}</span>
              </aside>
            </div>
          </div>
        </section>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.financial-map-fab { box-shadow: var(--bs-elevation-3); }

.tree-node {
  position: relative;
  display: block;
  border: 1px solid var(--bs-border);
  border-radius: var(--bs-radius-card);
  background: var(--bs-surface);
  padding: 1rem;
  box-shadow: var(--bs-elevation-1);
}

.tree-node h3 { font-weight: 700; }
.tree-node p { margin-top: 0.3rem; color: var(--bs-text-muted); font-size: 0.875rem; }

.tree-node-start { border-color: var(--bs-primary); }
.tree-node-engine { background: var(--bs-deep-structure-navy); color: var(--bs-white); border-color: transparent; }
.tree-node-engine p { color: inherit; }
.tree-node-ledger { border-width: 2px; border-color: var(--bs-primary); }
.tree-node-waiting { border-style: dashed; }

.tree-step {
  display: inline-flex;
  margin-bottom: 0.65rem;
  border-radius: 999px;
  background: var(--bs-status-info-bg);
  padding: 0.25rem 0.65rem;
  color: var(--bs-primary);
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.09em;
}

.tree-node-engine .tree-step { background: rgb(255 255 255 / 0.12); color: var(--bs-white); }

.tree-mini {
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
  border-radius: var(--bs-radius-button);
  background: var(--bs-surface-muted);
  padding: 0.75rem;
  font-size: 0.8rem;
}

.tree-mini span { color: var(--bs-text-muted); }

.tree-arrow {
  display: grid;
  height: 3.5rem;
  place-items: center;
  color: var(--bs-primary);
  font-size: 1.5rem;
  font-weight: 700;
}

.tree-stage-heading { margin: 0 auto 1rem; max-width: 44rem; text-align: center; }
.tree-stage-heading .tree-step { margin-bottom: 0.35rem; }
.tree-stage-heading h3 { font-size: 1.1rem; font-weight: 700; }
.tree-stage-heading p { margin-top: 0.25rem; color: var(--bs-text-muted); font-size: 0.875rem; }

.tree-branches { display: grid; gap: 1rem; }
.tree-node-icon {
  display: grid;
  width: 2.4rem;
  height: 2.4rem;
  margin-bottom: 0.75rem;
  place-items: center;
  border-radius: var(--bs-radius-button);
  background: var(--bs-status-info-bg);
  color: var(--bs-primary);
}
.tree-node-engine .tree-node-icon { margin: 0; flex: none; background: rgb(255 255 255 / 0.12); color: var(--bs-white); }

.tree-pill {
  border: 1px solid var(--bs-border);
  border-radius: 999px;
  background: var(--bs-surface-muted);
  padding: 0.2rem 0.5rem;
  color: var(--bs-text-muted);
  font-size: 0.72rem;
}

.tree-callout {
  margin-top: 0.75rem;
  border-inline-start: 3px solid var(--bs-status-warning);
  padding-inline-start: 0.65rem;
  color: var(--bs-text);
  font-size: 0.78rem;
  font-weight: 600;
}

.tree-link {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  margin-top: 0.85rem;
  color: var(--bs-primary);
  font-size: 0.8rem;
  font-weight: 700;
}

.tree-merge,
.tree-split {
  position: relative;
  display: grid;
  height: 4.25rem;
  place-items: center;
  color: var(--bs-text-muted);
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
}

.tree-merge::before,
.tree-split::before {
  position: absolute;
  inset-block: 0;
  inset-inline-start: 50%;
  width: 2px;
  background: var(--bs-border-strong);
  content: '';
}

.tree-merge span,
.tree-split span { position: relative; z-index: 1; border-radius: 999px; background: var(--bs-bg); padding: 0.25rem 0.65rem; }

.tree-engine-check {
  display: flex;
  align-items: flex-start;
  gap: 0.5rem;
  border-radius: var(--bs-radius-button);
  background: rgb(255 255 255 / 0.08);
  padding: 0.65rem;
  font-size: 0.75rem;
}
.tree-engine-check > span { display: grid; min-width: 1.25rem; height: 1.25rem; place-items: center; border-radius: 999px; background: rgb(255 255 255 / 0.14); }

.tree-ledger-rule {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  margin-top: 1rem;
  border-radius: var(--bs-radius-button);
  background: var(--bs-status-info-bg);
  padding: 0.65rem;
  color: var(--bs-primary);
  font-size: 0.82rem;
  font-weight: 700;
}

.tree-result { min-height: 100%; transition: transform var(--bs-motion-quick), border-color var(--bs-motion-quick); }
.tree-result:hover { transform: translateY(-2px); border-color: var(--bs-primary); }

@media (min-width: 768px) {
  .tree-branches-three { grid-template-columns: repeat(3, minmax(0, 1fr)); }
  .tree-branches-four { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .tree-branches > .tree-node::before {
    position: absolute;
    inset-inline-start: 50%;
    inset-block-start: -1rem;
    width: 2px;
    height: 1rem;
    background: var(--bs-border-strong);
    content: '';
  }
}

@media (min-width: 1100px) {
  .tree-branches-four { grid-template-columns: repeat(4, minmax(0, 1fr)); }
}

@media (max-width: 767px) {
  .tree-branches { padding-inline-start: 1rem; border-inline-start: 2px solid var(--bs-border-strong); }
  .tree-branches > .tree-node::before { position: absolute; inset-inline-start: -1rem; inset-block-start: 2rem; width: 1rem; height: 2px; background: var(--bs-border-strong); content: ''; }
}

:lang(ar) .tree-step,
[dir='rtl'] .tree-step,
:lang(ar) .tree-merge,
[dir='rtl'] .tree-merge,
:lang(ar) .tree-split,
[dir='rtl'] .tree-split { text-transform: none; letter-spacing: normal; }
</style>

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
    class="financial-map-fab ls-btn ls-btn-primary fixed bottom-20 end-4 z-20 flex items-center gap-2 rounded-full px-5 py-3 font-bold shadow-raised lg:bottom-6 lg:end-6"
    :aria-label="t('financialMap.open')"
    @click="show"
  >
    <span class="financial-map-fab-icon" aria-hidden="true"><AppIcon name="chart" :size="22" /></span>
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
            <div class="financial-tree mx-auto max-w-[1180px] pb-8">
              <section aria-labelledby="financial-map-setup">
                <div class="tree-stage-heading tree-stage-heading-start">
                  <span class="tree-step">{{ t('financialMap.steps.setup') }}</span>
                  <h3 id="financial-map-setup">{{ t('financialMap.setup.title') }}</h3>
                  <p>{{ t('financialMap.setup.body') }}</p>
                </div>

                <ol class="tree-branches tree-branches-three tree-numbered">
                  <li class="tree-node tree-node-start">
                    <span class="tree-node-number">1.1</span>
                    <h3>{{ t('financialMap.setup.organization') }}</h3>
                    <p>{{ t('financialMap.setup.organizationHint') }}</p>
                  </li>
                  <li class="tree-node tree-node-start">
                    <span class="tree-node-number">1.2</span>
                    <h3>{{ t('financialMap.setup.accounts') }}</h3>
                    <p>{{ t('financialMap.setup.accountsHint') }}</p>
                    <NuxtLink to="/accounts" class="tree-link" @click="close">{{ t('financialMap.setup.reviewAccounts') }} <AppIcon name="arrowRight" :size="15" directional /></NuxtLink>
                  </li>
                  <li class="tree-node tree-node-start">
                    <span class="tree-node-number">1.3</span>
                    <h3>{{ t('financialMap.setup.categories') }}</h3>
                    <p>{{ t('financialMap.setup.categoriesHint') }}</p>
                    <NuxtLink to="/records/expense" class="tree-link" @click="close">{{ t('financialMap.setup.firstEntry') }} <AppIcon name="arrowRight" :size="15" directional /></NuxtLink>
                  </li>
                </ol>
              </section>

              <div class="tree-arrow" aria-hidden="true"><span>↓</span></div>

              <section aria-labelledby="financial-map-inputs">
                <div class="tree-stage-heading">
                  <span class="tree-step">{{ t('financialMap.steps.record') }}</span>
                  <h3 id="financial-map-inputs">{{ t('financialMap.sourcesTitle') }}</h3>
                  <p>{{ t('financialMap.sourcesHint') }}</p>
                </div>

                <div class="tree-branches tree-branches-three tree-numbered">
                  <article class="tree-node">
                    <span class="tree-node-number">2.1</span>
                    <div class="tree-node-icon"><AppIcon name="transactions" /></div>
                    <h3>{{ t('financialMap.manual.title') }}</h3>
                    <p>{{ t('financialMap.manual.body') }}</p>
                    <NuxtLink to="/transactions" class="tree-link" @click="close">{{ t('financialMap.manual.link') }} <AppIcon name="arrowRight" :size="15" directional /></NuxtLink>
                  </article>

                  <article class="tree-node tree-node-waiting">
                    <span class="tree-node-number">2.2</span>
                    <div class="tree-node-icon"><AppIcon name="invoice" /></div>
                    <h3>{{ t('financialMap.commitments.title') }}</h3>
                    <p>{{ t('financialMap.commitments.body') }}</p>
                    <div class="tree-callout">{{ t('financialMap.commitments.rule') }}</div>
                    <NuxtLink to="/records/commitments" class="tree-link" @click="close">{{ t('financialMap.commitments.link') }} <AppIcon name="arrowRight" :size="15" directional /></NuxtLink>
                  </article>

                  <article class="tree-node tree-node-waiting">
                    <span class="tree-node-number">2.3</span>
                    <div class="tree-node-icon"><AppIcon name="repeat" /></div>
                    <h3>{{ t('financialMap.recurring.title') }}</h3>
                    <p>{{ t('financialMap.recurring.body') }}</p>
                    <div class="tree-callout">{{ t('financialMap.recurring.rule') }}</div>
                    <NuxtLink to="/records/recurring" class="tree-link" @click="close">{{ t('financialMap.recurring.link') }} <AppIcon name="arrowRight" :size="15" directional /></NuxtLink>
                  </article>
                </div>

                <div class="tree-subbranch">
                  <p class="tree-subbranch-label">{{ t('financialMap.manual.flowsTitle') }}</p>
                  <ol class="tree-flow-branches">
                    <li v-for="(flow, index) in manualFlows" :key="flow" class="tree-pill">
                      <span>2.1.{{ index + 1 }}</span>
                      {{ t(`financialMap.manual.flows.${flow}`) }}
                    </li>
                  </ol>
                </div>
              </section>

              <div class="tree-merge" aria-hidden="true"><span>{{ t('financialMap.converges') }}</span></div>

              <section aria-labelledby="financial-map-engine">
                <div class="tree-stage-heading">
                  <span class="tree-step">{{ t('financialMap.steps.validate') }}</span>
                  <h3 id="financial-map-engine">{{ t('financialMap.engine.title') }}</h3>
                  <p>{{ t('financialMap.engine.body') }}</p>
                </div>

                <ol class="tree-check-path">
                  <li v-for="(check, index) in postingChecks" :key="check" class="tree-node tree-engine-check">
                    <span class="tree-check-number">3.{{ index + 1 }}</span>
                    <span>{{ t(`financialMap.engine.checks.${check}`) }}</span>
                  </li>
                </ol>
                <div class="tree-engine-result">
                  <AppIcon name="checkBadge" :size="22" />
                  <span>{{ t('financialMap.engine.result') }}</span>
                </div>
              </section>

              <div class="tree-arrow" aria-hidden="true"><span>↓</span></div>

              <section aria-labelledby="financial-map-ledger">
                <div class="tree-stage-heading">
                  <span class="tree-step">{{ t('financialMap.steps.ledger') }}</span>
                  <h3 id="financial-map-ledger">{{ t('financialMap.ledger.rule') }}</h3>
                </div>
                <div class="tree-branches tree-branches-two tree-numbered">
                  <article class="tree-node tree-node-ledger">
                    <span class="tree-node-number">4.1</span>
                    <p class="text-xs font-bold uppercase tracking-[0.12em] text-primary">{{ t('financialMap.ledger.eventLabel') }}</p>
                    <h3>{{ t('financialMap.ledger.event') }}</h3>
                    <p>{{ t('financialMap.ledger.eventHint') }}</p>
                  </article>
                  <article class="tree-node tree-node-ledger">
                    <span class="tree-node-number">4.2</span>
                    <p class="text-xs font-bold uppercase tracking-[0.12em] text-primary">{{ t('financialMap.ledger.linesLabel') }}</p>
                    <h3>{{ t('financialMap.ledger.lines') }}</h3>
                    <p>{{ t('financialMap.ledger.linesHint') }}</p>
                  </article>
                </div>
              </section>

              <div class="tree-split" aria-hidden="true"><span>{{ t('financialMap.resultsFrom') }}</span></div>

              <section aria-labelledby="financial-map-results">
                <div class="tree-stage-heading">
                  <span class="tree-step">{{ t('financialMap.steps.results') }}</span>
                  <h3 id="financial-map-results">{{ t('financialMap.resultsTitle') }}</h3>
                  <p>{{ t('financialMap.resultsHint') }}</p>
                </div>

                <div class="tree-branches tree-branches-four tree-numbered">
                  <NuxtLink to="/accounts" class="tree-node tree-result" @click="close">
                    <span class="tree-node-number">5.1</span>
                    <div class="tree-node-icon"><AppIcon name="wallet" /></div>
                    <h3>{{ t('financialMap.results.accounts.title') }}</h3>
                    <p>{{ t('financialMap.results.accounts.body') }}</p>
                    <span class="tree-link">{{ t('financialMap.results.open') }} <AppIcon name="arrowRight" :size="15" directional /></span>
                  </NuxtLink>
                  <NuxtLink to="/dashboard" class="tree-node tree-result" @click="close">
                    <span class="tree-node-number">5.2</span>
                    <div class="tree-node-icon"><AppIcon name="dashboard" /></div>
                    <h3>{{ t('financialMap.results.dashboard.title') }}</h3>
                    <p>{{ t('financialMap.results.dashboard.body') }}</p>
                    <span class="tree-link">{{ t('financialMap.results.open') }} <AppIcon name="arrowRight" :size="15" directional /></span>
                  </NuxtLink>
                  <NuxtLink to="/reports" class="tree-node tree-result" @click="close">
                    <span class="tree-node-number">5.3</span>
                    <div class="tree-node-icon"><AppIcon name="reports" /></div>
                    <h3>{{ t('financialMap.results.reports.title') }}</h3>
                    <p>{{ t('financialMap.results.reports.body') }}</p>
                    <div class="mt-2 flex flex-wrap gap-1.5"><span v-for="report in reports" :key="report" class="tree-pill">{{ t(`financialMap.results.reports.items.${report}`) }}</span></div>
                    <span class="tree-link">{{ t('financialMap.results.open') }} <AppIcon name="arrowRight" :size="15" directional /></span>
                  </NuxtLink>
                  <NuxtLink to="/transactions" class="tree-node tree-result" @click="close">
                    <span class="tree-node-number">5.4</span>
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
.financial-map-fab {
  isolation: isolate;
  box-shadow: var(--bs-elevation-3);
  transition: box-shadow var(--bs-motion-quick), transform var(--bs-motion-quick);
}

.financial-map-fab::before {
  position: absolute;
  z-index: -1;
  border: 2px solid var(--bs-primary);
  border-radius: inherit;
  opacity: 0;
  content: '';
  inset: -0.3rem;
  animation: financial-map-ring 3s ease-out infinite;
}

.financial-map-fab-icon { display: inline-flex; animation: financial-map-icon 3s ease-in-out infinite; }
.financial-map-fab:hover { transform: translateY(-3px); }
.financial-map-fab:hover::before,
.financial-map-fab:hover .financial-map-fab-icon { animation-play-state: paused; }

.tree-node {
  position: relative;
  display: block;
  border: 1px solid var(--bs-border);
  border-radius: var(--bs-radius-card);
  background: var(--bs-surface);
  padding: 1.25rem;
  box-shadow: var(--bs-elevation-1);
}

.tree-node h3 { font-weight: 700; }
.tree-node p { margin-top: 0.3rem; color: var(--bs-text-muted); font-size: 0.875rem; }

.tree-node-start { border-color: color-mix(in srgb, var(--bs-primary) 45%, var(--bs-border)); }
.tree-node-ledger { border-width: 2px; border-color: var(--bs-primary); }
.tree-node-waiting { border-style: dashed; }

.tree-node-number {
  position: absolute;
  inset-block-start: 0.85rem;
  inset-inline-end: 0.9rem;
  color: var(--bs-primary);
  font-size: 0.68rem;
  font-weight: 800;
  letter-spacing: 0.05em;
}

.tree-numbered .tree-node { padding-block-start: 2.7rem; }

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

.tree-arrow {
  display: grid;
  height: 5rem;
  place-items: center;
  color: var(--bs-primary);
  font-size: 1.5rem;
  font-weight: 700;
}

.tree-stage-heading { margin: 0 auto 2rem; max-width: 44rem; text-align: center; }
.tree-stage-heading-start { margin-top: 0.5rem; }
.tree-stage-heading .tree-step { margin-bottom: 0.35rem; }
.tree-stage-heading h3 { font-size: 1.1rem; font-weight: 700; }
.tree-stage-heading p { margin-top: 0.5rem; color: var(--bs-text-muted); font-size: 0.875rem; line-height: 1.7; }

.tree-branches { position: relative; display: grid; gap: 1.5rem; }
.tree-branches-two { grid-template-columns: repeat(2, minmax(0, 1fr)); }
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
.tree-pill {
  display: block;
  border: 1px solid var(--bs-border);
  border-radius: var(--bs-radius-button);
  background: var(--bs-surface-muted);
  padding: 0.45rem 0.6rem;
  color: var(--bs-text-muted);
  font-size: 0.72rem;
}

.tree-subbranch {
  position: relative;
  max-width: 58rem;
  margin: 2.5rem auto 0;
  padding-top: 1rem;
}

.tree-subbranch::before {
  position: absolute;
  inset-block-start: -2.5rem;
  inset-inline-start: 50%;
  width: 2px;
  height: 2.5rem;
  background: var(--bs-border-strong);
  content: '';
}

.tree-subbranch-label {
  position: relative;
  width: max-content;
  max-width: 100%;
  margin: 0 auto 1rem;
  border-radius: 999px;
  background: var(--bs-bg);
  padding: 0.25rem 0.65rem;
  color: var(--bs-text-muted);
  font-size: 0.72rem;
  font-weight: 700;
  text-align: center;
}

.tree-flow-branches { display: grid; gap: 0.6rem; grid-template-columns: repeat(2, minmax(0, 1fr)); }
.tree-flow-branches .tree-pill { position: relative; display: flex; align-items: center; gap: 0.5rem; }
.tree-flow-branches .tree-pill > span { color: var(--bs-primary); font-size: 0.65rem; font-weight: 800; }

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
  height: 5rem;
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

.tree-check-path {
  position: relative;
  display: grid;
  max-width: 48rem;
  margin-inline: auto;
  gap: 1rem;
}

.tree-check-path::before {
  position: absolute;
  inset-block: -2rem;
  inset-inline-start: 50%;
  width: 2px;
  background: var(--bs-border-strong);
  content: '';
}

.tree-engine-check {
  display: flex;
  width: calc(50% - 1.5rem);
  align-items: center;
  gap: 0.75rem;
  line-height: 1.5;
}

.tree-engine-check:nth-child(odd) { justify-self: start; }
.tree-engine-check:nth-child(even) { justify-self: end; }

.tree-engine-check::after {
  position: absolute;
  inset-block-start: 50%;
  width: 1.5rem;
  height: 2px;
  background: var(--bs-border-strong);
  content: '';
}

.tree-engine-check:nth-child(odd)::after { inset-inline-end: -1.5rem; }
.tree-engine-check:nth-child(even)::after { inset-inline-start: -1.5rem; }

.tree-check-number {
  display: flex;
  min-width: 2.3rem;
  height: 2.3rem;
  align-items: center;
  justify-content: center;
  border-radius: 999px;
  background: var(--bs-status-info-bg);
  color: var(--bs-primary);
  font-size: 0.7rem;
  font-weight: 800;
}

.tree-engine-result {
  position: relative;
  display: flex;
  max-width: 34rem;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  margin: 2rem auto 0;
  border-radius: var(--bs-radius-card);
  background: var(--bs-deep-structure-navy);
  padding: 1rem;
  color: var(--bs-white);
  font-size: 0.82rem;
  font-weight: 700;
  text-align: center;
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
  .tree-flow-branches { grid-template-columns: repeat(4, minmax(0, 1fr)); }
  .tree-subbranch { max-width: none; padding-top: 2rem; }
  .tree-subbranch::before { inset-inline-start: 16.666%; height: 3.25rem; }
  .tree-subbranch::after {
    position: absolute;
    inset-block-start: 0.75rem;
    inset-inline: 12.5%;
    height: 2px;
    background: var(--bs-border-strong);
    content: '';
  }
  .tree-subbranch-label { z-index: 1; }
  .tree-flow-branches .tree-pill::before {
    position: absolute;
    inset-block-start: -1.6rem;
    inset-inline-start: 50%;
    width: 2px;
    height: 1.6rem;
    background: var(--bs-border-strong);
    content: '';
  }
}

@media (max-width: 480px) {
  .tree-flow-branches { grid-template-columns: 1fr; }
}

@media (max-width: 767px) {
  .tree-branches-two { grid-template-columns: 1fr; }
  .tree-branches { padding-inline-start: 1rem; border-inline-start: 2px solid var(--bs-border-strong); }
  .tree-branches > .tree-node::before { position: absolute; inset-inline-start: -1rem; inset-block-start: 2rem; width: 1rem; height: 2px; background: var(--bs-border-strong); content: ''; }
  .tree-check-path { padding-inline-start: 1rem; }
  .tree-check-path::before { inset-inline-start: 0; }
  .tree-engine-check { width: 100%; }
  .tree-engine-check::after,
  .tree-engine-check:nth-child(odd)::after,
  .tree-engine-check:nth-child(even)::after { inset-inline-start: -1rem; width: 1rem; }
}

@keyframes financial-map-ring {
  0%, 55%, 100% { opacity: 0; transform: scale(1); }
  65% { opacity: 0.35; }
  85% { opacity: 0; transform: scale(1.12, 1.35); }
}

@keyframes financial-map-icon {
  0%, 45%, 100% { transform: rotate(0); }
  52% { transform: rotate(-8deg); }
  59% { transform: rotate(8deg); }
  66% { transform: rotate(0); }
}

@media (prefers-reduced-motion: reduce) {
  .financial-map-fab,
  .financial-map-fab::before,
  .financial-map-fab-icon { animation: none; }
}

:lang(ar) .tree-step,
[dir='rtl'] .tree-step,
:lang(ar) .tree-merge,
[dir='rtl'] .tree-merge,
:lang(ar) .tree-split,
[dir='rtl'] .tree-split { text-transform: none; letter-spacing: normal; }
</style>

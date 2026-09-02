<script setup lang="ts">
definePageMeta({ layout: false })

const { t } = useI18n()
const user = useSupabaseUser()
const { restore } = useTheme()

onMounted(restore)
useHead({ title: () => `${t('landing.title')} · ${t('app.name')}` })

const features = [
  { icon: '↗', key: 'cashflow' },
  { icon: '◎', key: 'ledger' },
  { icon: '◫', key: 'commitments' },
  { icon: '↻', key: 'automation' },
  { icon: '⌁', key: 'reports' },
  { icon: '◇', key: 'team' },
]
</script>

<template>
  <div class="min-h-dvh bg-background text-fg">
    <header class="sticky top-0 z-30 border-b border-[var(--bs-border)] bg-background/90 backdrop-blur-xl">
      <div class="mx-auto flex min-h-16 max-w-7xl items-center gap-4 px-4 lg:px-8">
        <NuxtLink to="/" class="text-lg font-black tracking-[-0.04em]" dir="ltr">
          Ledger Suit
          <span class="text-xs font-semibold" dir="ltr"> by Building Suit </span>
        </NuxtLink>
        <nav class="ms-auto hidden items-center gap-6 text-sm text-fg-muted md:flex" :aria-label="t('landing.navigation')">
          <a href="#features" class="hover:text-fg">{{ t('landing.navFeatures') }}</a>
          <a href="#workflow" class="hover:text-fg">{{ t('landing.navWorkflow') }}</a>
          <a href="#pricing" class="hover:text-fg">{{ t('landing.navPricing') }}</a>
        </nav>
        <SettingsMenu />
        <NuxtLink :to="user ? '/dashboard' : '/login'" class="ls-btn ls-btn-sm">{{ user ? t('landing.openApp') : t('auth.signIn') }}</NuxtLink>
        <NuxtLink v-if="!user" to="/signup" class="ls-btn ls-btn-primary ls-btn-sm">{{ t('landing.startTrial') }}</NuxtLink>
      </div>
    </header>

    <main>
      <section class="relative overflow-hidden border-b border-[var(--bs-border)]">
        <div class="ls-hero-grid absolute inset-0 opacity-40" aria-hidden="true" />
        <div class="relative mx-auto grid max-w-7xl items-center gap-14 px-4 py-20 lg:grid-cols-[1.05fr_.95fr] lg:px-8 lg:py-28">
          <div class="max-w-3xl">
            <p class="mb-5 text-xs font-bold uppercase tracking-[.22em] text-fg-muted">{{ t('landing.eyebrow') }}</p>
            <h1 class="text-4xl font-black leading-[1.08] tracking-[-.055em] sm:text-6xl">{{ t('landing.heroTitle') }}</h1>
            <p class="mt-6 max-w-2xl text-lg leading-8 text-fg-muted">{{ t('landing.heroBody') }}</p>
            <div class="mt-8 flex flex-wrap gap-3">
              <NuxtLink to="/signup" class="ls-btn ls-btn-primary">{{ t('landing.createWorkspace') }} <span aria-hidden="true">→</span></NuxtLink>
              <a href="#features" class="ls-btn">{{ t('landing.explore') }}</a>
            </div>
            <p class="mt-4 text-xs text-fg-muted">{{ t('landing.trialNote') }}</p>
          </div>

          <div class="relative">
            <div class="ls-card overflow-hidden p-3 shadow-overlay">
              <div class="flex items-center gap-2 border-b border-[var(--bs-border)] px-3 pb-3 text-xs text-fg-muted">
                <span class="h-2.5 w-2.5 rounded-full bg-fg" /><span class="h-2.5 w-2.5 rounded-full bg-[var(--bs-border-strong)]" /><span class="h-2.5 w-2.5 rounded-full bg-[var(--bs-border)]" />
                <span class="ms-auto">{{ t('landing.previewLabel') }}</span>
              </div>
              <div class="grid gap-3 p-3 sm:grid-cols-2">
                <div v-for="metric in ['cash','revenue','expenses','profit']" :key="metric" class="rounded-card border border-[var(--bs-border)] bg-surface-muted p-4">
                  <p class="text-xs text-fg-muted">{{ t(`landing.metrics.${metric}`) }}</p>
                  <p class="mt-2 text-2xl font-black" dir="ltr">{{ metric === 'cash' ? 'EGP 482,400' : metric === 'revenue' ? 'EGP 96,800' : metric === 'expenses' ? 'EGP 51,200' : 'EGP 45,600' }}</p>
                </div>
              </div>
              <div class="mx-3 mb-3 rounded-card border border-[var(--bs-border)] p-4">
                <div class="mb-5 flex items-center justify-between"><span class="font-bold">{{ t('landing.cashflowPreview') }}</span><span class="text-xs text-fg-muted">6 {{ t('landing.months') }}</span></div>
                <div class="flex h-32 items-end gap-3" aria-hidden="true">
                  <div v-for="height in [42, 68, 52, 84, 73, 96]" :key="height" class="flex flex-1 items-end gap-1"><span class="w-1/2 rounded-t-sm bg-fg" :style="{ height: `${height}%` }" /><span class="w-1/2 rounded-t-sm bg-[var(--bs-border-strong)]" :style="{ height: `${Math.max(24, height - 25)}%` }" /></div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section id="features" class="mx-auto max-w-7xl px-4 py-20 lg:px-8">
        <div class="max-w-2xl"><p class="text-xs font-bold uppercase tracking-[.2em] text-fg-muted">{{ t('landing.featuresEyebrow') }}</p><h2 class="mt-3 text-3xl font-black tracking-[-.04em]">{{ t('landing.featuresTitle') }}</h2><p class="mt-4 text-base text-fg-muted">{{ t('landing.featuresBody') }}</p></div>
        <div class="mt-10 grid gap-px overflow-hidden rounded-modal border border-[var(--bs-border)] bg-[var(--bs-border)] md:grid-cols-2 lg:grid-cols-3">
          <article v-for="feature in features" :key="feature.key" class="bg-surface p-7">
            <span class="grid h-10 w-10 place-items-center rounded-control bg-surface-muted text-lg" aria-hidden="true">{{ feature.icon }}</span>
            <h3 class="mt-5 text-lg font-bold">{{ t(`landing.features.${feature.key}.title`) }}</h3>
            <p class="mt-2 text-sm leading-6 text-fg-muted">{{ t(`landing.features.${feature.key}.body`) }}</p>
          </article>
        </div>
      </section>

      <section id="workflow" class="border-y border-[var(--bs-border)] bg-surface-muted">
        <div class="mx-auto max-w-7xl px-4 py-20 lg:px-8">
          <div class="grid gap-10 lg:grid-cols-3">
            <div><p class="text-xs font-bold uppercase tracking-[.2em] text-fg-muted">{{ t('landing.workflowEyebrow') }}</p><h2 class="mt-3 text-3xl font-black tracking-[-.04em]">{{ t('landing.workflowTitle') }}</h2></div>
            <ol class="grid gap-5 lg:col-span-2 sm:grid-cols-3">
              <li v-for="step in 3" :key="step" class="ls-card p-6"><span class="text-xs font-black text-fg-muted">0{{ step }}</span><h3 class="mt-4 font-bold">{{ t(`landing.workflow.${step}.title`) }}</h3><p class="mt-2 text-sm text-fg-muted">{{ t(`landing.workflow.${step}.body`) }}</p></li>
            </ol>
          </div>
        </div>
      </section>

      <section id="pricing" class="mx-auto max-w-5xl px-4 py-20 text-center lg:px-8">
        <p class="text-xs font-bold uppercase tracking-[.2em] text-fg-muted">{{ t('landing.pricingEyebrow') }}</p>
        <h2 class="mt-3 text-3xl font-black tracking-[-.04em]">{{ t('landing.pricingTitle') }}</h2>
        <div class="mx-auto mt-9 grid max-w-3xl gap-4 sm:grid-cols-2">
          <div class="ls-card p-7 text-start"><p class="font-bold">{{ t('billing.monthly') }}</p><p class="mt-3 text-3xl font-black">{{ t('billing.monthlyPrice') }}</p><p class="mt-3 text-sm text-fg-muted">{{ t('landing.priceMonthlyBody') }}</p></div>
          <div class="ls-card relative p-7 text-start"><span class="absolute end-4 top-4 rounded-full bg-fg px-3 py-1 text-xs font-bold text-background">{{ t('landing.bestValue') }}</span><p class="font-bold">{{ t('billing.yearly') }}</p><p class="mt-3 text-3xl font-black">{{ t('billing.yearlyPrice') }}</p><p class="mt-3 text-sm text-fg-muted">{{ t('landing.priceYearlyBody') }}</p></div>
        </div>
        <NuxtLink to="/signup" class="ls-btn ls-btn-primary mt-8">{{ t('landing.startTrial') }}</NuxtLink>
      </section>
    </main>

    <footer class="border-t border-[var(--bs-border)] py-8"><div class="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-4 px-4 text-xs text-fg-muted lg:px-8"><span dir="ltr">© 2026 Building Suit</span><span>{{ t('landing.footer') }}</span></div></footer>
  </div>
</template>

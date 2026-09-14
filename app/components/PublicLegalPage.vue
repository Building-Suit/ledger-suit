<script setup lang="ts">
import type { LegalDocument } from '~/utils/legal'

const props = defineProps<{
  document: LegalDocument
}>()

const { t } = useI18n()

useHead(() => ({
  title: `${props.document.title} · Ledger Suit`,
  meta: [{ name: 'description', content: props.document.intro }],
}))
</script>

<template>
  <main class="mx-auto max-w-5xl px-4 py-10 lg:px-8 lg:py-14">
    <article class="ls-card overflow-hidden">
        <div class="border-b border-[var(--bs-border)] bg-surface-muted px-6 py-8 sm:px-10">
          <p class="text-xs font-bold uppercase tracking-[.18em] text-brand-gold-highlight">
            Ledger Suit by Building Suit
          </p>
          <h1 class="mt-3 text-3xl font-black tracking-[-.04em] sm:text-4xl">
            {{ document.title }}
          </h1>
          <p class="mt-4 max-w-3xl text-sm leading-7 text-fg-muted sm:text-base">
            {{ document.intro }}
          </p>
          <p class="mt-4 text-xs text-fg-muted">
            {{ t('marketing.lastUpdated') }} {{ document.updated }}
          </p>
        </div>

        <div class="space-y-9 px-6 py-8 sm:px-10 sm:py-10">
          <section v-for="section in document.sections" :key="section.title">
            <h2 class="text-xl font-black tracking-[-.02em]">
              {{ section.title }}
            </h2>

            <div v-if="section.paragraphs?.length" class="mt-3 space-y-3">
              <p
                v-for="paragraph in section.paragraphs"
                :key="paragraph"
                class="text-sm leading-7 text-fg-muted sm:text-base"
              >
                {{ paragraph }}
              </p>
            </div>

            <ul v-if="section.bullets?.length" class="mt-3 space-y-2 ps-5 text-sm leading-7 text-fg-muted sm:text-base">
              <li v-for="bullet in section.bullets" :key="bullet" class="list-disc">
                {{ bullet }}
              </li>
            </ul>
          </section>
        </div>
    </article>
  </main>
</template>

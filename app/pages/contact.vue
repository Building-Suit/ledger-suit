<script setup lang="ts">
import { publicBusiness } from '~/utils/legal'

definePageMeta({ layout: 'marketing' })

const { t, locale } = useI18n()

useHead(() => ({
  title: `${t('marketing.contact')} · Ledger Suit`,
  meta: [
    {
      name: 'description',
      content: t('marketing.contactMetaDescription'),
    },
  ],
}))
</script>

<template>
  <main class="mx-auto max-w-5xl px-4 py-10 lg:px-8 lg:py-14">
    <section class="ls-card overflow-hidden">
        <div class="border-b border-[var(--bs-border)] bg-surface-muted px-6 py-8 sm:px-10">
          <p class="text-xs font-bold uppercase tracking-[.18em] text-brand-gold-highlight">
            Ledger Suit by Building Suit
          </p>
          <h1 class="mt-3 text-3xl font-black tracking-[-.04em] sm:text-4xl">
            {{ t('marketing.contact') }}
          </h1>
          <p class="mt-4 max-w-3xl text-sm leading-7 text-fg-muted sm:text-base">
            {{ t('marketing.contactIntro') }}
          </p>
        </div>

        <div class="grid gap-px bg-[var(--bs-border)] md:grid-cols-3">
          <div class="bg-surface p-6 sm:p-8">
            <p class="text-xs font-bold uppercase tracking-[.14em] text-fg-muted">
              {{ t('marketing.email') }}
            </p>
            <a :href="`mailto:${publicBusiness.supportEmail}`" class="mt-3 block break-all font-bold text-link" dir="ltr">
              {{ publicBusiness.supportEmail }}
            </a>
          </div>

          <div class="bg-surface p-6 sm:p-8">
            <p class="text-xs font-bold uppercase tracking-[.14em] text-fg-muted">
              {{ t('marketing.phone') }}
            </p>
            <a :href="`tel:${publicBusiness.phone}`" class="mt-3 block font-bold text-link" dir="ltr">
              {{ publicBusiness.phone }}
            </a>
          </div>

          <div class="bg-surface p-6 sm:p-8">
            <p class="text-xs font-bold uppercase tracking-[.14em] text-fg-muted">
              {{ t('marketing.businessAddress') }}
            </p>
            <p class="mt-3 font-bold">
              {{ locale === 'ar' ? publicBusiness.addressAr : publicBusiness.addressEn }}
            </p>
          </div>
        </div>

        <div class="px-6 py-8 sm:px-10">
          <h2 class="text-xl font-black">{{ t('marketing.businessIdentity') }}</h2>
          <p class="mt-3 text-sm leading-7 text-fg-muted sm:text-base">
            <i18n-t keypath="marketing.businessIdentityBody" tag="span" scope="global">
              <template #product><bdi dir="ltr">Ledger Suit</bdi></template>
              <template #parent><bdi dir="ltr">Building Suit</bdi></template>
            </i18n-t>
          </p>
        </div>
    </section>
  </main>
</template>

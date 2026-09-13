<script setup lang="ts">
import type { QuotaKey } from '~/composables/usePlanUsage'

const keys: QuotaKey[] = ['max_members', 'max_monthly_transactions', 'max_storage_bytes', 'max_accounts', 'max_counterparties', 'max_recurring_rules', 'max_custom_roles']
const { t } = useI18n()
const { rows, loading, loadError, refresh } = usePlanUsage()
</script>

<template>
  <section id="usage" class="ls-card p-6" aria-labelledby="usage-heading">
    <div class="flex items-start justify-between gap-3">
      <div><h2 id="usage-heading" class="text-lg font-bold">{{ t('usage.title') }}</h2><p class="mt-1 text-sm text-fg-muted">{{ t('usage.subtitle') }}</p></div>
      <button v-if="loadError" type="button" class="text-link" @click="refresh()">{{ t('common.retry') }}</button>
    </div>
    <p v-if="loading && !rows.length" class="mt-4 text-sm text-fg-muted" role="status">{{ t('usage.loading') }}</p>
    <p v-else-if="loadError && !rows.length" class="ls-error mt-4" role="alert">{{ t('usage.loadFailed') }}</p>
    <div v-else class="mt-5 grid gap-3 md:grid-cols-2 xl:grid-cols-3">
      <QuotaUsageMeter v-for="key in keys" :key="key" :quota-key="key" />
    </div>
  </section>
</template>

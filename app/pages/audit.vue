<script setup lang="ts">
import type { Database, Json } from '~~/types/database.types'

definePageMeta({ layout: 'default' })

interface AuditRow {
  id: number
  actor_id: string | null
  actor_email: string | null
  action: string
  entity_type: string
  entity_id: string | null
  before_state: Json | null
  after_state: Json | null
  metadata: Json
  created_at: string
}

interface AuditRpcClient {
  rpc(name: 'audit_history_window_days', args: { p_organization_id: string }): PromiseLike<{
    data: number | null
    error: unknown | null
  }>
  rpc(name: 'list_audit_history', args: {
    p_organization_id: string
    p_limit: number
    p_before_created_at?: string
    p_before_id?: number
  }): PromiseLike<{ data: AuditRow[] | null, error: unknown | null }>
}

const PAGE_SIZE = 50
const supabase = useSupabaseClient<Database>()
const auditRpc = supabase as unknown as AuditRpcClient
const { currentId, can } = useTenant()
const { t, te, locale } = useI18n()

useHead({ title: () => `${t('audit.title')} · ${t('app.name')}` })

const rows = shallowRef<AuditRow[]>([])
const windowDays = ref(0)
const loading = ref(true)
const loadingMore = ref(false)
const errorMessage = ref('')
const hasMore = ref(false)

function localizedPart(group: 'actions' | 'entities', value: string) {
  const key = `audit.${group}.${value}`
  return te(key) ? t(key) : value.replaceAll('_', ' ')
}

function activityLabel(row: AuditRow) {
  const [, verb = row.action] = row.action.split('.', 2)
  return localizedPart('actions', verb)
}

function entityLabel(value: string) {
  return localizedPart('entities', value)
}

function formatTimestamp(value: string) {
  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function jsonText(value: Json | null) {
  return JSON.stringify(value ?? {}, null, 2)
}

async function fetchRows(append = false) {
  if (!currentId.value || !can('audit.read')) {
    rows.value = []
    windowDays.value = 0
    loading.value = false
    return
  }

  if (append) loadingMore.value = true
  else {
    rows.value = []
    windowDays.value = 0
    loading.value = true
  }
  errorMessage.value = ''
  try {
    const last = append ? rows.value.at(-1) : null
    if (!append) {
      const windowResult = await auditRpc.rpc('audit_history_window_days', {
        p_organization_id: currentId.value,
      })
      if (windowResult.error) throw windowResult.error
      windowDays.value = Number(windowResult.data ?? 0)
    }

    const historyResult = await auditRpc.rpc('list_audit_history', {
      p_organization_id: currentId.value,
      p_limit: PAGE_SIZE,
      p_before_created_at: last?.created_at,
      p_before_id: last?.id,
    })
    if (historyResult.error) throw historyResult.error

    const next = (historyResult.data ?? []) as AuditRow[]
    rows.value = append ? [...rows.value, ...next] : next
    hasMore.value = next.length === PAGE_SIZE
  }
  catch {
    errorMessage.value = t('audit.loadFailed')
  }
  finally {
    loading.value = false
    loadingMore.value = false
  }
}

watch(currentId, () => fetchRows(), { immediate: true })
</script>

<template>
  <div class="space-y-6">
    <header>
      <h1 class="text-h1 font-bold">{{ t('audit.title') }}</h1>
      <p class="mt-1 text-sm text-fg-muted">{{ t('audit.subtitle') }}</p>
    </header>

    <section v-if="windowDays" class="ls-card space-y-1 p-4" role="status">
      <p class="font-semibold">{{ t('audit.window', { days: windowDays }) }}</p>
      <p class="text-sm text-fg-muted">{{ t('audit.stored') }}</p>
    </section>

    <p v-if="errorMessage" class="ls-error" role="alert">{{ errorMessage }}</p>
    <SectionSkeleton v-if="loading" variant="table" :rows="7" />
    <EmptyState v-else-if="!rows.length && !errorMessage" :title="t('audit.empty')" />

    <template v-else-if="rows.length">
      <div class="ls-card overflow-x-auto">
        <table class="ls-table">
          <thead>
            <tr>
              <th>{{ t('audit.date') }}</th>
              <th>{{ t('audit.actor') }}</th>
              <th>{{ t('audit.activity') }}</th>
              <th>{{ t('audit.record') }}</th>
              <th>{{ t('audit.changes') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in rows" :key="row.id">
              <td class="whitespace-nowrap">{{ formatTimestamp(row.created_at) }}</td>
              <td dir="ltr">{{ row.actor_email || t('audit.system') }}</td>
              <td>
                <p class="font-medium">{{ activityLabel(row) }}</p>
                <p class="text-xs text-fg-muted" dir="ltr">{{ row.action }}</p>
              </td>
              <td>
                <p>{{ entityLabel(row.entity_type) }}</p>
                <p v-if="row.entity_id" class="text-xs text-fg-muted" dir="ltr">{{ row.entity_id }}</p>
              </td>
              <td>
                <details>
                  <summary class="cursor-pointer text-link">{{ t('audit.viewChanges') }}</summary>
                  <div class="mt-3 grid min-w-80 gap-3 text-xs">
                    <div><p class="font-semibold">{{ t('audit.before') }}</p><pre class="mt-1 overflow-auto rounded-control bg-background p-2" dir="ltr">{{ jsonText(row.before_state) }}</pre></div>
                    <div><p class="font-semibold">{{ t('audit.after') }}</p><pre class="mt-1 overflow-auto rounded-control bg-background p-2" dir="ltr">{{ jsonText(row.after_state) }}</pre></div>
                    <div><p class="font-semibold">{{ t('audit.metadata') }}</p><pre class="mt-1 overflow-auto rounded-control bg-background p-2" dir="ltr">{{ jsonText(row.metadata) }}</pre></div>
                  </div>
                </details>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-if="hasMore" class="flex justify-center">
        <button type="button" class="ls-btn" :disabled="loadingMore" @click="fetchRows(true)">
          {{ t('audit.loadMore') }}
        </button>
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
import type { Database, Json } from '~~/types/database.types'
import { parseCsv } from '~/utils/csv'

definePageMeta({ layout: 'default' })

const supabase = useSupabaseClient<Database>()
const { currentId, can } = useTenant()
const { t, te } = useI18n()
const { data: importsEnabled, pending: featurePending } = usePlanFeature('imports')

useHead({ title: () => `${t('imports.title')} · ${t('app.name')}` })

interface Batch {
  id: string
  filename: string
  status: string
  total_rows: number
  valid_rows: number
  invalid_rows: number
  posted_rows: number
  duplicate_rows: number
  failed_rows: number
}
interface ImportRow {
  id: string
  row_number: number
  status: string
  raw_data: Record<string, string>
  error_code: string | null
  transaction_id: string | null
}
interface DisplayRow {
  id: string
  rowNumber: number
  status: string
  issue: string
  typeValue: string
  dateValue: string
  amountValue: string
}
type Phase = 'upload' | 'mapping' | 'validated' | 'results'
type BusyAction = '' | 'validating' | 'confirming'

const REQUIRED_FIELDS = ['type', 'date', 'amount', 'account', 'category'] as const
const OPTIONAL_FIELDS = ['description', 'reference', 'counterparty', 'currency', 'exchange_rate'] as const
const ALL_FIELDS = [...REQUIRED_FIELDS, ...OPTIONAL_FIELDS]
const METRICS = ['total_rows', 'valid_rows', 'invalid_rows', 'posted_rows', 'duplicate_rows', 'failed_rows'] as const

const phase = ref<Phase>('upload')
const busy = ref<BusyAction>('')
const filename = ref('')
const headers = ref<string[]>([])
const sourceRows = ref<Record<string, string>[]>([])
const mapping = reactive<Record<string, string>>(Object.fromEntries(ALL_FIELDS.map(field => [field, ''])))
const batch = ref<Batch | null>(null)
const resultRows = ref<ImportRow[]>([])
const errorMessage = ref('')

const previewRows = computed(() => sourceRows.value.slice(0, 5))
const requiredMappingComplete = computed(() => REQUIRED_FIELDS.every(field => mapping[field]))
const canConfirm = computed(() => Boolean(batch.value && (
  batch.value.valid_rows > 0
  || (batch.value.total_rows > 0 && batch.value.duplicate_rows === batch.value.total_rows)
)))
const steps = computed(() => [
  { key: 'upload', done: phase.value !== 'upload' },
  { key: 'mapping', done: ['validated', 'results'].includes(phase.value) },
  { key: 'validation', done: ['validated', 'results'].includes(phase.value) },
  { key: 'confirmation', done: phase.value === 'results' },
  { key: 'results', done: phase.value === 'results' },
])
const displayRows = computed<DisplayRow[]>(() => resultRows.value.map((row) => {
  const raw = row.raw_data
  return {
    id: row.id,
    rowNumber: row.row_number,
    status: row.status,
    issue: localizedIssue(row.error_code),
    typeValue: mapping.type ? (raw[mapping.type] ?? '') : '',
    dateValue: mapping.date ? (raw[mapping.date] ?? '') : '',
    amountValue: mapping.amount ? (raw[mapping.amount] ?? '') : '',
  }
}))

function isRequiredField(field: string) {
  return REQUIRED_FIELDS.some(required => required === field)
}

function localizedIssue(errorCode: string | null) {
  if (!errorCode) return ''
  const key = `imports.issues.${errorCode}`
  return te(key) ? t(key) : t('imports.issues.generic')
}

function reset() {
  phase.value = 'upload'
  busy.value = ''
  filename.value = ''
  headers.value = []
  sourceRows.value = []
  batch.value = null
  resultRows.value = []
  errorMessage.value = ''
  for (const field of ALL_FIELDS) mapping[field] = ''
}

function readableError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error)
  if (message.includes('CSV_NO_DATA')) return t('imports.errors.noData')
  if (message.includes('CSV_HEADERS_INVALID')) return t('imports.errors.headers')
  if (message.includes('CSV_ROW_WIDTH_INVALID')) return t('imports.errors.rowWidth')
  if (message.includes('CSV_UNCLOSED_QUOTE')) return t('imports.errors.quote')
  if (message.includes('CSV_FILE_INVALID')) return t('imports.errors.file')
  if (message.includes('FEATURE_NOT_AVAILABLE_ON_PLAN')) return t('imports.errors.entitlement')
  return t('imports.errors.generic')
}

async function onFileSelected(event: Event) {
  reset()
  const file = (event.target as HTMLInputElement).files?.[0]
  if (!file) return
  try {
    if (!file.name.toLowerCase().endsWith('.csv') || file.size > 5 * 1024 * 1024) {
      throw new Error('CSV_FILE_INVALID')
    }
    const parsed = parseCsv(await file.text())
    if (parsed.rows.length > 10_000) throw new Error('CSV_FILE_INVALID')
    filename.value = file.name
    headers.value = parsed.headers
    sourceRows.value = parsed.rows
    for (const field of ALL_FIELDS) {
      mapping[field] = parsed.headers.find(header => header.toLowerCase() === field) ?? ''
    }
    phase.value = 'mapping'
  }
  catch (error) {
    errorMessage.value = readableError(error)
  }
}

async function loadBatch(batchId: string) {
  const [batchResult, rowsResult] = await Promise.all([
    supabase.from('import_batches').select('*').eq('id', batchId).single(),
    supabase.from('import_rows')
      .select('id,row_number,status,raw_data,error_code,transaction_id')
      .eq('batch_id', batchId).order('row_number').range(0, 99),
  ])
  if (batchResult.error) throw batchResult.error
  if (rowsResult.error) throw rowsResult.error
  batch.value = batchResult.data
  resultRows.value = (rowsResult.data ?? []) as unknown as ImportRow[]
}

async function validateImport() {
  if (!currentId.value || !requiredMappingComplete.value || busy.value) return
  busy.value = 'validating'
  errorMessage.value = ''
  try {
    const { data: batchId, error: createError } = await supabase.rpc('create_csv_import_batch', {
      p_organization_id: currentId.value,
      p_filename: filename.value,
      p_rows: sourceRows.value as Json,
    })
    if (createError) throw createError

    const selectedMapping = Object.fromEntries(
      ALL_FIELDS.filter(field => mapping[field]).map(field => [field, mapping[field]]),
    )
    const { error: validationError } = await supabase.rpc('validate_csv_import_batch', {
      p_batch_id: batchId,
      p_mapping: selectedMapping,
    })
    if (validationError) throw validationError
    await loadBatch(batchId)
    phase.value = 'validated'
  }
  catch (error) {
    errorMessage.value = readableError(error)
  }
  finally {
    busy.value = ''
  }
}

async function confirmImport() {
  if (!batch.value || busy.value) return
  busy.value = 'confirming'
  errorMessage.value = ''
  try {
    const { error } = await supabase.rpc('confirm_csv_import_batch', { p_batch_id: batch.value.id })
    if (error) throw error
    await loadBatch(batch.value.id)
    phase.value = 'results'
  }
  catch (error) {
    errorMessage.value = readableError(error)
  }
  finally {
    busy.value = ''
  }
}
</script>

<template>
  <div class="space-y-6">
    <header>
      <p class="text-sm font-semibold text-accent">{{ t('imports.eyebrow') }}</p>
      <h1 class="text-h1 font-bold">{{ t('imports.title') }}</h1>
      <p class="mt-1 max-w-2xl text-sm text-fg-muted">{{ t('imports.subtitle') }}</p>
    </header>

    <SectionSkeleton v-if="featurePending" variant="cards" />

    <div v-else-if="!can('imports.create')" class="ls-card p-6">
      <h2 class="font-semibold">{{ t('imports.noPermissionTitle') }}</h2>
      <p class="mt-2 text-sm text-fg-muted">{{ t('imports.noPermissionBody') }}</p>
    </div>

    <div v-else-if="!importsEnabled" class="ls-card p-6">
      <h2 class="font-semibold">{{ t('imports.upgradeTitle') }}</h2>
      <p class="mt-2 text-sm text-fg-muted">{{ t('imports.upgradeBody') }}</p>
      <NuxtLink v-if="can('billing.manage')" to="/billing" class="ls-btn ls-btn-accent mt-5">
        {{ t('imports.viewPlans') }}
      </NuxtLink>
    </div>

    <template v-else>
      <ol class="grid gap-2 sm:grid-cols-5" :aria-label="t('imports.progress')">
        <li
          v-for="(step, index) in steps"
          :key="step.key"
          class="rounded-control border px-3 py-2 text-sm"
          :class="step.done ? 'border-[var(--bs-status-success)] bg-[var(--bs-status-success-bg)]' : 'border-[var(--bs-border)] text-fg-muted'"
        >
          <span class="font-semibold">{{ index + 1 }}</span> · {{ t(`imports.steps.${step.key}`) }}
        </li>
      </ol>

      <p v-if="errorMessage" class="ls-error" role="alert">{{ errorMessage }}</p>

      <section v-if="phase === 'upload'" class="ls-card p-6">
        <h2 class="text-h2 font-bold">{{ t('imports.uploadTitle') }}</h2>
        <p class="mt-2 text-sm text-fg-muted">{{ t('imports.uploadHint') }}</p>
        <label class="ls-btn ls-btn-accent mt-5 cursor-pointer" for="csv-file">
          {{ t('imports.chooseFile') }}
        </label>
        <input id="csv-file" class="sr-only" type="file" accept=".csv,text/csv" @change="onFileSelected">
        <p class="mt-4 text-xs text-fg-muted">{{ t('imports.formatHint') }}</p>
      </section>

      <template v-else>
        <section v-if="phase === 'mapping'" class="ls-card p-6">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 class="text-h2 font-bold">{{ t('imports.mappingTitle') }}</h2>
              <p class="mt-1 text-sm text-fg-muted">{{ t('imports.fileSummary', { filename, count: sourceRows.length }) }}</p>
            </div>
            <button type="button" class="ls-btn ls-btn-sm" @click="reset">{{ t('imports.changeFile') }}</button>
          </div>
          <div class="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <FloatingField v-for="field in ALL_FIELDS" :key="field" :label="t(`imports.fields.${field}`)">
              <select v-model="mapping[field]" class="ls-input" :aria-required="isRequiredField(field)">
                <option value="">{{ isRequiredField(field) ? t('imports.selectColumn') : t('common.none') }}</option>
                <option v-for="header in headers" :key="header" :value="header" :disabled="Object.values(mapping).includes(header) && mapping[field] !== header">{{ header }}</option>
              </select>
            </FloatingField>
          </div>
        </section>

        <section v-if="phase === 'mapping'" class="ls-card overflow-hidden">
          <div class="p-4"><h2 class="font-semibold">{{ t('imports.previewTitle') }}</h2></div>
          <div class="overflow-x-auto">
            <table class="ls-table">
              <thead><tr><th v-for="header in headers" :key="header">{{ header }}</th></tr></thead>
              <tbody><tr v-for="(row, index) in previewRows" :key="index"><td v-for="header in headers" :key="header">{{ row[header] || t('common.dash') }}</td></tr></tbody>
            </table>
          </div>
          <div class="flex justify-end border-t border-[var(--bs-border)] p-4">
            <button type="button" class="ls-btn ls-btn-accent" :disabled="!requiredMappingComplete || !!busy" @click="validateImport">
              {{ busy === 'validating' ? t('imports.validating') : t('imports.validate') }}
            </button>
          </div>
        </section>

        <section v-if="batch && (phase === 'validated' || phase === 'results')" class="space-y-4">
          <div class="ls-card p-6">
            <div class="flex flex-wrap items-start justify-between gap-4">
              <div>
                <h2 class="text-h2 font-bold">{{ phase === 'results' ? t('imports.resultsTitle') : t('imports.validationTitle') }}</h2>
                <p class="mt-1 text-sm text-fg-muted">{{ filename }}</p>
              </div>
              <StatusBadge :status="batch.status" />
            </div>
            <dl class="mt-5 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
              <div v-for="metric in METRICS" :key="metric" class="rounded-control bg-surface-muted p-3">
                <dt class="text-xs text-fg-muted">{{ t(`imports.metrics.${metric}`) }}</dt>
                <dd class="mt-1 text-xl font-bold">{{ batch[metric] }}</dd>
              </div>
            </dl>
            <div class="mt-5 flex flex-wrap justify-end gap-2">
              <button v-if="phase === 'results'" type="button" class="ls-btn" @click="reset">{{ t('imports.importAnother') }}</button>
              <button v-else type="button" class="ls-btn" :disabled="!!busy" @click="reset">{{ t('imports.startOver') }}</button>
              <button v-if="phase === 'validated' && canConfirm" type="button" class="ls-btn ls-btn-accent" :disabled="!!busy" @click="confirmImport">
                {{ busy === 'confirming' ? t('imports.confirming') : t('imports.confirm') }}
              </button>
            </div>
          </div>

          <div class="ls-card overflow-hidden">
            <div class="overflow-x-auto">
              <table class="ls-table">
                <caption class="sr-only">{{ t('imports.rowsCaption') }}</caption>
                <thead>
                  <tr>
                    <th>{{ t('imports.row') }}</th>
                    <th>{{ t('transactions.status') }}</th>
                    <th>{{ t('transactions.type') }}</th>
                    <th>{{ t('transactions.date') }}</th>
                    <th>{{ t('transactions.amount') }}</th>
                    <th>{{ t('imports.issue') }}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="row in displayRows" :key="row.id">
                    <td>{{ row.rowNumber }}</td>
                    <td><StatusBadge :status="row.status" /></td>
                    <td>{{ row.typeValue }}</td>
                    <td>{{ row.dateValue }}</td>
                    <td>{{ row.amountValue }}</td>
                    <td class="max-w-80 text-xs text-fg-muted">{{ row.issue || t('common.dash') }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p v-if="batch.total_rows > resultRows.length" class="border-t border-[var(--bs-border)] p-3 text-xs text-fg-muted">{{ t('imports.firstRows', { count: resultRows.length }) }}</p>
          </div>
        </section>
      </template>
    </template>
  </div>
</template>

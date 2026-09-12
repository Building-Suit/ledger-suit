import { expect, test } from '@playwright/test'
import type { Page } from '@playwright/test'

const batchId = '91000000-0000-4000-8000-000000000001'
type Scenario = 'mixed' | 'all-invalid' | 'all-duplicate'

async function signIn(page: Page) {
  await page.goto('/login')
  await expect(page.locator('form')).toHaveAttribute('data-hydrated', 'true')
  await page.getByLabel('Email').fill('owner@alpha.test')
  await page.getByLabel('Password').fill('ledgersuit')
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  await expect(page).toHaveURL('/dashboard')
}

async function openImport(page: Page) {
  await signIn(page)
  await page.getByRole('link', { name: 'Import CSV' }).click()
  await expect(page).toHaveURL('/imports')
}

async function selectCsv(page: Page, rows: string) {
  await page.locator('#csv-file').setInputFiles({
    name: 'transactions.csv',
    mimeType: 'text/csv',
    buffer: Buffer.from(`type,date,amount,account,category\n${rows}`),
  })
  await expect(page.getByRole('heading', { name: 'Match CSV columns' })).toBeVisible()
  await page.getByRole('button', { name: 'Stage and validate' }).click()
  await expect(page.getByRole('heading', { name: 'Validation complete' })).toBeVisible()
}

async function mockImportApi(page: Page, scenario: Scenario) {
  const state = { confirmed: false, confirmCalls: 0 }
  const sourceRows = scenario === 'mixed'
    ? [
        { id: '1', row_number: 1, status: state.confirmed ? 'posted' : 'valid', raw_data: { type: 'income', date: '2026-09-01', amount: '100', account: 'Cash', category: 'Sales' }, error_code: null, error_message: null, transaction_id: state.confirmed ? 'tx-1' : null },
        { id: '2', row_number: 2, status: 'invalid', raw_data: { type: 'expense', date: 'bad-date', amount: '20', account: 'Cash', category: 'Supplies' }, error_code: 'IMPORT_ROW_DATE_INVALID', error_message: 'IMPORT_ROW_DATE_INVALID: raw backend detail', transaction_id: null },
        { id: '3', row_number: 3, status: 'duplicate', raw_data: { type: 'income', date: '2026-09-01', amount: '100', account: 'Cash', category: 'Sales' }, error_code: 'IMPORT_ROW_DUPLICATE', error_message: 'Raw duplicate backend detail.', transaction_id: null },
      ]
    : scenario === 'all-invalid'
      ? [{ id: '1', row_number: 1, status: 'invalid', raw_data: { type: 'expense', date: 'bad-date', amount: '20', account: 'Cash', category: 'Supplies' }, error_code: 'IMPORT_ROW_DATE_INVALID', error_message: 'IMPORT_ROW_DATE_INVALID: raw backend detail', transaction_id: null }]
      : [{ id: '1', row_number: 1, status: 'duplicate', raw_data: { type: 'income', date: '2026-09-01', amount: '100', account: 'Cash', category: 'Sales' }, error_code: 'IMPORT_ROW_DUPLICATE', error_message: 'Raw duplicate backend detail.', transaction_id: null }]

  await page.route('**/rest/v1/rpc/can_use_feature**', route => route.fulfill({ status: 200, contentType: 'application/json', body: 'true' }))
  await page.route('**/rest/v1/rpc/create_csv_import_batch', route => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(batchId) }))
  await page.route('**/rest/v1/rpc/validate_csv_import_batch', route => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(batchId) }))
  await page.route('**/rest/v1/rpc/confirm_csv_import_batch', async (route) => {
    state.confirmed = true
    state.confirmCalls++
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ batch_id: batchId, status: scenario === 'all-duplicate' ? 'completed' : 'partial' }) })
  })
  await page.route('**/rest/v1/import_batches?*', route => route.fulfill({
    status: 200,
    contentType: 'application/vnd.pgrst.object+json',
    body: JSON.stringify({
      id: batchId,
      filename: 'transactions.csv',
      status: state.confirmed ? (scenario === 'all-duplicate' ? 'completed' : 'partial') : 'validated',
      total_rows: sourceRows.length,
      valid_rows: scenario === 'mixed' && !state.confirmed ? 1 : 0,
      invalid_rows: scenario === 'mixed' ? 1 : scenario === 'all-invalid' ? 1 : 0,
      posted_rows: scenario === 'mixed' && state.confirmed ? 1 : 0,
      duplicate_rows: scenario === 'mixed' || scenario === 'all-duplicate' ? 1 : 0,
      failed_rows: 0,
    }),
  }))
  await page.route('**/rest/v1/import_rows?*', route => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify(sourceRows.map(row => scenario === 'mixed' && row.id === '1'
      ? { ...row, status: state.confirmed ? 'posted' : 'valid', transaction_id: state.confirmed ? 'tx-1' : null }
      : row)),
  }))

  return state
}

test('CSV workflow localizes invalid and duplicate issues, then posts valid rows', async ({ page }) => {
  await mockImportApi(page, 'mixed')
  await openImport(page)
  await expect(page.locator('html')).toHaveAttribute('dir', 'ltr')
  await selectCsv(page, 'income,2026-09-01,100,Cash,Sales\nexpense,bad-date,20,Cash,Supplies\nincome,2026-09-01,100,Cash,Sales')

  await expect(page.getByRole('row').filter({ hasText: 'bad-date' })).toContainText('Use a valid calendar date in YYYY-MM-DD format.')
  await expect(page.getByRole('row').filter({ hasText: '2026-09-01' }).last()).toContainText('An identical transaction already exists.')
  await expect(page.getByText('raw backend detail', { exact: false })).toHaveCount(0)
  await page.getByRole('button', { name: 'Confirm and post valid rows' }).click()
  await expect(page.getByRole('heading', { name: 'Import results' })).toBeVisible()
  await expect(page.getByRole('row').filter({ hasText: '2026-09-01' }).first()).toContainText('Posted')
})

test('all-invalid validation offers recovery and shows a localized issue under RTL', async ({ page }) => {
  await mockImportApi(page, 'all-invalid')
  await openImport(page)
  await selectCsv(page, 'expense,bad-date,20,Cash,Supplies')

  await expect(page.getByRole('button', { name: 'Confirm and post valid rows' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Start over' })).toBeVisible()
  await page.getByRole('button', { name: 'Account menu' }).click()
  await page.getByRole('button', { name: 'العربية' }).click()
  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl')
  await expect(page.getByText('استخدم تاريخًا صحيحًا بالصيغة YYYY-MM-DD.')).toBeVisible()
  await expect(page.getByText('raw backend detail', { exact: false })).toHaveCount(0)
  await page.getByRole('button', { name: 'البدء من جديد' }).click()
  await expect(page.locator('#csv-file')).toBeAttached()
})

test('all-duplicate validation can be confirmed to a completed result', async ({ page }) => {
  const state = await mockImportApi(page, 'all-duplicate')
  await openImport(page)
  await selectCsv(page, 'income,2026-09-01,100,Cash,Sales')

  await expect(page.getByRole('button', { name: 'Start over' })).toBeVisible()
  await expect(page.getByText('An identical transaction already exists.')).toBeVisible()
  await page.getByRole('button', { name: 'Confirm and post valid rows' }).click()
  await expect(page.getByRole('heading', { name: 'Import results' })).toBeVisible()
  await expect(page.getByText('Completed', { exact: true })).toBeVisible()
  expect(state.confirmCalls).toBe(1)
})

test('Solo sees an upgrade gate', async ({ page }) => {
  await page.route('**/rest/v1/rpc/can_use_feature**', route => route.fulfill({ status: 200, contentType: 'application/json', body: 'false' }))
  await openImport(page)
  await expect(page.getByRole('heading', { name: 'CSV imports are available on Starter and Business' })).toBeVisible()
  await expect(page.getByLabel('Choose CSV file')).toHaveCount(0)
})

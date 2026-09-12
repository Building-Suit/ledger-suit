import { expect, test } from '@playwright/test'
import type { Page } from '@playwright/test'

const batchId = '91000000-0000-4000-8000-000000000001'

async function signIn(page: Page) {
  await page.goto('/login')
  await expect(page.locator('form')).toHaveAttribute('data-hydrated', 'true')
  await page.getByLabel('Email').fill('owner@alpha.test')
  await page.getByLabel('Password').fill('ledgersuit')
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  await expect(page).toHaveURL('/dashboard')
}

test('CSV workflow previews, validates, identifies invalid and duplicate rows, then posts valid rows', async ({ page }) => {
  let confirmed = false
  await page.route('**/rest/v1/rpc/can_use_feature**', route => route.fulfill({ status: 200, contentType: 'application/json', body: 'true' }))
  await page.route('**/rest/v1/rpc/create_csv_import_batch', route => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(batchId) }))
  await page.route('**/rest/v1/rpc/validate_csv_import_batch', route => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(batchId) }))
  await page.route('**/rest/v1/rpc/confirm_csv_import_batch', async (route) => {
    confirmed = true
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ batch_id: batchId, status: 'partial' }) })
  })
  await page.route('**/rest/v1/import_batches?*', route => route.fulfill({
    status: 200,
    contentType: 'application/vnd.pgrst.object+json',
    body: JSON.stringify({
      id: batchId,
      organization_id: '10000000-0000-4000-8000-000000000001',
      filename: 'transactions.csv',
      status: confirmed ? 'partial' : 'validated',
      mapping: {},
      total_rows: 3,
      valid_rows: confirmed ? 0 : 1,
      invalid_rows: 1,
      posted_rows: confirmed ? 1 : 0,
      duplicate_rows: 1,
      failed_rows: 0,
      created_by: null,
      confirmed_by: null,
      created_at: '2026-09-12T00:00:00Z',
      updated_at: '2026-09-12T00:00:00Z',
      validated_at: '2026-09-12T00:00:00Z',
      confirmed_at: confirmed ? '2026-09-12T00:01:00Z' : null,
    }),
  }))
  await page.route('**/rest/v1/import_rows?*', route => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify([
      { id: '1', row_number: 1, status: confirmed ? 'posted' : 'valid', raw_data: { type: 'income', date: '2026-09-01', amount: '100', account: 'Cash', category: 'Sales' }, error_code: null, error_message: null, transaction_id: confirmed ? 'tx-1' : null },
      { id: '2', row_number: 2, status: 'invalid', raw_data: { type: 'expense', date: 'bad-date', amount: '20', account: 'Cash', category: 'Supplies' }, error_code: 'IMPORT_ROW_DATE_INVALID', error_message: 'IMPORT_ROW_DATE_INVALID: use YYYY-MM-DD', transaction_id: null },
      { id: '3', row_number: 3, status: 'duplicate', raw_data: { type: 'income', date: '2026-09-01', amount: '100', account: 'Cash', category: 'Sales' }, error_code: 'IMPORT_ROW_DUPLICATE', error_message: 'An identical row already exists.', transaction_id: null },
    ]),
  }))

  await signIn(page)
  await page.getByRole('link', { name: 'Import CSV' }).click()
  await expect(page).toHaveURL('/imports')
  await expect(page.locator('html')).toHaveAttribute('dir', 'ltr')
  await page.locator('#csv-file').setInputFiles({
    name: 'transactions.csv',
    mimeType: 'text/csv',
    buffer: Buffer.from('type,date,amount,account,category\nincome,2026-09-01,100,Cash,Sales\nexpense,bad-date,20,Cash,Supplies\nincome,2026-09-01,100,Cash,Sales'),
  })
  await expect(page.getByRole('heading', { name: 'Match CSV columns' })).toBeVisible()
  await expect(page.getByRole('table').first()).toContainText('Sales')
  await page.getByRole('button', { name: 'Stage and validate' }).click()
  await expect(page.getByRole('heading', { name: 'Validation complete' })).toBeVisible()
  await expect(page.getByRole('row').filter({ hasText: 'bad-date' })).toContainText('Invalid')
  await expect(page.getByRole('row').filter({ hasText: 'An identical row already exists.' })).toContainText('Duplicate')
  await page.getByRole('button', { name: 'Confirm and post valid rows' }).click()
  await expect(page.getByRole('heading', { name: 'Import results' })).toBeVisible()
  await expect(page.getByRole('row').filter({ hasText: '2026-09-01' }).first()).toContainText('Posted')
})

test('Solo sees an upgrade gate and the localized workflow mirrors in Arabic', async ({ page }) => {
  await page.route('**/rest/v1/rpc/can_use_feature**', route => route.fulfill({ status: 200, contentType: 'application/json', body: 'false' }))
  await signIn(page)
  await page.getByRole('link', { name: 'Import CSV' }).click()
  await expect(page).toHaveURL('/imports')
  await expect(page.getByRole('heading', { name: 'CSV imports are available on Starter and Business' })).toBeVisible()
  await expect(page.getByLabel('Choose CSV file')).toHaveCount(0)

  await page.getByRole('button', { name: 'Account menu' }).click()
  await page.getByRole('button', { name: 'العربية' }).click()
  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl')
  await expect(page.getByRole('heading', { name: 'استيراد CSV متاح في خطتي Starter وBusiness' })).toBeVisible()
})

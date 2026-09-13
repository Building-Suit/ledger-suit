import { expect, test } from '@playwright/test'

test.beforeEach(async ({ page }) => {
  await page.goto('/login')
  await expect(page.locator('form')).toHaveAttribute('data-hydrated', 'true')
  await page.getByLabel('Email').fill('owner@alpha.test')
  await page.getByLabel('Password').fill('ledgersuit')
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  await expect(page).toHaveURL('/dashboard')
})

test('owner can download every advertised financial report as CSV', async ({ page }) => {
  const requestedReports: string[] = []
  await page.route('**/rest/v1/accounts?*', route => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify([{
      organization_id: '00000000-0000-4000-8000-000000000001',
      id: '00000000-0000-4000-8000-000000000002',
      code: '1010',
      name: 'Bank',
      type: 'asset',
      subtype: 'bank',
      currency: 'EGP',
      is_liquid: true,
      is_archived: false,
      is_system: true,
      system_key: 'bank',
      parent_account_id: null,
    }]),
  }))
  await page.route('**/rest/v1/rpc/export_financial_report_csv', async (route) => {
    requestedReports.push(route.request().postDataJSON().p_report)
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify('section,account_name,amount,currency\nrevenue,"إيراد, نقدي",100.00,EGP'),
    })
  })

  await page.getByRole('link', { name: 'Reports' }).click()
  await expect(page.getByRole('heading', { name: 'Reports' })).toBeVisible()

  const exportFrom = async (panelName: string, filename: RegExp) => {
    const button = page.getByRole('tabpanel', { name: panelName }).getByRole('button', { name: 'Export CSV' })
    await expect(button).toBeEnabled()
    const downloadPromise = page.waitForEvent('download')
    await button.click()
    const download = await downloadPromise
    expect(download.suggestedFilename()).toMatch(filename)
  }

  await exportFrom('Overview', /^trial-balance-\d{4}-\d{2}-\d{2}\.csv$/)

  await page.getByRole('tab', { name: 'Profit & Loss' }).click()
  await exportFrom('Profit & Loss', /^profit-and-loss-.*\.csv$/)

  await page.getByRole('tab', { name: 'Balance Sheet' }).click()
  await exportFrom('Balance Sheet', /^balance-sheet-.*\.csv$/)

  await page.getByRole('tab', { name: 'Cash Flow' }).click()
  await exportFrom('Cash Flow', /^cash-flow-.*\.csv$/)

  await page.getByRole('tab', { name: 'Ledger', exact: true }).click()
  await exportFrom('Ledger', /^general-ledger-.*\.csv$/)

  expect(requestedReports).toEqual([
    'trial_balance',
    'profit_loss',
    'balance_sheet',
    'cash_flow',
    'general_ledger',
  ])
})

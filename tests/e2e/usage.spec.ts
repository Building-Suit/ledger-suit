import { expect, test, type Page } from '@playwright/test'

const usageRows = [
  ['max_members', 2, 3],
  ['max_monthly_transactions', 2000, 2500],
  ['max_storage_bytes', 5100273664, 5368709120],
  ['max_accounts', 100, 100],
  ['max_counterparties', 671, 1000],
  ['max_recurring_rules', 17, 25],
  ['max_custom_roles', 2, 3],
].map(([quota_key, used_value, limit_value]) => ({
  plan_key: 'starter',
  subscription_status: 'active',
  writes_allowed: true,
  quota_key,
  used_value,
  limit_value,
  remaining_value: Math.max(Number(limit_value) - Number(used_value), 0),
  is_unlimited: false,
  is_at_limit: Number(used_value) >= Number(limit_value),
  is_over_limit: Number(used_value) > Number(limit_value),
}))

async function mockUsage(page: Page, rows: () => typeof usageRows = () => usageRows) {
  await page.route('**/rest/v1/rpc/subscription_usage_summary', route => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify(rows()),
  }))
}

async function signIn(page: Page, arabic = false) {
  await page.goto('/login')
  await expect(page.locator('form')).toHaveAttribute('data-hydrated', 'true')
  await page.getByLabel(arabic ? 'البريد الإلكتروني' : 'Email').fill('owner@alpha.test')
  await page.getByLabel(arabic ? 'كلمة المرور' : 'Password').fill('ledgersuit')
  await page.getByRole('button', { name: arabic ? 'تسجيل الدخول' : 'Sign in', exact: true }).click()
  await expect(page).toHaveURL('/dashboard')
}

test('billing shows all quota meters and 80, 95, and reached states', async ({ page }) => {
  await mockUsage(page)
  await signIn(page)
  await page.getByRole('button', { name: 'Account menu' }).click()
  await page.getByRole('menuitem', { name: 'Subscription' }).click()

  const usage = page.locator('#usage')
  await expect(usage.locator('[data-quota]')).toHaveCount(7)
  await expect(usage.locator('[data-quota="max_monthly_transactions"]')).toContainText('Approaching limit')
  await expect(usage.locator('[data-quota="max_storage_bytes"]')).toContainText('Almost reached')
  await expect(usage.locator('[data-quota="max_storage_bytes"]')).toContainText('4.8 GB / 5 GB')
  const accounts = usage.locator('[data-quota="max_accounts"]')
  await expect(accounts).toContainText('Limit reached')
  await expect(accounts).toContainText('Business allowance: 300')
  await expect(accounts).toContainText(/From EGP\s*1,099 per month/)
  await expect(accounts.getByRole('link', { name: 'View upgrade options' })).toHaveAttribute('href', '/billing#plans')
})

test('quota usage and upgrade guidance are localized under RTL', async ({ page, context }) => {
  await context.addCookies([
    { name: 'ledger-suit-locale', value: 'ar', domain: '127.0.0.1', path: '/' },
    { name: 'i18n_redirected', value: 'ar', domain: '127.0.0.1', path: '/' },
  ])
  await mockUsage(page)
  await signIn(page, true)
  await page.getByRole('button', { name: 'قائمة الحساب' }).click()
  await page.getByRole('menuitem', { name: 'الاشتراك' }).click()

  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl')
  const usage = page.locator('#usage')
  await expect(usage.locator('[data-quota="max_storage_bytes"]')).toContainText('٤٫٨ ج.بايت / ٥ ج.بايت')
  await expect(usage.locator('[data-quota="max_accounts"]')).toContainText('تم بلوغ الحد')
  await expect(usage.locator('[data-quota="max_accounts"]')).toContainText(/١٬٠٩٩/)
  await expect(usage.getByRole('link', { name: 'عرض خيارات الترقية' }).first()).toBeVisible()
})

test('creation dialogs show the relevant current usage and upgrade action', async ({ page }) => {
  await mockUsage(page)
  await page.route('**/rest/v1/rpc/create_account', route => route.fulfill({
    status: 400,
    contentType: 'application/json',
    body: JSON.stringify({ code: 'P0001', message: 'PLAN_ACCOUNT_LIMIT_REACHED', details: null, hint: null }),
  }))
  await signIn(page)

  await page.getByRole('link', { name: 'Accounts', exact: true }).first().click()
  await page.getByRole('button', { name: 'Add account' }).first().click()
  let dialog = page.getByRole('dialog')
  await expect(dialog.locator('[data-quota="max_accounts"]')).toContainText('100 / 100')
  await dialog.getByLabel('Account name').fill('Over quota account')
  await dialog.getByRole('button', { name: 'Save' }).click()
  await expect(dialog.getByRole('alert')).toHaveText('Your plan’s account limit has been reached. Existing and archived accounts remain available; upgrade your plan to create another account.')
  await dialog.getByRole('button', { name: 'Close' }).click()

  await page.getByRole('link', { name: 'Expense', exact: true }).click()
  await page.getByRole('button', { name: 'Add Expense' }).first().click()
  dialog = page.getByRole('dialog')
  await expect(dialog.locator('[data-quota="max_monthly_transactions"]')).toContainText('2,000 / 2,500')
  await dialog.getByRole('button', { name: 'Close' }).click()

  await page.getByRole('link', { name: 'Recurring rule' }).click()
  await page.getByRole('button', { name: 'Add Recurring rule' }).first().click()
  dialog = page.getByRole('dialog')
  await expect(dialog.locator('[data-quota="max_recurring_rules"]')).toContainText('17 / 25')
  await dialog.getByRole('button', { name: 'Close' }).click()

  await page.getByRole('link', { name: 'Counterparties' }).click()
  await page.getByRole('button', { name: 'Add Counterparty' }).first().click()
  dialog = page.getByRole('dialog')
  await expect(dialog.locator('[data-quota="max_counterparties"]')).toContainText('671 / 1,000')
})

test('reopening a creation surface refreshes usage for the same organization', async ({ page }) => {
  let transactionUsage = 2000
  await mockUsage(page, () => usageRows.map(row => row.quota_key === 'max_monthly_transactions'
    ? { ...row, used_value: transactionUsage, remaining_value: 2500 - transactionUsage }
    : row))
  await signIn(page)

  await page.getByRole('link', { name: 'Expense', exact: true }).click()
  await page.getByRole('button', { name: 'Add Expense' }).first().click()
  let dialog = page.getByRole('dialog')
  await expect(dialog.locator('[data-quota="max_monthly_transactions"]')).toContainText('2,000 / 2,500')
  await dialog.getByRole('button', { name: 'Close' }).click()

  transactionUsage = 2400
  await page.getByRole('button', { name: 'Add Expense' }).first().click()
  dialog = page.getByRole('dialog')
  await expect(dialog.locator('[data-quota="max_monthly_transactions"]')).toContainText('2,400 / 2,500')
})

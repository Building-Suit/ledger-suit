import { expect, test, type Page } from '@playwright/test'

const quotaImpacts = [
  ['max_members', 2, 1, true],
  ['max_monthly_transactions', 420, 500, false],
  ['max_storage_bytes', 2147483648, 1073741824, true],
  ['max_accounts', 22, 30, false],
  ['max_counterparties', 18, 100, false],
  ['max_recurring_rules', 3, 5, false],
  ['max_custom_roles', 1, 0, true],
].map(([quota_key, used_value, target_limit_value, blocked]) => ({
  quota_key,
  used_value,
  current_limit_value: null,
  target_limit_value,
  is_over_target: Number(used_value) > Number(target_limit_value),
  will_block_new_activity: blocked,
}))

async function mockPlanChange(page: Page) {
  let checkoutCalls = 0
  await page.route('**/rest/v1/rpc/subscription_access_state', route => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify('active'),
  }))
  await page.route('**/rest/v1/rpc/plan_change_impact', route => route.fulfill({
    status: 200,
    contentType: 'application/vnd.pgrst.object+json',
    body: JSON.stringify({
      current_plan_key: 'business',
      current_interval: 'monthly',
      target_plan_key: 'solo',
      target_interval: 'monthly',
      target_amount_minor: 39900,
      change_direction: 'downgrade',
      provider_change_supported: false,
      requires_manual_handoff: true,
      would_block_new_activity: true,
      audit_history_current_days: 1095,
      audit_history_target_days: 90,
      audit_history_reduced: true,
      quota_impacts: quotaImpacts,
      feature_impacts: [
        { feature_key: 'imports', current_enabled: true, target_enabled: false, will_lose: true },
        { feature_key: 'multi_currency', current_enabled: true, target_enabled: false, will_lose: true },
        { feature_key: 'priority_support', current_enabled: true, target_enabled: false, will_lose: true },
      ],
    }),
  }))
  await page.route('**/functions/v1/paymob-checkout', (route) => {
    checkoutCalls++
    return route.fulfill({ status: 500, body: '{}' })
  })
  return () => checkoutCalls
}

async function signInAndOpenBilling(page: Page, arabic = false) {
  await page.goto('/login')
  await expect(page.locator('form')).toHaveAttribute('data-hydrated', 'true')
  await page.getByLabel(arabic ? 'البريد الإلكتروني' : 'Email').fill('owner@alpha.test')
  await page.getByLabel(arabic ? 'كلمة المرور' : 'Password').fill('ledgersuit')
  await page.getByRole('button', { name: arabic ? 'تسجيل الدخول' : 'Sign in', exact: true }).click()
  await expect(page).toHaveURL('/dashboard')
  await page.getByRole('button', { name: arabic ? 'قائمة الحساب' : 'Account menu' }).click()
  await page.getByRole('menuitem', { name: arabic ? 'الاشتراك' : 'Subscription' }).click()
  await expect(page).toHaveURL('/billing')
}

test('active billing preflights all downgrade consequences without starting checkout', async ({ page }) => {
  const checkoutCalls = await mockPlanChange(page)
  await signInAndOpenBilling(page)

  await page.locator('[data-plan="solo"]').getByRole('button', { name: 'Review change to Solo' }).click()
  const dialog = page.getByTestId('plan-change-impact')
  await expect(dialog).toContainText('Business → Solo')
  await expect(dialog).toContainText('Changing plans will not delete financial history or workspace resources.')
  await expect(dialog.locator('[data-impact-quota]')).toHaveCount(7)
  await expect(dialog.locator('[data-impact-quota="max_members"]')).toContainText('Current usage 2 · target allowance 1')
  await expect(dialog.locator('[data-impact-quota="max_members"]')).toContainText('New activity blocked')
  await expect(dialog.locator('[data-impact-quota="max_storage_bytes"]')).toContainText('Current usage 2 GB · target allowance 1 GB')
  await expect(dialog).toContainText('CSV imports')
  await expect(dialog).toContainText('Multi-currency accounting')
  await expect(dialog).toContainText('Priority support')
  await expect(dialog).toContainText('Audit-history visibility changes to 90 days')
  await expect(dialog).toContainText('Paymob plan changes are not applied automatically.')
  expect(checkoutCalls()).toBe(0)
})

test('plan-change consequences and provider handoff are localized under RTL', async ({ page, context }) => {
  await context.addCookies([
    { name: 'ledger-suit-locale', value: 'ar', domain: '127.0.0.1', path: '/' },
    { name: 'i18n_redirected', value: 'ar', domain: '127.0.0.1', path: '/' },
  ])
  await mockPlanChange(page)
  await signInAndOpenBilling(page, true)

  await page.locator('[data-plan="solo"]').getByRole('button', { name: 'راجع التغيير إلى فردي' }).click()
  const dialog = page.getByTestId('plan-change-impact')
  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl')
  await expect(dialog).toContainText('لن يؤدي تغيير الخطة إلى حذف السجل المالي أو موارد مساحة العمل.')
  await expect(dialog.locator('[data-impact-quota="max_members"]')).toContainText('ستُحظر الأنشطة الجديدة')
  await expect(dialog).toContainText('لا تُطبَّق تغييرات خطط باي موب تلقائيًا.')
})

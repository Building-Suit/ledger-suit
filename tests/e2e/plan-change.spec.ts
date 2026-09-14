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

function impactResponse(direction: 'upgrade' | 'downgrade') {
  const upgrade = direction === 'upgrade'
  return {
    current_plan_key: upgrade ? 'solo' : 'business',
    current_interval: 'monthly',
    target_plan_key: upgrade ? 'business' : 'solo',
    target_interval: 'monthly',
    target_amount_minor: upgrade ? 109900 : 39900,
    change_direction: direction,
    provider_change_supported: false,
    requires_manual_handoff: true,
    would_block_new_activity: !upgrade,
    audit_history_current_days: upgrade ? 90 : 1095,
    audit_history_target_days: upgrade ? 1095 : 90,
    audit_history_reduced: !upgrade,
    quota_impacts: upgrade
      ? quotaImpacts.map(impact => ({
          ...impact,
          current_limit_value: impact.target_limit_value,
          target_limit_value: impact.quota_key === 'max_storage_bytes' ? 21474836480 : impact.quota_key === 'max_members' ? 10 : impact.quota_key === 'max_monthly_transactions' ? 10000 : impact.quota_key === 'max_accounts' ? 300 : impact.quota_key === 'max_counterparties' ? 5000 : impact.quota_key === 'max_recurring_rules' ? 100 : 10,
          is_over_target: false,
          will_block_new_activity: false,
        }))
      : quotaImpacts,
    feature_impacts: [
      { feature_key: 'imports', current_enabled: !upgrade, target_enabled: upgrade, will_gain: upgrade, will_lose: !upgrade },
      { feature_key: 'multi_currency', current_enabled: !upgrade, target_enabled: upgrade, will_gain: upgrade, will_lose: !upgrade },
      { feature_key: 'priority_support', current_enabled: !upgrade, target_enabled: upgrade, will_gain: upgrade, will_lose: !upgrade },
    ],
  }
}

async function mockPlanChange(page: Page, currentPlan = 'business', direction: 'upgrade' | 'downgrade' = 'downgrade') {
  let checkoutCalls = 0
  let impactCalls = 0
  await page.route('**/rest/v1/rpc/subscription_access_state', route => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify('active'),
  }))
  await page.route('**/rest/v1/rpc/subscription_usage_summary', route => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify(quotaImpacts.map(impact => ({
      plan_key: currentPlan,
      subscription_status: 'active',
      writes_allowed: true,
      quota_key: impact.quota_key,
      used_value: impact.used_value,
      limit_value: impact.current_limit_value,
      remaining_value: null,
      is_unlimited: impact.current_limit_value === null,
      is_at_limit: false,
      is_over_limit: false,
    }))),
  }))
  await page.route('**/rest/v1/rpc/plan_change_impact', (route) => {
    impactCalls++
    return route.fulfill({
      status: 200,
      contentType: 'application/vnd.pgrst.object+json',
      body: JSON.stringify(impactResponse(direction)),
    })
  })
  await page.route('**/functions/v1/paymob-checkout', (route) => {
    checkoutCalls++
    return route.fulfill({ status: 500, body: '{}' })
  })
  return { checkoutCalls: () => checkoutCalls, impactCalls: () => impactCalls }
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
  const calls = await mockPlanChange(page)
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
  expect(calls.checkoutCalls()).toBe(0)
})

test('Solo to Business shows gained features and increased retained audit visibility', async ({ page }) => {
  const calls = await mockPlanChange(page, 'solo', 'upgrade')
  await signInAndOpenBilling(page)

  await page.locator('[data-plan="business"]').getByRole('button', { name: 'Review change to Business' }).click()
  const dialog = page.getByTestId('plan-change-impact')
  await expect(dialog).toContainText('Solo → Business')
  await expect(dialog).toContainText('Features gained')
  await expect(dialog).toContainText('CSV imports')
  await expect(dialog).toContainText('Multi-currency accounting')
  await expect(dialog).toContainText('Priority support')
  await expect(dialog).toContainText('Up to 1,095 days of retained audit history becomes visible; this does not create new history')
  await expect(dialog.locator('[data-impact-quota="max_members"]')).toContainText('target allowance 10')
  expect(calls.checkoutCalls()).toBe(0)
})

test('legacy compatibility subscriptions remain informational and cannot enter Step 20 handling', async ({ page }) => {
  const calls = await mockPlanChange(page, 'ledger_suit')
  await signInAndOpenBilling(page)

  const pricing = page.getByTestId('plan-pricing')
  await expect(pricing).toContainText('Your Ledger Suit compatibility plan remains grandfathered.')
  await expect(pricing.getByRole('button', { name: /^Review change to / })).toHaveCount(0)
  expect(calls.impactCalls()).toBe(0)
  expect(calls.checkoutCalls()).toBe(0)
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
  await expect(dialog).toContainText('لا تُطبَّق تغييرات خطط Paymob تلقائيًا.')
})

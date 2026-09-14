import { expect, test, type Page } from '@playwright/test'

const trialLimits = [
  ['max_members', 1, 10],
  ['max_monthly_transactions', 0, 10000],
  ['max_storage_bytes', 0, 21474836480],
  ['max_accounts', 0, 300],
  ['max_counterparties', 0, 5000],
  ['max_recurring_rules', 0, 100],
  ['max_custom_roles', 0, 10],
] as const

async function mockTrial(page: Page, accessState: 'trialing' | 'read_only') {
  const trialEnd = accessState === 'trialing'
    ? '2030-06-15T12:00:00.000Z'
    : '2029-06-15T12:00:00.000Z'

  await page.route('**/rest/v1/rpc/subscription_access_state', route => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify(accessState),
  }))
  await page.route('**/rest/v1/rpc/subscription_usage_summary', route => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify(trialLimits.map(([quota_key, used_value, limit_value]) => ({
      plan_key: 'trial',
      subscription_status: 'trialing',
      writes_allowed: accessState === 'trialing',
      quota_key,
      used_value,
      limit_value,
      remaining_value: limit_value - used_value,
      is_unlimited: false,
      is_at_limit: false,
      is_over_limit: false,
    }))),
  }))
  await page.route('**/rest/v1/subscriptions?*', route => route.fulfill({
    status: 200,
    contentType: 'application/vnd.pgrst.object+json',
    body: JSON.stringify({
      status: 'trialing',
      billing_interval: null,
      trial_ends_at: trialEnd,
      current_period_end: null,
      grace_period_ends_at: null,
      cancel_at_period_end: false,
      provider_status: null,
    }),
  }))

  if (accessState === 'read_only') {
    await page.route('**/rest/v1/rpc/my_capabilities', route => route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        'accounts.read', 'attachments.read', 'billing.manage', 'billing.read',
        'reports.read', 'transactions.read',
      ]),
    }))
  }
}

async function signIn(page: Page, arabic = false) {
  await page.goto('/login')
  await expect(page.locator('form')).toHaveAttribute('data-hydrated', 'true')
  await page.getByLabel(arabic ? 'البريد الإلكتروني' : 'Email').fill('owner@alpha.test')
  await page.getByLabel(arabic ? 'كلمة المرور' : 'Password').fill('ledgersuit')
  await page.getByRole('button', { name: arabic ? 'تسجيل الدخول' : 'Sign in', exact: true }).click()
  await expect(page).toHaveURL('/dashboard')
}

async function openBilling(page: Page, arabic = false) {
  await page.getByRole('button', { name: arabic ? 'قائمة الحساب' : 'Account menu' }).click()
  await page.getByRole('menuitem', { name: arabic ? 'الاشتراك' : 'Subscription' }).click()
  await expect(page).toHaveURL('/billing')
}

test('active Trial explains its benefits, limits, optional conversion, and checkout identity', async ({ page }) => {
  let checkoutBody: Record<string, unknown> | undefined
  await mockTrial(page, 'trialing')
  await page.route('**/functions/v1/paymob-checkout', async (route) => {
    checkoutBody = route.request().postDataJSON() as Record<string, unknown>
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ url: '/subscribe?checkout=complete&success=false' }),
    })
  })

  await signIn(page)
  await openBilling(page)

  await expect(page.getByText('Current plan', { exact: true })).toBeVisible()
  await expect(page.getByText('14-Day Free Trial', { exact: true }).first()).toBeVisible()
  const summary = page.getByTestId('trial-summary')
  await expect(summary).toContainText('No card was required')
  await expect(summary).toContainText('Business-level product features and limits')
  await expect(summary).toContainText('you are on Free Trial—not the Business plan')
  await expect(summary).toContainText('Priority Support is excluded')
  await expect(summary).toContainText('June 15, 2030')
  await expect(summary).toContainText('purchasing early is optional')
  await expect(page.locator('#usage [data-quota="max_members"]')).toContainText('1 / 10')
  await expect(page.locator('#usage [data-quota="max_monthly_transactions"]')).toContainText('0 / 10,000')
  await expect(page.locator('body')).not.toContainText('ledger_suit')
  await expect(page.locator('body')).not.toContainText('Current plan: trial')

  const pricing = page.getByTestId('plan-pricing')
  await expect(pricing.getByRole('button', { name: 'Choose Solo' })).toBeVisible()
  await expect(pricing.getByRole('button', { name: 'Choose Starter' })).toBeVisible()
  await expect(pricing.getByRole('button', { name: 'Choose Business' })).toBeVisible()
  await pricing.getByRole('radio', { name: 'Yearly', exact: true }).check()
  await pricing.getByRole('button', { name: 'Choose Business' }).click()
  await expect.poll(() => checkoutBody).toMatchObject({ planKey: 'business', interval: 'yearly' })
})

test('active Trial semantics are localized in Arabic under RTL', async ({ page, context }) => {
  await context.addCookies([
    { name: 'ledger-suit-locale', value: 'ar', domain: '127.0.0.1', path: '/' },
    { name: 'i18n_redirected', value: 'ar', domain: '127.0.0.1', path: '/' },
  ])
  await mockTrial(page, 'trialing')

  await signIn(page, true)
  await openBilling(page, true)

  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl')
  const summary = page.getByTestId('trial-summary')
  await expect(summary).toContainText('تجربة مجانية لمدة 14 يومًا')
  await expect(summary).toContainText('لم تُطلب بطاقة دفع')
  await expect(summary).toContainText('بمستوى خطة الأعمال')
  await expect(summary).toContainText('لست مشتركًا في خطة الأعمال')
  await expect(summary).toContainText('الدعم ذو الأولوية غير مشمول')
  await expect(summary).toContainText('الشراء المبكر اختياري')
  await expect(summary).toContainText('2030')
  await expect(page.locator('#usage [data-quota="max_members"]')).toContainText('١ / ١٠')
  await expect(page.locator('body')).not.toContainText('ledger_suit')
  await expect(page.locator('body')).not.toContainText('trial')
})

test('expired Trial keeps readable navigation and Billing checkout while mutations stay blocked', async ({ page }) => {
  await mockTrial(page, 'read_only')
  await signIn(page)

  await expect(page.getByText('This workspace is read-only')).toBeVisible()
  await expect(page.getByText('You can continue viewing records, attachments, and reports.')).toBeVisible()
  await expect(page.getByRole('link', { name: 'Transactions' })).toBeVisible()
  await expect(page.getByRole('link', { name: 'Reports' })).toBeVisible()
  await expect(page.getByRole('link', { name: 'Expense', exact: true })).toHaveCount(0)
  await page.getByRole('link', { name: 'Restore subscription' }).click()
  await expect(page).toHaveURL('/billing')

  const summary = page.getByTestId('trial-summary')
  await expect(summary).toContainText('Free Trial ended')
  await expect(summary).toContainText('Existing financial history remains readable')
  await expect(summary).toContainText('Billing remains available')
  await expect(summary).toContainText('product changes are blocked')
  await expect(summary).toContainText('Choose and successfully purchase Solo, Starter, or Business')
  const pricing = page.getByTestId('plan-pricing')
  await expect(pricing.getByRole('button', { name: 'Choose Solo' })).toBeVisible()
  await expect(pricing.getByRole('button', { name: 'Choose Starter' })).toBeVisible()
  await expect(pricing.getByRole('button', { name: 'Choose Business' })).toBeVisible()
})

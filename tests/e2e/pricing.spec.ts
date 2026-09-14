import { expect, test } from '@playwright/test'

test('launch pricing is responsive, accurate, and distinguishes included from future features', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto('/#pricing')
  await expect(page.locator('[data-hydrated="true"]')).toBeVisible()

  const pricing = page.getByTestId('plan-pricing')
  await expect(pricing.locator('[data-plan="starter"]')).toContainText('Most Popular')
  await expect(pricing.locator('[data-plan="solo"]')).toContainText('EGP 399')
  await expect(pricing.locator('[data-plan="starter"]')).toContainText('EGP 599')
  await expect(pricing.locator('[data-plan="business"]')).toContainText('EGP 1,099')
  await expect(pricing.locator('[data-plan="solo"]')).toContainText('CSV imports (Not included)')
  await expect(pricing.locator('[data-plan="starter"]')).toContainText('CSV imports (Included)')
  await expect(pricing.locator('[data-plan="business"]')).toContainText('Multi-currency accounting (Included)')

  await pricing.getByRole('radio', { name: 'Yearly', exact: true }).check()
  await expect(pricing.getByRole('radio', { name: 'Yearly', exact: true })).toBeChecked()
  await expect(pricing.locator('[data-plan="solo"] s')).toHaveText('EGP 4,788')
  await expect(pricing.locator('[data-plan="solo"]')).toContainText('EGP 3,255.84')
  await expect(pricing.locator('[data-plan="solo"]')).toContainText('32% off')
  await expect(pricing.locator('[data-plan="solo"]')).toContainText('EGP 271.32/month · billed EGP 3,255.84 per year')
  await expect(pricing.locator('[data-plan="starter"] s')).toHaveText('EGP 7,188')
  await expect(pricing.locator('[data-plan="starter"]')).toContainText('EGP 4,887.84')
  await expect(pricing.locator('[data-plan="starter"]')).toContainText('EGP 407.32/month · billed EGP 4,887.84 per year')
  await expect(pricing.locator('[data-plan="business"] s')).toHaveText('EGP 13,188')
  await expect(pricing.locator('[data-plan="business"]')).toContainText('EGP 8,967.84')
  await expect(pricing.locator('[data-plan="business"]')).toContainText('EGP 747.32/month · billed EGP 8,967.84 per year')
  const scale = pricing.locator('[data-plan="scale"]')
  await expect(scale).toContainText('Coming Soon')
  await expect(scale).toContainText('Pricing coming soon')
  await expect(scale).not.toContainText('Custom pricing')
  await expect(scale.getByRole('button')).toBeDisabled()
  await expect(pricing.getByText('Enterprise')).toBeVisible()
  await expect(pricing.getByText('Contact us')).toBeVisible()
  await expect(pricing.getByText('Multi-branch accounting — Coming Soon')).toBeVisible()
  await expect(pricing.getByText('Advanced Analytics & Reporting — Coming Soon')).toBeVisible()
  await expect(pricing.getByText('Developer API — Coming Soon')).toBeVisible()

  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(overflow).toBeLessThanOrEqual(1)
})

test('Arabic pricing remains localized and usable under RTL', async ({ page, context }) => {
  await context.addCookies([
    { name: 'ledger-suit-locale', value: 'ar', domain: '127.0.0.1', path: '/' },
    { name: 'i18n_redirected', value: 'ar', domain: '127.0.0.1', path: '/' },
  ])
  await page.goto('/#pricing')
  await expect(page.locator('[data-hydrated="true"]')).toBeVisible()

  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl')
  const pricing = page.getByTestId('plan-pricing')
  await expect(pricing.locator('[data-plan="starter"]')).toContainText('الأكثر شيوعًا')
  await expect(pricing.locator('[data-plan="solo"]')).toContainText('عضو واحد في مساحة العمل')
  await expect(pricing.locator('[data-plan="solo"]')).not.toContainText('١ أعضاء')
  await pricing.getByRole('radio', { name: 'سنوي', exact: true }).check()
  await expect(pricing.locator('[data-plan="starter"]')).toContainText('٤٬٨٨٧٫٨٤ ج.م')
  await expect(pricing.locator('[data-plan="business"]')).toContainText('المحاسبة متعددة العملات')
  await expect(pricing.getByText('المحاسبة متعددة الفروع — قريبًا')).toBeVisible()
})

test('checkout submits the selected plan and interval from the pricing card', async ({ page }) => {
  let checkoutBody: Record<string, unknown> | undefined
  await page.route('**/rest/v1/rpc/subscription_access_state', route => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify('checkout_required'),
  }))
  await page.route('**/functions/v1/paymob-checkout', async (route) => {
    checkoutBody = route.request().postDataJSON() as Record<string, unknown>
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ url: '/subscribe?checkout=complete&success=false' }),
    })
  })

  await page.goto('/login')
  await expect(page.locator('form')).toHaveAttribute('data-hydrated', 'true')
  await page.getByLabel('Email').fill('owner@alpha.test')
  await page.getByLabel('Password').fill('ledgersuit')
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  await expect(page).toHaveURL('/subscribe')

  const pricing = page.getByTestId('plan-pricing')
  const policyReview = pricing.getByTestId('checkout-policy-review')
  await expect(policyReview.getByRole('link', { name: 'Terms & Conditions' })).toHaveAttribute('href', '/terms')
  await expect(policyReview.getByRole('link', { name: 'Refund & Cancellation Policy' })).toHaveAttribute('href', '/refund-cancellation')
  await expect(policyReview.getByRole('link', { name: 'Privacy Policy' })).toHaveAttribute('href', '/privacy')
  await expect(policyReview.locator('input[type="checkbox"]')).toHaveCount(0)
  await expect(pricing.getByTestId('payment-method-branding')).toHaveText('Secure payments powered by Paymob')
  await pricing.getByRole('radio', { name: 'Yearly', exact: true }).check()
  await pricing.locator('[data-plan="business"]').getByRole('button', { name: 'Choose Business' }).click()

  await expect.poll(() => checkoutBody).toMatchObject({ planKey: 'business', interval: 'yearly' })
})

test('grace-period billing shows plans without checkout actions', async ({ page }) => {
  await page.route('**/rest/v1/rpc/subscription_access_state', route => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify('grace_period'),
  }))

  await page.goto('/login')
  await expect(page.locator('form')).toHaveAttribute('data-hydrated', 'true')
  await page.getByLabel('Email').fill('owner@alpha.test')
  await page.getByLabel('Password').fill('ledgersuit')
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  await expect(page).toHaveURL('/dashboard')

  await page.getByRole('button', { name: 'Account menu' }).click()
  await page.getByRole('menuitem', { name: 'Subscription' }).click()
  await expect(page).toHaveURL('/billing')
  await expect(page.getByText('Payment due')).toBeVisible()
  await expect(page.getByTestId('plan-pricing')).toBeVisible()
  await expect(page.getByRole('button', { name: /^Choose / })).toHaveCount(0)
})

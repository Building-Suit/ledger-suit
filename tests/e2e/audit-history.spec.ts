import { expect, test } from '@playwright/test'

test('authorized user sees the localized plan-aware audit history', async ({ page }) => {
  await page.goto('/login')
  await expect(page.locator('form')).toHaveAttribute('data-hydrated', 'true')
  await page.getByLabel('Email').fill('owner@alpha.test')
  await page.getByLabel('Password').fill('ledgersuit')
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  await expect(page).toHaveURL('/dashboard')

  await page.route('**/rest/v1/rpc/audit_history_window_days', route => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: '90',
  }))
  await page.route('**/rest/v1/rpc/list_audit_history', route => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify([{
      id: 101,
      actor_id: 'a0000000-0000-4000-8000-000000000001',
      actor_email: 'owner@alpha.test',
      action: 'account.updated',
      entity_type: 'account',
      entity_id: '10000000-0000-4000-8000-000000000001',
      before_state: { name: 'Cash' },
      after_state: { name: 'Main cash' },
      metadata: {},
      created_at: '2026-09-12T10:00:00Z',
    }]),
  }))

  await page.goto('/audit')
  await expect(page.getByRole('heading', { name: 'Audit history' })).toBeVisible()
  await expect(page.getByText('Your current plan shows the last 90 days of audit history.')).toBeVisible()
  await expect(page.getByText('Updated', { exact: true })).toBeVisible()
  await expect(page.getByRole('cell', { name: 'owner@alpha.test' })).toBeVisible()

  await page.getByRole('button', { name: 'Account menu' }).click()
  await page.getByRole('button', { name: 'العربية' }).click()
  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl')
  await expect(page.getByRole('heading', { name: 'سجل التدقيق' })).toBeVisible()
  await expect(page.getByText('تعرض خطتك الحالية آخر 90 يومًا من سجل التدقيق.')).toBeVisible()
  await expect(page.getByText('تحديث', { exact: true })).toBeVisible()
})

import { expect, test } from '@playwright/test'

test.beforeEach(async ({ page }) => {
  await page.goto('/login')
  await expect(page.locator('form')).toHaveAttribute('data-hydrated', 'true')
  await page.getByLabel('Email').fill('owner@alpha.test')
  await page.getByLabel('Password').fill('ledgersuit')
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  await expect(page).toHaveURL('/dashboard')
})

test('owner can navigate the four-page finance shell and open operations', async ({ page }) => {
  await expect(page.getByRole('link', { name: 'Dashboard' })).toBeVisible()
  await expect(page.getByRole('link', { name: 'Transactions' })).toBeVisible()
  await expect(page.getByRole('link', { name: 'Accounts' })).toBeVisible()
  await expect(page.getByRole('link', { name: 'Reports' })).toBeVisible()
  await page.getByRole('button', { name: 'Operations' }).click()
  const operations = page.getByRole('dialog')
  await expect(operations.getByRole('heading', { name: 'Operations' })).toBeVisible()
  await expect(operations.getByRole('button', { name: 'Commitments' })).toBeVisible()
  await expect(operations.getByText('Q3 professional fees')).toBeVisible()
  await operations.getByRole('button', { name: 'Recurring' }).click()
  await expect(operations.getByRole('option', { name: 'Liability payment' })).toHaveCount(1)
})

test('owner can add an account through the controlled workflow', async ({ page }) => {
  const accountName = `Playwright Bank ${Date.now()}`
  await page.getByRole('link', { name: 'Accounts' }).click()
  await page.getByRole('button', { name: 'Add account' }).click()
  await page.getByLabel('Account name').fill(accountName)
  await page.getByLabel('Code').fill(`PW${Date.now()}`)
  await page.getByRole('button', { name: 'Save' }).click()
  await expect(page.getByText(accountName, { exact: true })).toBeVisible()
})

test('owner can partially settle a commitment into the ledger', async ({ page }) => {
  await page.getByRole('button', { name: 'Operations' }).click()
  const operations = page.getByRole('dialog')
  const commitment = operations.getByRole('row').filter({ hasText: 'Q3 professional fees' })
  await commitment.getByRole('button', { name: 'Settle' }).click()
  await operations.getByPlaceholder('Amount (blank for full)').fill('100')
  await operations.getByRole('button', { name: 'Post settlement' }).click()
  await expect(commitment).toContainText('Partially paid')
})

test('owner can reach reports and transaction entry', async ({ page }) => {
  await page.getByRole('link', { name: 'Reports' }).click()
  await expect(page.getByRole('heading', { name: 'Reports' })).toBeVisible()
  await expect(page.getByRole('tab', { name: 'Profit & Loss' })).toBeVisible()
  await page.getByRole('button', { name: 'Add' }).click()
  const addDrawer = page.getByRole('dialog', { name: 'Add' })
  await addDrawer.getByRole('button').filter({ hasText: 'Expense' }).click()
  await expect(page.getByRole('dialog')).toContainText('Expense')
})

test('global add drawer exposes creation workflows by section', async ({ page }) => {
  await page.getByRole('button', { name: 'Add' }).click()
  const drawer = page.getByRole('dialog', { name: 'Add' })
  await expect(drawer.getByRole('heading', { name: 'Transactions' })).toBeVisible()
  await expect(drawer.getByRole('heading', { name: 'Accounts' })).toBeVisible()
  await expect(drawer.getByRole('heading', { name: 'Operations' })).toBeVisible()
  await expect(drawer.getByRole('heading', { name: 'Workspace' })).toBeVisible()
  await expect(drawer.getByRole('button', { name: /^Account / })).toBeVisible()
  await expect(drawer.getByRole('button', { name: /^Team invitation / })).toBeVisible()
})

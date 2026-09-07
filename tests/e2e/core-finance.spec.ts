import { expect, test } from '@playwright/test'

test.beforeEach(async ({ page }) => {
  await page.goto('/login')
  await expect(page.locator('form')).toHaveAttribute('data-hydrated', 'true')
  await page.getByLabel('Email').fill('owner@alpha.test')
  await page.getByLabel('Password').fill('ledgersuit')
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  await expect(page).toHaveURL('/dashboard')
})

test('owner can navigate the grouped finance shell and open operation pages', async ({ page }) => {
  await expect(page.getByRole('link', { name: 'Dashboard' })).toBeVisible()
  await expect(page.getByRole('link', { name: 'Transactions' })).toBeVisible()
  await expect(page.getByRole('link', { name: 'Accounts' })).toBeVisible()
  await expect(page.getByRole('link', { name: 'Reports' })).toBeVisible()
  await page.getByRole('link', { name: 'Commitments' }).click()
  await expect(page.getByText('Q3 professional fees')).toBeVisible()
  await page.getByRole('link', { name: 'Recurring rule' }).click()
  await expect(page.getByRole('heading', { name: 'Recurring rule' })).toBeVisible()
  await expect(page.getByRole('columnheader', { name: 'Actions' })).toBeVisible()
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
  await page.getByRole('link', { name: 'Commitments' }).click()
  const commitment = page.getByRole('row').filter({ hasText: 'Q3 professional fees' })
  await commitment.getByRole('button', { name: 'Settle' }).click()
  const actionDialog = page.getByRole('dialog')
  await actionDialog.getByPlaceholder('Amount (blank for full)').fill('100')
  await actionDialog.getByRole('button', { name: 'Post settlement' }).click()
  await expect(commitment).toContainText('Partially paid')
})

test('owner can reach reports and transaction entry', async ({ page }) => {
  await page.getByRole('link', { name: 'Reports' }).click()
  await expect(page.getByRole('heading', { name: 'Reports' })).toBeVisible()
  await expect(page.getByRole('tab', { name: 'Profit & Loss' })).toBeVisible()
  await page.getByRole('link', { name: 'Expense' }).click()
  await page.getByRole('button', { name: 'Add Expense' }).click()
  await expect(page.getByRole('dialog', { name: 'Expense' })).toBeVisible()
})

test('permanent navigation exposes every creation workflow by section', async ({ page }) => {
  const navigation = page.getByRole('navigation', { name: 'Primary' }).first()
  await expect(navigation.getByRole('heading', { name: 'Transactions' })).toBeVisible()
  await expect(navigation.getByRole('heading', { name: 'Ledger' })).toBeVisible()
  await expect(navigation.getByRole('heading', { name: 'Operations' })).toBeVisible()
  await expect(navigation.getByRole('heading', { name: 'Workspace' })).toBeVisible()
  await expect(navigation.getByRole('link', { name: 'Accounts', exact: true })).toBeVisible()
  await expect(navigation.getByRole('link', { name: 'Team invitations' })).toBeVisible()
})

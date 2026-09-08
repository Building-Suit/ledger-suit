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
  await expect(page.getByRole('heading', { name: 'Commitments' })).toBeVisible()
  await page.getByRole('link', { name: 'Recurring rule' }).click()
  await expect(page.getByRole('heading', { name: 'Recurring rule' })).toBeVisible()
  await expect(page.getByRole('columnheader', { name: 'Actions' })).toBeVisible()
})

test('owner can add an account through the controlled workflow', async ({ page }) => {
  const accountName = `Playwright Bank ${Date.now()}`
  await page.getByRole('link', { name: 'Accounts' }).click()
  await expect(page.getByRole('tab', { name: 'Assets' })).toHaveAttribute('aria-selected', 'true')
  await page.getByRole('tab', { name: 'Liabilities' }).click()
  await expect(page).toHaveURL(/\/accounts\?tab=liability/)
  await page.getByRole('button', { name: 'Add account' }).click()
  await page.getByLabel('Account name').fill(accountName)
  await page.getByLabel('Code').fill(`PW${Date.now()}`)
  await page.getByRole('button', { name: 'Save' }).click()
  await expect(page.getByText(accountName, { exact: true })).toBeVisible()
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
  await expect(navigation.getByRole('link', { name: 'Access & permissions' })).toBeVisible()
})

test('owner can review members, role permissions and invitations', async ({ page }) => {
  await page.getByRole('link', { name: 'Access & permissions' }).click()
  await expect(page.getByRole('heading', { name: 'Roles, permissions & invitations' })).toBeVisible()
  await expect(page.getByRole('tab', { name: /Members/ })).toHaveAttribute('aria-selected', 'true')
  await expect(page.getByRole('table').getByText('Amina Owner', { exact: true })).toBeVisible()

  await page.getByRole('tab', { name: 'Roles & permissions' }).click()
  await expect(page.getByRole('heading', { name: 'Role access at a glance' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Permission matrix' })).toBeVisible()

  await page.getByRole('tab', { name: /Invitations/ }).click()
  await expect(page.getByRole('button', { name: 'Invite team member' }).first()).toBeVisible()
})

test('financial system map explains the path from setup to reports', async ({ page }) => {
  await page.getByRole('button', { name: 'Open the financial system map' }).click()

  const dialog = page.getByRole('dialog', { name: 'How your financial system works' })
  await expect(dialog).toBeVisible()
  await expect(dialog.getByText('Set up the financial foundation')).toBeVisible()
  await expect(dialog.getByText('Protected posting engine')).toBeVisible()
  await expect(dialog.getByText('Posted entries are the single source of truth', { exact: false })).toBeVisible()
  await expect(dialog.getByText('Where the result appears')).toBeVisible()
  await expect(dialog.getByRole('link', { name: 'Review accounts' })).toHaveAttribute('href', '/accounts')

  await page.keyboard.press('Escape')
  await expect(dialog).toBeHidden()
})

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
  await expect(page.getByRole('button', { name: 'Add Recurring rule' }).first()).toBeVisible()
})

test('owner can add an account through the controlled workflow', async ({ page }) => {
  const accountName = `Playwright Bank ${Date.now()}`
  await page.getByRole('link', { name: 'Accounts' }).click()
  await expect(page.getByRole('tab', { name: 'Assets' })).toHaveAttribute('aria-selected', 'true')
  await page.getByRole('tab', { name: 'Liabilities' }).click()
  await expect(page).toHaveURL(/\/accounts\?tab=liability/)
  await page.getByRole('button', { name: 'Add account' }).first().click()
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
  await page.getByRole('button', { name: 'Add Expense' }).first().click()
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

test('owner can start a separately billed organization from the switcher', async ({ page }) => {
  let createRequests = 0
  page.on('request', (request) => {
    if (request.url().includes('/rest/v1/rpc/create_organization')) createRequests++
  })
  await page.route('**/rest/v1/rpc/check_legal_name_availability', route => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify(false),
  }))

  await page.getByRole('button', { name: 'Organization' }).click()
  await page.getByRole('button', { name: 'Create another organization' }).click()

  const dialog = page.getByRole('dialog', { name: 'Create another organization' })
  await expect(dialog).toBeVisible()
  await expect(dialog.getByText('A separate subscription is required')).toBeVisible()
  await expect(dialog.getByText('Your existing organization and subscription will not change.', { exact: false })).toBeVisible()
  await expect(dialog.getByText('EGP 600 / month')).toBeVisible()
  await expect(dialog.getByText('EGP 4,800 / year')).toBeVisible()
  await expect(dialog.getByRole('button', { name: 'Create and continue to Stripe' })).toBeVisible()
  await expect(dialog.getByLabel('Legal business name')).toHaveAttribute('required', '')

  await dialog.getByLabel('Organization name').fill('Duplicate Legal Name Books')
  await dialog.getByLabel('Legal business name').fill('Alpha Trading LLC')
  await dialog.getByRole('button', { name: 'Create and continue to Stripe' }).click()
  await expect(dialog.getByText('This legal business name is already registered.')).toBeVisible()
  expect(createRequests).toBe(0)

  await dialog.getByRole('button', { name: 'Close' }).click()
  await expect(dialog).toBeHidden()
})

test('owner can review members, role permissions and invitations', async ({ page }) => {
  await page.getByRole('link', { name: 'Access & permissions' }).click()
  await expect(page.getByRole('heading', { name: 'Roles, permissions & invitations' })).toBeVisible()
  await expect(page.getByRole('tab', { name: /Members/ })).toHaveAttribute('aria-selected', 'true')
  await expect(page.getByRole('table').getByText('Amina Owner', { exact: true })).toBeVisible()

  await expect(page.getByRole('button', { name: 'Permission matrix' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'New role' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Invite', exact: true })).toBeVisible()

  await page.getByRole('tab', { name: 'Roles & permissions' }).click()
  await expect(page.getByRole('heading', { name: 'Roles', exact: true })).toBeVisible()
  const ownerRole = page.locator('article').filter({ has: page.getByRole('heading', { name: 'Owner', exact: true }) })
  const adminRole = page.locator('article').filter({ has: page.getByRole('heading', { name: 'Admin', exact: true }) })
  await expect(ownerRole.getByRole('button', { name: 'Edit role' })).toHaveCount(0)
  await adminRole.getByRole('button', { name: 'Edit role' }).click()
  const editAdmin = page.getByRole('dialog')
  await expect(editAdmin.getByRole('heading', { name: 'Edit Admin' })).toBeVisible()
  await expect(editAdmin.getByRole('table')).toBeVisible()
  await editAdmin.getByRole('button', { name: 'Close' }).click()

  await page.getByRole('button', { name: 'Permission matrix' }).click()
  const matrix = page.getByRole('dialog')
  await expect(matrix.getByRole('heading', { name: 'Permission matrix' })).toBeVisible()
  await expect(matrix.getByRole('checkbox')).toHaveCount(0)
  await matrix.getByRole('button', { name: 'Close' }).click()

  await page.getByRole('button', { name: 'New role' }).click()
  const newRole = page.getByRole('dialog')
  await expect(newRole.getByRole('heading', { name: 'New role' })).toBeVisible()
  await expect(newRole.getByRole('table')).toBeVisible()
  await expect(newRole.locator('fieldset')).toHaveCount(0)
  const permissionRows = await newRole.getByRole('row').allTextContents()
  expect(permissionRows.indexOf('Transactions')).toBeLessThan(permissionRows.indexOf('Ledger'))
  expect(permissionRows.indexOf('Ledger')).toBeLessThan(permissionRows.indexOf('Operations'))
  await newRole.getByRole('button', { name: 'Close' }).click()

  await page.getByRole('tab', { name: /Invitations/ }).click()
  await expect(page.getByRole('button', { name: 'Invite', exact: true })).toHaveCount(1)
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

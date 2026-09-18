import { expect, test, type Page, type Route } from '@playwright/test'

async function signIn(page: Page, email = 'owner@alpha.test') {
  await page.goto('/login')
  await expect(page.locator('form')).toHaveAttribute('data-hydrated', 'true')
  await page.getByLabel('Email').fill(email)
  await page.getByLabel('Password').fill('ledgersuit')
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  await expect(page).toHaveURL('/dashboard')
  await expect(page.getByTestId('section-skeleton')).toHaveCount(0)
}

function balance(organizationId: string, index: number, overrides = {}) {
  return {
    organization_id: organizationId, account_id: `fixture-${index}`,
    name: `Account ${String(index).padStart(4, '0')}`, code: String(index).padStart(4, '0'),
    type: 'asset', subtype: 'bank', currency: 'EGP', balance_minor: 12345,
    entry_count: 2, is_archived: false, is_liquid: true, parent_account_id: null,
    ...overrides,
  }
}

async function mockChart(page: Page, size = 4) {
  await page.route('**/rest/v1/account_balances?**', async (route) => {
    const url = new URL(route.request().url())
    const org = url.searchParams.get('organization_id')!.slice(3)
    const rows = Array.from({ length: size }, (_, i) => balance(org, i))
    if (size === 4) {
      rows[0] = balance(org, 0, { name: 'Zebra bank', code: '100' })
      rows[1] = balance(org, 1, { name: 'Alpha cash', code: '200' })
      rows[2] = balance(org, 2, { name: 'Archived bank', code: '300', is_archived: true })
      rows[3] = balance(org, 3, { name: 'Supplier liability', type: 'liability', subtype: 'accounts_payable' })
    }
    await fulfillPage(route, rows)
  })
}

async function fulfillPage(route: Route, rows: ReturnType<typeof balance>[]) {
  const url = new URL(route.request().url())
  const offset = Number(url.searchParams.get('offset') ?? 0)
  const limit = Number(url.searchParams.get('limit') ?? 500)
  const result = rows.slice(offset, offset + limit)
  await route.fulfill({ json: result, headers: { 'Content-Range': `${offset}-${offset + result.length - 1}/${rows.length}` } })
}

async function accounts(page: Page) {
  await page.getByRole('link', { name: 'Accounts', exact: true }).first().click()
  await expect(page.locator('main > [data-hydrated]')).toHaveAttribute('data-hydrated', 'true')
  await expect(page.getByLabel('Search accounts', { exact: true })).toBeEnabled()
}

test('search, clear, keyboard sorting, archive and type filters compose without changing totals', async ({ page }) => {
  await mockChart(page)
  await signIn(page)
  await accounts(page)
  const table = page.getByRole('table')
  await expect(page.getByTestId('account-result-count')).toHaveText('2 of 2 Assets accounts')
  const total = await page.getByRole('tabpanel').locator('h2 + span').textContent()
  await page.getByLabel('Search accounts', { exact: true }).fill('zEbRa')
  await expect(table.getByRole('row')).toHaveCount(2)
  await expect(table).toContainText('Zebra bank')
  await expect(page.getByRole('tabpanel').locator('h2 + span')).toHaveText(total!)
  await page.getByRole('button', { name: 'Clear search', exact: true }).click()
  await expect(page.getByLabel('Search accounts', { exact: true })).toBeFocused()
  await page.getByLabel('Search accounts', { exact: true }).fill('200')
  await expect(table).toContainText('Alpha cash')
  await expect(table).not.toContainText('Zebra bank')
  await page.getByRole('button', { name: 'Clear search', exact: true }).click()
  const name = table.getByRole('columnheader', { name: 'Account', exact: true })
  await name.focus()
  await page.keyboard.press('Enter')
  await expect(name).toHaveAttribute('aria-sort', 'ascending')
  await expect(table.getByRole('row').nth(1)).toContainText('Alpha cash')
  await page.keyboard.press('Enter')
  await expect(name).toHaveAttribute('aria-sort', 'descending')
  await expect(table.getByRole('row').nth(1)).toContainText('Zebra bank')
  await table.getByRole('columnheader', { name: 'Code', exact: true }).click()
  await expect(table.getByRole('row').nth(1)).toContainText('Zebra bank')
  await page.getByLabel('Show archived').check()
  await expect(table).toContainText('Archived bank')
  await page.getByLabel('Search accounts', { exact: true }).fill('Supplier')
  await expect(table).toContainText('No matching accounts')
  await page.getByRole('tab', { name: 'Liabilities' }).click()
  await expect(page).toHaveURL(/tab=liability/)
  await expect(table).toContainText('Supplier liability')
  await expect(page.getByLabel('Show archived')).toBeChecked()
})

test('loads beyond the API cap before global name/code search and count', async ({ page }) => {
  const offsets: number[] = []
  page.on('request', (request) => {
    const url = new URL(request.url())
    if (url.pathname.endsWith('/account_balances')) offsets.push(Number(url.searchParams.get('offset')))
  })
  await mockChart(page, 1003)
  const selectorOffsets: number[] = []
  await page.route('**/rest/v1/accounts?**', async (route) => {
    const url = new URL(route.request().url())
    const org = url.searchParams.get('organization_id')!.slice(3)
    selectorOffsets.push(Number(url.searchParams.get('offset')))
    await fulfillPage(route, Array.from({ length: 1003 }, (_, i) => ({ ...balance(org, i), id: `fixture-${i}`, is_system: false, system_key: null })))
  })
  await signIn(page)
  await accounts(page)
  await expect(page.getByTestId('account-result-count')).toHaveText('1003 of 1003 Assets accounts')
  expect([...new Set(offsets)]).toEqual([0, 500, 1000])
  await expect(page.getByRole('table').getByRole('row')).toHaveCount(26)
  await page.getByRole('button', { name: 'Next', exact: true }).click()
  await expect(page.getByRole('table')).toContainText('Account 0025')
  await page.getByRole('columnheader', { name: 'Account', exact: true }).click()
  await page.getByRole('columnheader', { name: 'Account', exact: true }).click()
  await expect(page.getByRole('table').getByRole('row').nth(1)).toContainText('Account 1002')
  await page.getByLabel('Search accounts', { exact: true }).fill('1002')
  await expect(page.getByRole('table')).toContainText('Account 1002')
  await expect(page.getByTestId('account-result-count')).toHaveText('1 of 1003 Assets accounts')
  await page.getByRole('link', { name: 'Expense', exact: true }).click()
  await page.getByRole('button', { name: 'Add Expense' }).first().click()
  await expect(page.locator('#src option').filter({ hasText: 'Account 1002' })).toHaveCount(1)
  expect([...new Set(selectorOffsets)]).toEqual([0, 500, 1000])
})

test('failed later page shows an actionable error, then retry loads the complete empty chart', async ({ page }) => {
  let fail = true
  await page.route('**/rest/v1/account_balances?**', async (route) => {
    const url = new URL(route.request().url())
    const org = url.searchParams.get('organization_id')!.slice(3)
    if (!fail) return fulfillPage(route, [])
    if (Number(url.searchParams.get('offset'))) return route.fulfill({ status: 500, json: { message: 'Fixture failure' } })
    return fulfillPage(route, Array.from({ length: 501 }, (_, i) => balance(org, i)))
  })
  await signIn(page)
  await page.getByRole('link', { name: 'Accounts', exact: true }).first().click()
  await expect(page.getByRole('alert')).toContainText('Accounts could not be loaded')
  await expect(page.getByRole('table')).toHaveCount(0)
  await expect(page.getByTestId('account-result-count')).toHaveCount(0)
  fail = false
  await page.getByRole('button', { name: 'Try again' }).click()
  await expect(page.getByText('Create your first account')).toBeVisible()
})

test('viewer can search and sort but cannot create, edit or archive', async ({ page }) => {
  await mockChart(page)
  await signIn(page, 'viewer@alpha.test')
  await accounts(page)
  await expect(page.getByRole('table')).toContainText('Alpha cash')
  await page.getByRole('columnheader', { name: 'Account', exact: true }).click()
  for (const name of ['Add account', 'Edit', 'Archive']) {
    await expect(page.getByRole('button', { name, exact: true })).toHaveCount(0)
  }
})

test('real create/edit/archive refresh the table and existing transaction selector without reload', async ({ page }) => {
  await signIn(page)
  // Mount the existing selector first, so this verifies cache refresh, not just a fresh page read.
  await page.getByRole('link', { name: 'Expense', exact: true }).click()
  await page.getByRole('button', { name: 'Add Expense' }).first().click()
  await expect(page.getByRole('dialog', { name: 'Expense' })).toBeVisible()
  await page.getByRole('dialog', { name: 'Expense' }).getByRole('button', { name: 'Close' }).click()
  await accounts(page)
  const name = `UI02A Bank ${Date.now()}`
  let documents = 0
  page.on('request', request => { if (request.resourceType() === 'document') documents++ })
  await page.getByLabel('Search accounts', { exact: true }).fill('intentionally hidden')
  await page.getByLabel('Show archived').check()
  await page.getByRole('button', { name: 'Add account', exact: true }).first().click()
  await page.getByLabel('Account name', { exact: true }).fill(name)
  await page.getByLabel('Code', { exact: true }).fill(`UI${Date.now()}`)
  await page.getByRole('combobox', { name: 'Account subtype', exact: true }).selectOption('bank')
  await page.getByRole('button', { name: 'Save', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Show saved account' })).toBeVisible()
  await expect(page.getByLabel('Search accounts', { exact: true })).toHaveValue('intentionally hidden')
  await expect(page.getByLabel('Show archived')).toBeChecked()
  await page.getByRole('button', { name: 'Show saved account' }).click()
  await expect(page.getByRole('table')).toContainText(name)
  await page.getByRole('table').getByRole('button', { name: 'Edit', exact: true }).click()
  await page.getByLabel('Account name', { exact: true }).fill(`${name} updated`)
  await page.getByRole('button', { name: 'Save', exact: true }).click()
  await expect(page.getByRole('table')).toContainText(`${name} updated`)
  await page.getByRole('link', { name: 'Expense', exact: true }).click()
  await page.getByRole('button', { name: 'Add Expense' }).first().click()
  await expect(page.locator('#src option').filter({ hasText: `${name} updated` })).toHaveCount(1)
  await page.getByRole('dialog', { name: 'Expense' }).getByRole('button', { name: 'Close' }).click()
  await accounts(page)
  await page.getByLabel('Search accounts', { exact: true }).fill(name)
  await page.getByRole('table').getByRole('button', { name: 'Archive', exact: true }).click()
  await expect(page.getByRole('table')).not.toContainText(name)
  await page.getByLabel('Show archived').check()
  await expect(page.getByRole('table')).toContainText(name)
  expect(documents).toBe(0)
})

test('switching tenants clears filters and rejects a delayed response from the previous tenant', async ({ page }) => {
  const secondId = 'b0000000-1111-4000-8000-000000000099'
  let firstId = ''
  await page.route('**/rest/v1/organization_members?**', async (route) => {
    if (!route.request().url().includes('organizations(') && !decodeURIComponent(route.request().url()).includes('organizations(')) return route.continue()
    const response = await route.fetch()
    const memberships = await response.json()
    firstId = memberships[0].organizations.id
    await route.fulfill({ response, json: [...memberships, { ...memberships[0], organizations: { ...memberships[0].organizations, id: secondId, name: 'UI02A Second tenant', legal_name: 'Second tenant fixture' } }] })
  })
  // These fixtures exercise browser isolation, not database authorization.
  // Reuse the signed-in tenant's entitlement/capability responses for the fake tenant.
  await page.route('**/rest/v1/rpc/*', async (route) => {
    const body = route.request().postData()
    if (!body?.includes(secondId)) return route.continue()
    const response = await route.fetch({ postData: body.replaceAll(secondId, firstId) })
    await route.fulfill({ response })
  })
  let release!: () => void
  const delayed = new Promise<void>((resolve) => { release = resolve })
  let secondRequested!: () => void
  const requested = new Promise<void>((resolve) => { secondRequested = resolve })
  await page.route('**/rest/v1/account_balances?**', async (route) => {
    const org = new URL(route.request().url()).searchParams.get('organization_id')!.slice(3)
    if (org === secondId) { secondRequested(); await delayed }
    await fulfillPage(route, [balance(org, 0, { name: org === secondId ? 'Private second tenant row' : 'First tenant account' })])
  })
  await signIn(page)
  await accounts(page)
  await page.getByLabel('Search accounts', { exact: true }).fill('First')
  await page.getByLabel('Show archived').check()
  await page.getByRole('columnheader', { name: 'Account', exact: true }).click()
  await page.getByRole('button', { name: 'Organization', exact: true }).click()
  await page.getByRole('option', { name: /UI02A Second tenant/ }).click()
  await requested
  await expect(page.getByLabel('Search accounts', { exact: true })).toHaveValue('')
  await expect(page.getByLabel('Show archived')).not.toBeChecked()
  await expect(page.getByRole('table')).toHaveCount(0)
  await expect(page.getByTestId('account-result-count')).toHaveCount(0)
  await page.getByRole('button', { name: 'Organization', exact: true }).click()
  await page.getByRole('option', { name: /Alpha Trading/ }).click()
  await expect(page.getByRole('table')).toContainText('First tenant account')
  release()
  await expect(page.getByRole('columnheader', { name: 'Code', exact: true })).toHaveAttribute('aria-sort', 'ascending')
  await expect(page.getByRole('table')).not.toContainText('Private second tenant row')
  await expect(page.getByTestId('account-result-count')).toHaveText('1 of 1 Assets accounts')
})

for (const locale of ['en', 'ar']) {
  for (const theme of ['light', 'dark']) {
    test(`${locale} ${theme}: narrow table stays within the page and supports keyboard sorting`, async ({ page }) => {
      await mockChart(page)
      await signIn(page)
      await accounts(page)
      await page.getByRole('button', { name: 'Account menu', exact: true }).click()
      await page.getByRole('button', { name: theme === 'light' ? 'Light' : 'Dark', exact: true }).click()
      if (locale === 'ar') await page.getByRole('button', { name: 'العربية', exact: true }).click()
      await page.getByRole('button', { name: locale === 'ar' ? 'قائمة الحساب' : 'Account menu', exact: true }).click()
      await page.setViewportSize({ width: 390, height: 844 })
      await expect(page.locator('main > [data-hydrated]')).toHaveAttribute('data-hydrated', 'true')
      const table = page.getByRole('table')
      await expect(table).toBeVisible()
      await expect(page.locator('html')).toHaveAttribute('dir', locale === 'ar' ? 'rtl' : 'ltr')
      await expect(page.locator('html')).toHaveAttribute('data-theme', theme)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
      const header = table.getByRole('columnheader').nth(1)
      await header.focus()
      await expect(header).toBeFocused()
      await header.press('Enter')
      await expect(header).toHaveAttribute('aria-sort', 'ascending')
      await expect(table.getByRole('row').nth(1)).toContainText('Alpha cash')
      const scroll = page.getByRole('region', { name: locale === 'ar' ? /جدول الحسابات/ : /Account table/ })
      await scroll.focus()
      await expect(scroll).toBeFocused()
      expect(await scroll.evaluate(element => element.scrollWidth > element.clientWidth)).toBe(true)
    })
  }
}

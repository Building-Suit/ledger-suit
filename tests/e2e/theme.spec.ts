import { expect, test } from '@playwright/test'

test('the brand logo displays light logo on dark theme', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('ledger-suit.theme', 'dark'))
  await page.goto('/')

  const root = page.locator('html')
  await expect(root).toHaveAttribute('data-theme', 'dark')

  const logo = page.getByRole('img', { name: 'Ledger Suit by Building Suit' }).first()
  await expect(logo.locator('.ls-logo-image-light')).toBeVisible()
  await expect(logo.locator('.ls-logo-image-dark')).toBeHidden()

  await page.reload()
  await expect(root).toHaveAttribute('data-theme', 'dark')
  await expect(logo.locator('.ls-logo-image-light')).toBeVisible()
  await expect(logo.locator('.ls-logo-image-dark')).toBeHidden()
})

test('the brand logo displays dark logo on light theme', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('ledger-suit.theme', 'light'))
  await page.goto('/')

  const root = page.locator('html')
  await expect(root).toHaveAttribute('data-theme', 'light')

  const logo = page.getByRole('img', { name: 'Ledger Suit by Building Suit' }).first()
  await expect(logo.locator('.ls-logo-image-dark')).toBeVisible()
  await expect(logo.locator('.ls-logo-image-light')).toBeHidden()

  await page.reload()
  await expect(root).toHaveAttribute('data-theme', 'light')
  await expect(logo.locator('.ls-logo-image-dark')).toBeVisible()
  await expect(logo.locator('.ls-logo-image-light')).toBeHidden()
})

test('system theme follows the emulated color scheme without a forced attribute', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('ledger-suit.theme', 'system'))
  await page.emulateMedia({ colorScheme: 'dark' })
  await page.goto('/')

  const root = page.locator('html')
  await expect(root).not.toHaveAttribute('data-theme')
  const logo = page.getByRole('img', { name: 'Ledger Suit by Building Suit' }).first()
  await expect(logo.locator('.ls-logo-image-light')).toBeVisible()
  await expect(logo.locator('.ls-logo-image-dark')).toBeHidden()

  await page.emulateMedia({ colorScheme: 'light' })
  await expect(logo.locator('.ls-logo-image-dark')).toBeVisible()
  await expect(logo.locator('.ls-logo-image-light')).toBeHidden()
})

test('a stored theme preference persists across a reload', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('ledger-suit.theme', 'dark'))
  await page.goto('/')

  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark')
  await expect.poll(() => page.evaluate(() => localStorage.getItem('ledger-suit.theme'))).toBe('dark')
  await page.reload()
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark')
})

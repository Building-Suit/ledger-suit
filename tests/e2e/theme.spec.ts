import { expect, test } from '@playwright/test'

test('the brand wordmark follows the selected theme', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('ledger-suit.theme', 'dark'))
  await page.goto('/')

  const logo = page.getByRole('img', { name: 'Ledger Suit by Building Suit' }).first()
  await expect(logo.locator('.ls-logo-image-light')).toBeVisible()
  await expect(logo.locator('.ls-logo-image-dark')).toBeHidden()

  await page.evaluate(() => localStorage.setItem('ledger-suit.theme', 'light'))
  await page.reload()
  await expect(logo.locator('.ls-logo-image-light')).toBeVisible()
  await expect(logo.locator('.ls-logo-image-dark')).toBeHidden()
})

test('refreshing with the light theme never loads dark before light', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('ledger-suit.theme', 'light'))

  const wordmarkRequests: string[] = []
  page.on('request', (request) => {
    const url = request.url()
    if (/ledger-suit-wordmark-(light|dark)\.svg/.test(url)) wordmarkRequests.push(url)
  })

  await page.goto('/')
  await page.reload()

  const root = page.locator('html')
  await expect(root).toHaveAttribute('data-theme', 'light')

  const firstLight = wordmarkRequests.findIndex(url => url.includes('wordmark-light'))
  const firstDark = wordmarkRequests.findIndex(url => url.includes('wordmark-dark'))

  expect(firstLight, 'the light wordmark must be requested').toBeGreaterThanOrEqual(0)
  if (firstDark !== -1) {
    expect(
      firstLight,
      `the dark wordmark loaded before the light one: ${wordmarkRequests.join(', ')}`,
    ).toBeLessThan(firstDark)
  }
})

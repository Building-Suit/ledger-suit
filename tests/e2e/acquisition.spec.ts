import { expect, test } from '@playwright/test'

test('landing page explains the product and leads to paid onboarding', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Run your finances')
  await expect(page.getByRole('link', { name: 'Start 14-day trial' }).first()).toBeVisible()
  await expect(page.getByText('EGP 600 / month')).toBeVisible()
  await expect(page.getByText('EGP 4,800 / year')).toBeVisible()

  await page.getByRole('link', { name: 'Start 14-day trial' }).first().click()
  await expect(page).toHaveURL('/signup')
  await expect(page.getByLabel('Full name')).toBeVisible()
  await expect(page.getByLabel('Phone number')).toBeVisible()
  await expect(page.getByLabel('Job title')).toBeVisible()
})

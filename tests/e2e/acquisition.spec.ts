import { expect, test } from '@playwright/test'

async function readOtp(email: string) {
  for (let attempt = 0; attempt < 20; attempt++) {
    const response = await fetch(`http://127.0.0.1:54324/api/v1/search?query=${encodeURIComponent(`to:${email}`)}`)
    const inbox = await response.json() as { messages?: Array<{ ID?: string; id?: string }> }
    const messageId = inbox.messages?.[0]?.ID ?? inbox.messages?.[0]?.id
    if (messageId) {
      const message = await fetch(`http://127.0.0.1:54324/api/v1/message/${messageId}`).then(result => result.text())
      const otp = message.match(/\b(\d{6})\b/)?.[1]
      if (otp) return otp
    }
    await new Promise(resolve => setTimeout(resolve, 250))
  }
  throw new Error(`No signup OTP received for ${email}`)
}

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

test('signup verifies email by OTP before provisioning and checkout', async ({ page }) => {
  const email = `otp-${Date.now()}@ledgersuit.test`
  await page.route('**/functions/v1/stripe-checkout', route => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify({ url: 'http://127.0.0.1:3210/billing/ready?session_id=otp-test' }),
  }))

  await page.goto('/signup')
  await expect(page.locator('form')).toHaveAttribute('data-hydrated', 'true')
  await page.getByLabel('Full name').fill('OTP Test Owner')
  await page.getByLabel('Phone number').fill('+201000000000')
  await page.getByLabel('Job title').fill('Founder')
  await page.getByLabel('Email').fill(email)
  await page.getByLabel('Password').fill('otp-test-password')
  await page.getByRole('button', { name: 'Continue' }).click()

  await expect(page.getByRole('heading', { name: 'Business setup' })).toBeVisible()
  await page.locator('#org-display-name').fill('OTP Test Books')
  await page.locator('#org-legal-name').fill('OTP Test Books LLC')
  await page.getByRole('button', { name: 'Continue' }).click()
  await page.getByRole('button', { name: 'Create account and continue to Stripe' }).click()

  await expect(page.getByRole('heading', { name: 'Verify your email' })).toBeVisible()
  await expect(page.getByText(email)).toBeVisible()
  await expect(page.getByText(/Code expires in (59|60):/)).toBeVisible()
  await expect(page.getByRole('button', { name: /Resend in/ })).toBeDisabled()

  const otp = await readOtp(email)
  for (let index = 0; index < 6; index++) {
    await page.getByLabel(`Verification code digit ${index + 1}`).fill(otp[index]!)
  }
  await page.getByRole('button', { name: 'Verify and continue to Stripe' }).click()

  await expect(page).toHaveURL(/\/billing\/ready\?session_id=otp-test/)
})

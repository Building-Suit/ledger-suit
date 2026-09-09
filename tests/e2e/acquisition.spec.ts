import { expect, test } from '@playwright/test'

async function readOtp(email: string) {
  const mailpitUrl = process.env.MAILPIT_URL ?? 'http://127.0.0.1:54324'
  for (let attempt = 0; attempt < 20; attempt++) {
    const response = await fetch(`${mailpitUrl}/api/v1/search?query=${encodeURIComponent(`to:${email}`)}`)
    const inbox = await response.json() as { messages?: Array<{ ID?: string; id?: string }> }
    const messageId = inbox.messages?.[0]?.ID ?? inbox.messages?.[0]?.id
    if (messageId) {
      const message = await fetch(`${mailpitUrl}/api/v1/message/${messageId}`).then(result => result.text())
      const otp = message.match(/\b(\d{6})\b/)?.[1]
      if (otp) return otp
    }
    await new Promise(resolve => setTimeout(resolve, 250))
  }
  throw new Error(`No signup OTP received for ${email}`)
}

test('an invited user verifies email, creates a password, joins, and can sign in again', async ({ page, request }) => {
  const supabaseUrl = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321'
  const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0'
  const email = `invitee-${Date.now()}@ledgersuit.test`
  const password = 'invited-user-password'

  const ownerAuth = await request.post(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
    headers: { apikey: anonKey },
    data: { email: 'owner@alpha.test', password: 'ledgersuit' },
  })
  expect(ownerAuth.ok()).toBeTruthy()
  const ownerSession = await ownerAuth.json() as { access_token: string }

  const organizationsResponse = await request.get(`${supabaseUrl}/rest/v1/organizations?select=id&name=eq.Alpha%20Trading`, {
    headers: { apikey: anonKey, Authorization: `Bearer ${ownerSession.access_token}` },
  })
  const organizations = await organizationsResponse.json() as Array<{ id: string }>

  const invitationResponse = await request.post(`${supabaseUrl}/rest/v1/rpc/create_organization_invitation`, {
    headers: { apikey: anonKey, Authorization: `Bearer ${ownerSession.access_token}` },
    data: {
      p_organization_id: organizations[0]!.id,
      p_email: email,
      p_role: 'viewer',
    },
  })
  expect(invitationResponse.ok()).toBeTruthy()
  const invitations = await invitationResponse.json() as Array<{ invitation_token: string }>

  await page.goto(`/accept-invitation?token=${invitations[0]!.invitation_token}`)
  await expect(page.getByRole('heading', { name: 'You’re invited to Alpha Trading' })).toBeVisible()
  await expect(page.getByLabel('Your Ledger Suit login email')).toHaveValue(email)
  await expect(page.getByLabel('Your Ledger Suit login email')).toHaveAttribute('readonly', '')

  await page.getByRole('button', { name: 'Send OTP to create password' }).click()
  const otp = await readOtp(email)
  for (let index = 0; index < 6; index++) {
    await page.getByLabel(`Verification code digit ${index + 1}`).fill(otp[index]!)
  }
  await page.getByRole('button', { name: 'Verify code' }).click()
  await expect(page.getByRole('heading', { name: 'Create your password' })).toBeVisible()
  await page.getByLabel('Full name').fill('Invited User')
  await page.getByLabel('Phone number').fill(`+2010${String(Date.now()).slice(-8)}`)
  await page.getByLabel('Job title').fill('Accountant')
  await page.getByLabel('New password').fill(password)
  await page.getByLabel('Confirm password').fill(password)
  await page.getByRole('button', { name: 'Create password & join workspace' }).click()
  await expect(page).toHaveURL('/dashboard')
  await expect(page.getByRole('banner').getByText('Alpha Trading', { exact: true })).toBeVisible()

  await page.getByRole('button', { name: 'Account menu' }).click()
  await page.getByRole('menuitem', { name: 'Sign out' }).click()
  await page.getByLabel('Email').fill(email)
  await page.getByLabel('Password').fill(password)
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  await expect(page).toHaveURL('/dashboard')
})

test('landing page explains the product and leads to a cardless trial', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Run your finances')
  await expect(page.getByRole('link', { name: 'Start 14-day trial' }).first()).toBeVisible()
  await expect(page.getByText('14 days free · No credit card required')).toBeVisible()
  await expect(page.getByText('EGP 600 / month')).toBeVisible()
  await expect(page.getByText('EGP 4,800 / year')).toBeVisible()

  await page.getByRole('link', { name: 'Start 14-day trial' }).first().click()
  await expect(page).toHaveURL('/signup')
  await expect(page.getByLabel('Full name')).toBeVisible()
  await expect(page.getByLabel('Phone number')).toBeVisible()
  await expect(page.getByLabel('Job title')).toBeVisible()
  await expect(page.getByText('14-day free trial — no credit card required')).toBeVisible()
})

test('signup verifies email by OTP before provisioning the free trial', async ({ page }) => {
  const unique = Date.now()
  const email = `otp-${unique}@ledgersuit.test`

  await page.goto('/signup')
  await expect(page.locator('form')).toHaveAttribute('data-hydrated', 'true')
  await page.getByLabel('Full name').fill('OTP Test Owner')
  await page.getByLabel('Phone number').fill(`+2010${String(unique).slice(-8)}`)
  await page.getByLabel('Job title').fill('Founder')
  await page.getByLabel('Email').fill(email)
  await page.getByLabel('Password').fill('otp-test-password')
  await page.getByRole('button', { name: 'Continue' }).click()

  await expect(page.getByRole('heading', { name: 'Business setup' })).toBeVisible()
  await page.locator('#org-display-name').fill(`OTP Test Books ${unique}`)
  await page.locator('#org-legal-name').fill(`OTP Test Books ${unique} LLC`)
  await page.getByRole('button', { name: 'Create account and start free trial' }).click()

  await expect(page.getByRole('heading', { name: 'Verify your email' })).toBeVisible()
  await expect(page.getByText(email)).toBeVisible()
  await expect(page.getByText(/Code expires in (59|60):/)).toBeVisible()
  await expect(page.getByRole('button', { name: /Resend in/ })).toBeDisabled()

  const otp = await readOtp(email)
  for (let index = 0; index < 6; index++) {
    await page.getByLabel(`Verification code digit ${index + 1}`).fill(otp[index]!)
  }
  await page.getByRole('button', { name: 'Verify and start free trial' }).click()

  await expect(page).toHaveURL('/dashboard')
  await expect(page.getByText(/Trial: (13d 23h|14d 0h)/)).toBeVisible()
})

test('the dedicated OTP route presents verification without the product shell', async ({ page }) => {
  await page.goto('/verify-email?email=unconfirmed%40ledgersuit.test')
  await expect(page.getByRole('heading', { name: 'Verify your email' })).toBeVisible()
  await expect(page.getByText('unconfirmed@ledgersuit.test')).toBeVisible()
  await expect(page.getByRole('link', { name: 'Dashboard' })).toHaveCount(0)
})

test('an unpaid workspace is sent to payment before the product shell', async ({ page }) => {
  await page.goto('/login')
  await expect(page.locator('form')).toHaveAttribute('data-hydrated', 'true')
  await page.route('**/rest/v1/rpc/subscription_access_state', route => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify('checkout_required'),
  }))

  await page.getByLabel('Email').fill('owner@alpha.test')
  await page.getByLabel('Password').fill('ledgersuit')
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()

  await expect(page).toHaveURL('/subscribe')
  await expect(page.getByRole('heading', { name: 'Activate Alpha Trading' })).toBeVisible()
  await expect(page.getByRole('link', { name: 'Dashboard' })).toHaveCount(0)
})

test('billing stays mounted and product navigation remains client-side', async ({ page }) => {
  let entitlementRequests = 0
  let documentRequests = 0

  page.on('request', (request) => {
    if (request.url().includes('/rest/v1/rpc/subscription_access_state')) entitlementRequests++
    if (request.resourceType() === 'document') documentRequests++
  })

  await page.goto('/login')
  await expect(page.locator('form')).toHaveAttribute('data-hydrated', 'true')
  await page.getByLabel('Email').fill('owner@alpha.test')
  await page.getByLabel('Password').fill('ledgersuit')
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  await expect(page).toHaveURL('/dashboard')
  await expect(page.getByTestId('section-skeleton')).toHaveCount(0)

  const documentsAfterLogin = documentRequests
  await page.getByRole('button', { name: 'Account menu' }).click()
  await page.getByRole('menuitem', { name: 'Subscription' }).click()
  await expect(page).toHaveURL('/billing')
  await expect(page.getByRole('heading', { name: 'Subscription' })).toBeVisible()

  // A remount loop used to issue this RPC continuously and leave a blank page.
  await page.waitForTimeout(1_000)
  expect(entitlementRequests).toBeLessThanOrEqual(2)

  let releaseTransactions!: () => void
  const transactionsReleased = new Promise<void>((resolve) => {
    releaseTransactions = resolve
  })
  await page.route('**/rest/v1/rpc/search_transactions', async (route) => {
    await transactionsReleased
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([]),
    })
  })

  const click = page.getByRole('link', { name: 'Transactions' }).click()
  await expect(page).toHaveURL('/transactions')
  await expect(page.getByRole('heading', { name: 'Transactions', level: 1 })).toBeVisible()
  await expect(page.getByTestId('section-skeleton')).toBeVisible()
  expect(documentRequests).toBe(documentsAfterLogin)

  releaseTransactions()
  await click
  await expect(page.getByTestId('section-skeleton')).toHaveCount(0)
})

test('switching authenticated users clears tenant data without losing Nuxt context', async ({ page }) => {
  await page.goto('/login')
  await expect(page.locator('form')).toHaveAttribute('data-hydrated', 'true')
  await page.getByLabel('Email').fill('owner@alpha.test')
  await page.getByLabel('Password').fill('ledgersuit')
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  await expect(page).toHaveURL('/dashboard')
  await expect(page.getByRole('banner').getByText('Alpha Trading', { exact: true })).toBeVisible()

  await page.getByRole('button', { name: 'Account menu' }).click()
  await page.getByRole('menuitem', { name: 'Sign out' }).click()
  await expect(page).toHaveURL('/login')

  await page.getByLabel('Email').fill('owner@beta.test')
  await page.getByLabel('Password').fill('ledgersuit')
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()

  await expect(page).toHaveURL('/dashboard')
  await expect(page.getByRole('banner').getByText('Beta Supplies', { exact: true })).toBeVisible()
  await expect(page.getByRole('banner').getByText('Alpha Trading', { exact: true })).toHaveCount(0)
  await expect(page.getByText(/composable that requires access to the Nuxt instance/i)).toHaveCount(0)
})

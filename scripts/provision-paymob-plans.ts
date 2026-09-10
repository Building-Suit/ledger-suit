interface PaymobPlan {
  id: number
  name: string
  frequency: number
  amount_cents: number
  integration: number
  use_transaction_amount: boolean
  is_active: boolean
  webhook_url: string | null
}

interface PlanSpec {
  name: string
  frequency: 30 | 360
  amountCents: number
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim()
  if (!value) throw new Error(`${name} is required`)
  return value
}

function positiveInteger(name: string): number {
  const value = Number(requiredEnv(name))
  if (!Number.isSafeInteger(value) || value <= 0) throw new Error(`${name} must be a positive integer`)
  return value
}

function webhookUrl(): string {
  const argument = Deno.args.find(value => value.startsWith('--webhook-url='))?.slice('--webhook-url='.length)
  if (!argument) {
    throw new Error('Pass the deployed callback as --webhook-url=https://<project-ref>.supabase.co/functions/v1/paymob-webhook')
  }
  const url = new URL(argument)
  if (url.protocol !== 'https:' || !url.pathname.endsWith('/functions/v1/paymob-webhook')) {
    throw new Error('The webhook URL must be HTTPS and end with /functions/v1/paymob-webhook')
  }
  return url.toString()
}

const baseUrl = (Deno.env.get('PAYMOB_BASE_URL')?.trim() || 'https://accept.paymob.com').replace(/\/$/, '')
const apiKey = requiredEnv('PAYMOB_API_KEY')
const motoIntegrationId = positiveInteger('PAYMOB_MOTO_INTEGRATION_ID')
const callbackUrl = webhookUrl()

async function responseJson<T>(response: Response): Promise<T> {
  const payload = await response.json().catch(() => ({})) as Record<string, unknown>
  if (!response.ok) {
    const message = payload.detail ?? payload.message ?? `Paymob request failed (${response.status})`
    throw new Error(typeof message === 'string' ? message : JSON.stringify(message))
  }
  return payload as T
}

async function authToken(): Promise<string> {
  const response = await fetch(`${baseUrl}/api/auth/tokens`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ api_key: apiKey }),
  })
  const payload = await responseJson<{ token?: string }>(response)
  if (!payload.token) throw new Error('Paymob authentication did not return a token')
  return payload.token
}

async function listPlans(token: string): Promise<PaymobPlan[]> {
  const plans: PaymobPlan[] = []
  let next: string | null = `${baseUrl}/api/acceptance/subscription-plans`
  while (next) {
    const response: Response = await fetch(next, { headers: { Authorization: `Bearer ${token}` } })
    const page: { results?: PaymobPlan[], next?: string | null } = await responseJson(response)
    plans.push(...(page.results ?? []))
    next = page.next ?? null
  }
  return plans
}

function matches(plan: PaymobPlan, spec: PlanSpec): boolean {
  return plan.frequency === spec.frequency
    && plan.amount_cents === spec.amountCents
    && plan.integration === motoIntegrationId
    && plan.use_transaction_amount === true
    && plan.is_active === true
    && plan.webhook_url === callbackUrl
}

async function ensurePlan(token: string, plans: PaymobPlan[], spec: PlanSpec): Promise<PaymobPlan> {
  const namedPlans = plans.filter(plan => plan.name === spec.name)
  const existing = namedPlans.find(plan => matches(plan, spec))
  if (existing) return existing
  if (namedPlans.length) {
    throw new Error(`${spec.name} already exists with different billing settings; review it in Paymob instead of creating a duplicate`)
  }

  const response = await fetch(`${baseUrl}/api/acceptance/subscription-plans`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      frequency: spec.frequency,
      name: spec.name,
      webhook_url: callbackUrl,
      plan_type: 'rent',
      number_of_deductions: null,
      amount_cents: spec.amountCents,
      use_transaction_amount: true,
      is_active: true,
      integration: motoIntegrationId,
    }),
  })
  return await responseJson<PaymobPlan>(response)
}

const token = await authToken()
const plans = await listPlans(token)
const monthly = await ensurePlan(token, plans, {
  name: 'Ledger Suit Monthly',
  frequency: 30,
  amountCents: positiveInteger('PAYMOB_MONTHLY_AMOUNT_CENTS'),
})
const yearly = await ensurePlan(token, plans, {
  name: 'Ledger Suit Yearly',
  frequency: 360,
  amountCents: positiveInteger('PAYMOB_YEARLY_AMOUNT_CENTS'),
})

console.log('Paymob subscription plans are ready:')
console.log(`PAYMOB_MONTHLY_PLAN_ID="${monthly.id}"`)
console.log(`PAYMOB_YEARLY_PLAN_ID="${yearly.id}"`)

import { requiredEnv } from './http.ts'

const STRIPE_URL = 'https://api.stripe.com/v1'

export async function stripeRequest<T>(
  path: string,
  options: { method?: 'GET' | 'POST', body?: URLSearchParams, idempotencyKey?: string } = {},
): Promise<T> {
  const response = await fetch(`${STRIPE_URL}${path}`, {
    method: options.method ?? 'GET',
    headers: {
      Authorization: `Bearer ${requiredEnv('STRIPE_SECRET_KEY')}`,
      ...(options.body ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {}),
      ...(options.idempotencyKey ? { 'Idempotency-Key': options.idempotencyKey } : {}),
    },
    body: options.body,
  })
  const payload = await response.json()
  if (!response.ok) {
    const message = payload?.error?.message ?? `Stripe request failed (${response.status})`
    throw new Error(message)
  }
  return payload as T
}

function hex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)].map(byte => byte.toString(16).padStart(2, '0')).join('')
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false
  let difference = 0
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index)
  }
  return difference === 0
}

export async function verifyStripeSignature(
  rawBody: string,
  signatureHeader: string | null,
  toleranceSeconds = 300,
): Promise<boolean> {
  if (!signatureHeader) return false
  const entries = signatureHeader.split(',').map(item => item.split('=', 2))
  const timestamp = entries.find(([key]) => key === 't')?.[1]
  const signatures = entries.filter(([key]) => key === 'v1').map(([, value]) => value)
  if (!timestamp || signatures.length === 0) return false

  const parsedTimestamp = Number(timestamp)
  if (!Number.isFinite(parsedTimestamp)
    || Math.abs(Math.floor(Date.now() / 1000) - parsedTimestamp) > toleranceSeconds) return false

  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(requiredEnv('STRIPE_WEBHOOK_SECRET')),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const digest = hex(await crypto.subtle.sign(
    'HMAC', key, new TextEncoder().encode(`${timestamp}.${rawBody}`),
  ))
  return signatures.some(signature => constantTimeEqual(digest, signature))
}

import { requiredEnv } from './http.ts'

type JsonRecord = Record<string, unknown>

function baseUrl(): string {
  return (Deno.env.get('PAYMOB_BASE_URL') ?? 'https://accept.paymob.com').replace(/\/$/, '')
}

export async function paymobRequest<T>(path: string, body: JsonRecord): Promise<T> {
  const response = await fetch(`${baseUrl()}${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Token ${requiredEnv('PAYMOB_SECRET_KEY')}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })
  const payload = await response.json().catch(() => ({})) as JsonRecord
  if (!response.ok) {
    const message = payload.detail ?? payload.message ?? `Paymob request failed (${response.status})`
    throw new Error(typeof message === 'string' ? message : JSON.stringify(message))
  }
  return payload as T
}

export function paymobCheckoutUrl(clientSecret: string): string {
  const query = new URLSearchParams({
    publicKey: requiredEnv('PAYMOB_PUBLIC_KEY'),
    clientSecret,
  })
  return `${baseUrl()}/unifiedcheckout/?${query}`
}

const transactionHmacFields = [
  'amount_cents',
  'created_at',
  'currency',
  'error_occured',
  'has_parent_transaction',
  'id',
  'integration_id',
  'is_3d_secure',
  'is_auth',
  'is_capture',
  'is_refunded',
  'is_standalone_payment',
  'is_voided',
  'order.id',
  'owner',
  'pending',
  'source_data.pan',
  'source_data.sub_type',
  'source_data.type',
  'success',
] as const

function nestedValue(record: JsonRecord, path: string): unknown {
  return path.split('.').reduce<unknown>((value, key) => (
    value && typeof value === 'object' ? (value as JsonRecord)[key] : undefined
  ), record)
}

function hex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)].map(byte => byte.toString(16).padStart(2, '0')).join('')
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false
  let difference = 0
  for (let index = 0; index < left.length; index++) difference |= left.charCodeAt(index) ^ right.charCodeAt(index)
  return difference === 0
}

export async function verifyPaymobTransactionHmac(
  object: JsonRecord,
  receivedHmac: string | null,
): Promise<boolean> {
  if (!receivedHmac) return false
  const message = transactionHmacFields.map(field => String(nestedValue(object, field) ?? '')).join('')
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(requiredEnv('PAYMOB_HMAC_SECRET')),
    { name: 'HMAC', hash: 'SHA-512' },
    false,
    ['sign'],
  )
  const digest = hex(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message)))
  return constantTimeEqual(digest.toLowerCase(), receivedHmac.toLowerCase())
}

export async function verifyPaymobSubscriptionHmac(
  subscriptionId: string,
  triggerType: string,
  receivedHmac: string | null,
): Promise<boolean> {
  if (!receivedHmac) return false
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(requiredEnv('PAYMOB_HMAC_SECRET')),
    { name: 'HMAC', hash: 'SHA-512' },
    false,
    ['sign'],
  )
  const message = `${triggerType}for${subscriptionId}`
  const digest = hex(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message)))
  return constantTimeEqual(digest.toLowerCase(), receivedHmac.toLowerCase())
}

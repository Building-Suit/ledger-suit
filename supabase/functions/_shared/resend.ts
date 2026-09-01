import { escapeHtml, requiredEnv } from './http.ts'

interface EmailInput {
  to: string
  subject: string
  body: string
  recipientName?: string
  organizationName?: string
  actionUrl?: string | null
  idempotencyKey: string
}

export async function sendEmail(input: EmailInput): Promise<string> {
  const safeBody = escapeHtml(input.body).replaceAll('\n', '<br>')
  const safeName = escapeHtml(input.recipientName ?? input.to)
  const safeOrg = escapeHtml(input.organizationName ?? 'Ledger Suit')
  const action = input.actionUrl
    ? `<p style="margin:24px 0"><a href="${escapeHtml(input.actionUrl)}" style="background:#14213d;color:#fff;padding:12px 18px;border-radius:8px;text-decoration:none">Open Ledger Suit</a></p>`
    : ''

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${requiredEnv('RESEND_API_KEY')}`,
      'Content-Type': 'application/json',
      'Idempotency-Key': input.idempotencyKey.slice(0, 256),
    },
    body: JSON.stringify({
      from: requiredEnv('RESEND_FROM_EMAIL'),
      to: [input.to],
      subject: input.subject,
      html: `<div style="font-family:Arial,sans-serif;max-width:600px;margin:auto;color:#14213d"><h2>${safeOrg}</h2><p>Hello ${safeName},</p><p>${safeBody}</p>${action}<p style="color:#667085;font-size:13px">Ledger Suit</p></div>`,
    }),
  })
  const payload = await response.json()
  if (!response.ok) throw new Error(payload?.message ?? `Resend request failed (${response.status})`)
  return String(payload.id)
}

import { escapeHtml, requiredEnv } from './http.ts'

interface EmailInput {
  to: string
  subject: string
  body: string
  recipientName?: string
  organizationName?: string
  actionUrl?: string | null
  actionLabel?: string
  brandUrl?: string
  preheader?: string
  idempotencyKey: string
}

export async function sendEmail(input: EmailInput): Promise<string> {
  const safeBody = escapeHtml(input.body).replaceAll('\n', '<br>')
  const safeName = escapeHtml(input.recipientName ?? input.to)
  const safeOrg = escapeHtml(input.organizationName ?? 'Ledger Suit')
  const safePreheader = escapeHtml(input.preheader ?? input.subject)
  const safeActionLabel = escapeHtml(input.actionLabel ?? 'Open Ledger Suit')
  const brand = input.brandUrl
    ? `<img src="${escapeHtml(input.brandUrl)}" width="44" height="44" alt="" style="display:block;width:44px;height:44px;border-radius:10px">`
    : '<div style="width:44px;height:44px;border-radius:10px;background:#d99a32"></div>'
  const action = input.actionUrl
    ? `<p style="margin:28px 0"><a href="${escapeHtml(input.actionUrl)}" style="display:inline-block;background:#d99a32;color:#101828;padding:13px 20px;border-radius:9px;text-decoration:none;font-weight:700">${safeActionLabel}</a></p>`
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
      html: `<div style="display:none;max-height:0;overflow:hidden;opacity:0">${safePreheader}</div><div style="background:#f5f6f8;padding:32px 16px"><div style="font-family:Arial,sans-serif;max-width:600px;margin:auto;overflow:hidden;border:1px solid #d9dde5;border-radius:14px;background:#ffffff;color:#14213d"><div style="display:flex;align-items:center;gap:12px;background:#14213d;padding:22px 28px;color:#ffffff">${brand}<div><div style="font-size:19px;font-weight:800">Ledger Suit</div><div style="margin-top:3px;font-size:12px;color:#d99a32">BY BUILDING SUIT</div></div></div><div style="padding:30px 28px"><p style="margin:0 0 18px;font-size:20px;font-weight:800">${safeOrg}</p><p>Hello ${safeName},</p><p style="font-size:15px;line-height:1.65">${safeBody}</p>${action}<p style="margin:26px 0 0;padding-top:20px;border-top:1px solid #e5e7eb;color:#667085;font-size:12px;line-height:1.5">For your security, this invitation is tied to your email address and expires after 14 days. If you were not expecting it, you can safely ignore this message.</p></div></div></div>`,
    }),
  })
  const payload = await response.json()
  if (!response.ok) throw new Error(payload?.message ?? `Resend request failed (${response.status})`)
  return String(payload.id)
}

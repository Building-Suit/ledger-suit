import { adminClient, json, publicError, requiredEnv } from '../_shared/http.ts'
import { sendEmail } from '../_shared/resend.ts'

interface QueuedEmail {
  notification_id: string
  recipient_email: string
  recipient_name: string
  organization_name: string
  subject: string
  body: string
  action_url: string | null
  notification_type: string
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405)
  const expected = `Bearer ${requiredEnv('SUPABASE_SERVICE_ROLE_KEY')}`
  if (request.headers.get('Authorization') !== expected) return json({ error: 'Unauthorized' }, 401)

  const admin = adminClient()
  try {
    const { data, error } = await admin.rpc('claim_notification_emails', { p_limit: 25 })
    if (error) throw error
    const queued = (data ?? []) as QueuedEmail[]
    let sent = 0

    for (const item of queued) {
      try {
        const appUrl = requiredEnv('APP_BASE_URL').replace(/\/$/, '')
        const actionUrl = item.action_url
          ? `${appUrl}${item.action_url.startsWith('/') ? item.action_url : `/${item.action_url}`}`
          : appUrl
        const providerId = await sendEmail({
          to: item.recipient_email,
          recipientName: item.recipient_name,
          organizationName: item.organization_name,
          subject: item.subject,
          body: item.body,
          actionUrl,
          idempotencyKey: `notification/${item.notification_id}`,
        })
        await admin.rpc('complete_notification_email', {
          p_notification_id: item.notification_id,
          p_provider_id: providerId,
          p_error: null,
        })
        sent++
      }
      catch (error) {
        await admin.rpc('complete_notification_email', {
          p_notification_id: item.notification_id,
          p_provider_id: null,
          p_error: error instanceof Error ? error.message : 'Email delivery failed',
        })
      }
    }
    return json({ claimed: queued.length, sent })
  }
  catch (error) {
    return json({ error: publicError(error) }, 500)
  }
})

import { authenticatedClient, handleOptions, json, publicError, readJson, requiredEnv } from '../_shared/http.ts'
import { sendEmail } from '../_shared/resend.ts'

interface InvitationBody {
  organizationId: string
  email: string
  role: 'admin' | 'accountant' | 'data_entry' | 'viewer'
}

Deno.serve(async (request) => {
  const preflight = handleOptions(request)
  if (preflight) return preflight
  try {
    const { organizationId, email, role } = await readJson<InvitationBody>(request)
    const supabase = await authenticatedClient(request)
    const { data, error } = await supabase.rpc('create_organization_invitation', {
      p_organization_id: organizationId,
      p_email: email.trim().toLowerCase(),
      p_role: role,
    })
    if (error) throw error
    const invitation = (data as Array<{ invitation_token: string, invitation_id: string }> | null)?.[0]
    if (!invitation?.invitation_token) throw new Error('Invitation could not be created')

    const appUrl = requiredEnv('APP_BASE_URL').replace(/\/$/, '')
    const actionUrl = `${appUrl}/?invitation=${encodeURIComponent(invitation.invitation_token)}`
    try {
      await sendEmail({
        to: email.trim().toLowerCase(),
        subject: 'You are invited to Ledger Suit',
        body: 'You have been invited to join an organization in Ledger Suit. Sign in with this email address to accept it.',
        actionUrl,
        idempotencyKey: `invitation/${invitation.invitation_id}`,
      })
      return json({ sent: true, invitationToken: invitation.invitation_token })
    }
    catch (emailError) {
      return json({ sent: false, invitationToken: invitation.invitation_token, warning: publicError(emailError) })
    }
  }
  catch (error) {
    return json({ error: publicError(error) }, 400)
  }
})

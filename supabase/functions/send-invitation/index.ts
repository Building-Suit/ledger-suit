import { authenticatedClient, handleOptions, json, publicError, readJson, requiredEnv } from '../_shared/http.ts'
import { sendEmail } from '../_shared/resend.ts'

interface InvitationBody {
  organizationId?: string
  email?: string
  role?: 'admin' | 'accountant' | 'data_entry' | 'viewer'
  roleId?: string | null
  invitationId?: string
}

Deno.serve(async (request) => {
  const preflight = handleOptions(request)
  if (preflight) return preflight
  try {
    const { organizationId, email, role, roleId, invitationId } = await readJson<InvitationBody>(request)
    const supabase = await authenticatedClient(request)
    const { data, error } = invitationId
      ? await supabase.rpc('renew_organization_invitation', { p_invitation_id: invitationId })
      : await supabase.rpc('create_organization_invitation', {
          p_organization_id: organizationId,
          p_email: email?.trim().toLowerCase(),
          p_role: role,
          p_role_id: roleId ?? null,
        })
    if (error) throw error
    const invitation = (data as Array<{ invitation_token: string, invitation_id: string }> | null)?.[0]
    if (!invitation?.invitation_token) throw new Error('Invitation could not be created')

    const { data: invitationRecord, error: invitationError } = await supabase
      .from('organization_invitations')
      .select('email, role, role_id, organizations(name)')
      .eq('id', invitation.invitation_id)
      .single()
    if (invitationError || !invitationRecord) throw invitationError ?? new Error('Invitation could not be loaded')

    const { data: auth } = await supabase.auth.getUser()
    const { data: sender } = await supabase
      .from('profiles')
      .select('full_name, job_title')
      .eq('id', auth.user?.id ?? '')
      .single()

    const recipientEmail = String(invitationRecord.email)
    const organization = invitationRecord.organizations as unknown as { name: string } | null
    const organizationName = organization?.name ?? 'your organization'
    const senderName = sender?.full_name?.trim() || 'A Ledger Suit administrator'
    const senderTitle = sender?.job_title?.trim() || 'Workspace administrator'
    let roleName = String(invitationRecord.role).replaceAll('_', ' ')
    if (invitationRecord.role_id) {
      const { data: customRole } = await supabase
        .from('organization_roles')
        .select('name_en')
        .eq('id', invitationRecord.role_id)
        .maybeSingle()
      if (customRole?.name_en) roleName = customRole.name_en
    }

    const appUrl = requiredEnv('APP_BASE_URL').replace(/\/$/, '')
    const actionUrl = `${appUrl}/accept-invitation?token=${encodeURIComponent(invitation.invitation_token)}`
    try {
      await sendEmail({
        to: recipientEmail,
        subject: `${senderName} invited you to ${organizationName} on Ledger Suit`,
        body: `${senderName}, ${senderTitle}, invited you to join ${organizationName} as ${roleName}.\n\nYour email address (${recipientEmail}) will be your Ledger Suit login. Select the button below, send a one-time code to this address, verify it, and choose your own password. After setup, sign in normally with this email and password.`,
        recipientName: recipientEmail,
        organizationName,
        actionUrl,
        actionLabel: 'Accept invitation & create password',
        brandUrl: `${appUrl}/brand/ledger-suit-app-icon.png`,
        preheader: `Join ${organizationName} securely and create your Ledger Suit password.`,
        idempotencyKey: `invitation/${invitation.invitation_id}/${invitation.invitation_token.slice(0, 16)}`,
      })
      return json({ sent: true })
    }
    catch (emailError) {
      // A token that never reached the recipient must not remain as a ghost
      // pending invitation or block a clean retry with the same address.
      await supabase.rpc('revoke_organization_invitation', { p_invitation_id: invitation.invitation_id })
      return json({ sent: false, warning: publicError(emailError) })
    }
  }
  catch (error) {
    return json({ error: publicError(error) }, 400)
  }
})

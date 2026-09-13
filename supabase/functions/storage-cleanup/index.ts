import { adminClient, json, publicError, requiredEnv } from '../_shared/http.ts'

interface CleanupItem {
  reservation_id: string
  storage_bucket: string
  storage_key: string
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405)
  const expected = `Bearer ${requiredEnv('SUPABASE_SERVICE_ROLE_KEY')}`
  if (request.headers.get('Authorization') !== expected) return json({ error: 'Unauthorized' }, 401)

  const admin = adminClient()
  try {
    const { data, error } = await admin.rpc('claim_attachment_storage_cleanup', { p_limit: 100 })
    if (error) throw error
    const items = (data ?? []) as CleanupItem[]
    let cleaned = 0

    for (const item of items) {
      const { error: removeError } = await admin.storage
        .from(item.storage_bucket)
        .remove([item.storage_key])
      const { error: completeError } = await admin.rpc('complete_attachment_storage_cleanup', {
        p_reservation_id: item.reservation_id,
        p_error: removeError?.message ?? null,
      })
      if (completeError) throw completeError
      if (!removeError) cleaned++
    }

    return json({ claimed: items.length, cleaned })
  }
  catch (error) {
    return json({ error: publicError(error) }, 500)
  }
})

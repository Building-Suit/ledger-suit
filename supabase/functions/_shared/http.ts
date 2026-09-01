import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2'

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, stripe-signature',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

export function handleOptions(request: Request): Response | null {
  return request.method === 'OPTIONS' ? new Response('ok', { headers: corsHeaders }) : null
}

export function requiredEnv(name: string): string {
  const value = Deno.env.get(name)
  if (!value) throw new Error(`Missing server secret: ${name}`)
  return value
}

export function adminClient(): SupabaseClient {
  return createClient(requiredEnv('SUPABASE_URL'), requiredEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false },
  })
}

export async function authenticatedClient(request: Request): Promise<SupabaseClient> {
  const authorization = request.headers.get('Authorization')
  if (!authorization?.startsWith('Bearer ')) throw new Error('Authentication required')

  const client = createClient(requiredEnv('SUPABASE_URL'), requiredEnv('SUPABASE_ANON_KEY'), {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data, error } = await client.auth.getUser()
  if (error || !data.user) throw new Error('Authentication required')
  return client
}

export async function readJson<T>(request: Request): Promise<T> {
  if (request.method !== 'POST') throw new Error('Method not allowed')
  return await request.json() as T
}

export function publicError(error: unknown): string {
  const message = error instanceof Error ? error.message : 'Request failed'
  if (message.includes('TENANT_ACCESS_DENIED') || message.includes('INSUFFICIENT_PERMISSION')) {
    return 'You do not have permission to perform this action.'
  }
  if (message.startsWith('Missing server secret:')) return 'Billing is not configured yet.'
  return message
}

export function escapeHtml(value: string): string {
  return value.replace(/[&<>'"]/g, character => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;',
  })[character] ?? character)
}

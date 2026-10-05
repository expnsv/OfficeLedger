import { createClient } from 'npm:@supabase/supabase-js@2.109.0'
Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 })
  try {
    const body = await req.json()
    const username = String(body?.username ?? '').trim().toLowerCase()
    const password = String(body?.password ?? '')
    if (!username || !password) return Response.json({ ok: false, error: 'Invalid bootstrap credentials.' }, { status: 401 })
    const publicClient = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { auth: { autoRefreshToken: false, persistSession: false } })
    const { data: userId, error: verifyError } = await publicClient.rpc('verify_bootstrap_credential', { p_username: username, p_password: password })
    if (verifyError || !userId) return Response.json({ ok: false, error: 'Invalid bootstrap credentials.' }, { status: 401 })
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { autoRefreshToken: false, persistSession: false } })
    const { data, error } = await admin.auth.admin.updateUserById(userId, { password, email_confirm: true })
    if (error) throw error
    return Response.json({ ok: true, email: data.user?.email })
  } catch (error) {
    console.error(error)
    return Response.json({ ok: false, error: 'Bootstrap authentication failed.' }, { status: 500 })
  }
})

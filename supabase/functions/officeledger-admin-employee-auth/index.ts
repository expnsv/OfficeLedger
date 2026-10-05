import { createClient } from 'npm:@supabase/supabase-js@2.109.0'
Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 })
  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return Response.json({ error: 'Authentication required.' }, { status: 401 })
    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authHeader } } })
    const { data: { user }, error: userError } = await supabase.auth.getUser()
    if (userError || !user) return Response.json({ error: 'Authentication required.' }, { status: 401 })
    const { data: isAdmin, error: adminError } = await supabase.rpc('is_admin')
    if (adminError || !isAdmin) return Response.json({ error: 'Administrator access required.' }, { status: 403 })
    const body = await req.json(), action = String(body?.action ?? ''), targetUserId = String(body?.user_id ?? '')
    if (!targetUserId) return Response.json({ error: 'Employee is required.' }, { status: 400 })
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { autoRefreshToken: false, persistSession: false } })
    if (action === 'update_email') {
      const email = String(body?.email ?? '').trim().toLowerCase()
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return Response.json({ error: 'Valid email is required.' }, { status: 400 })
      const { error } = await admin.auth.admin.updateUserById(targetUserId, { email, email_confirm: false })
      if (error) throw error
      const { error: dbError } = await admin.from('profiles').update({ email, updated_at: new Date().toISOString() }).eq('user_id', targetUserId)
      if (dbError) throw dbError
      return Response.json({ ok: true })
    }
    if (action === 'send_recovery') {
      const { data: target, error } = await admin.from('profiles').select('email,is_active').eq('user_id', targetUserId).single()
      if (error) throw error
      if (!target.is_active) return Response.json({ error: 'Inactive employee cannot receive a recovery email.' }, { status: 400 })
      const { error: recoveryError } = await supabase.auth.resetPasswordForEmail(target.email, { redirectTo: new URL('/index.html?recovery=1', req.url).toString() })
      if (recoveryError) throw recoveryError
      const { error: flagError } = await admin.from('profiles').update({ must_change_password: true, updated_at: new Date().toISOString() }).eq('user_id', targetUserId)
      if (flagError) throw flagError
      return Response.json({ ok: true })
    }
    return Response.json({ error: 'Unsupported action.' }, { status: 400 })
  } catch (error) {
    console.error(error)
    return Response.json({ error: 'Employee authentication operation failed.' }, { status: 500 })
  }
})

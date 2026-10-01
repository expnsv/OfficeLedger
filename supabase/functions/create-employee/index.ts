import { createClient } from 'npm:@supabase/supabase-js@2.109.0'

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const publishableKey = (() => {
  const directKey = Deno.env.get('SUPABASE_PUBLISHABLE_KEY')
  if (directKey) return directKey
  try {
    const keys = JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS') ?? '{}') as Record<string, string>
    if (keys.default) return keys.default
  } catch {
    // Fall back to the compatibility variable used by existing projects.
  }
  return Deno.env.get('SUPABASE_ANON_KEY') ?? ''
})()
const secretKey = (() => {
  const directKey = Deno.env.get('SUPABASE_SECRET_KEY')
  if (directKey) return directKey
  try {
    const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}') as Record<string, string>
    if (keys.default) return keys.default
  } catch {
    // Fall back to the compatibility variable used by existing projects.
  }
  return Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
})()
const appOrigin = Deno.env.get('APP_ORIGIN') ?? 'https://expnsv.github.io'
const redirectUrl = Deno.env.get('APP_REDIRECT_URL') ?? 'https://expnsv.github.io/OfficeLedger/index.html'

function corsHeaders(origin: string | null): Record<string, string> {
  return {
    'Access-Control-Allow-Origin': origin === appOrigin ? appOrigin : 'null',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin'
  }
}

function json(body: Record<string, unknown>, status: number, origin: string | null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }
  })
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get('Origin')
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(origin) })
  if (request.method !== 'POST' || !origin || origin !== appOrigin) return json({ error: 'Request not allowed.' }, 403, origin)
  if (!supabaseUrl || !publishableKey || !secretKey || !appOrigin || !redirectUrl) {
    return json({ error: 'Employee invitations are not configured.' }, 500, origin)
  }

  try {
    const expectedOrigin = new URL(appOrigin).origin
    const inviteRedirect = new URL(redirectUrl)
    if (expectedOrigin !== appOrigin || inviteRedirect.origin !== appOrigin) throw new Error('Invalid application URL configuration.')

    const authorization = request.headers.get('Authorization') ?? ''
    const tokenMatch = authorization.match(/^Bearer\s+(.+)$/i)
    if (!tokenMatch) return json({ error: 'Sign in as an Admin to invite an employee.' }, 401, origin)

    const caller = createClient(supabaseUrl, publishableKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      global: { headers: { Authorization: authorization } }
    })
    const { data: { user }, error: authError } = await caller.auth.getUser(tokenMatch[1])
    if (authError || !user) return json({ error: 'Sign in as an Admin to invite an employee.' }, 401, origin)

    const { data: profile, error: profileError } = await caller.from('profiles')
      .select('role, is_active, display_name').eq('user_id', user.id).maybeSingle()
    if (profileError || profile?.role !== 'ADMIN' || profile.is_active !== true) {
      return json({ error: 'Only an active Admin can invite employees.' }, 403, origin)
    }

    let payload: unknown
    try { payload = await request.json() } catch { return json({ error: 'Invalid request.' }, 400, origin) }
    const body = payload && typeof payload === 'object' ? payload as Record<string, unknown> : {}
    const name = typeof body.name === 'string' ? body.name.trim() : ''
    const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : ''
    if (!name || name.length > 80 || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return json({ error: 'Enter a valid employee name and email address.' }, 400, origin)
    }

    const admin = createClient(supabaseUrl, secretKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
    })
    const { data, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
      data: { display_name: name },
      redirectTo: inviteRedirect
    })
    if (inviteError || !data.user) {
      return json({ error: 'Could not send the invitation. Confirm the address and email delivery settings.' }, 400, origin)
    }

    const { error: profileWriteError } = await admin.from('profiles').insert({
      user_id: data.user.id,
      email,
      display_name: name,
      role: 'EMPLOYEE',
      is_active: true
    })
    if (profileWriteError) {
      await admin.auth.admin.deleteUser(data.user.id)
      return json({ error: 'The account could not be added to OfficeLedger.' }, 500, origin)
    }

    const { error: auditError } = await admin.from('audit_events').insert({
      actor_id: user.id,
      actor_name: String(profile.display_name ?? user.email ?? 'Admin'),
      actor_role: 'ADMIN',
      action: 'Employee invited',
      record_id: data.user.id,
      category: 'Employees',
      new_value: { email, name }
    })
    if (auditError) {
      await admin.from('profiles').delete().eq('user_id', data.user.id)
      await admin.auth.admin.deleteUser(data.user.id)
      return json({ error: 'The invitation could not be recorded in the audit history.' }, 500, origin)
    }
    return json({ invited: true }, 200, origin)
  } catch {
    return json({ error: 'The employee invitation could not be completed.' }, 500, origin)
  }
})

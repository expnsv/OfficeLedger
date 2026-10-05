import { createClient } from 'npm:@supabase/supabase-js@2.109.0'
const url=Deno.env.get('SUPABASE_URL')??''
const publishable=Deno.env.get('SUPABASE_PUBLISHABLE_KEY')??Deno.env.get('SUPABASE_ANON_KEY')??''
const secret=Deno.env.get('SUPABASE_SECRET_KEY')??Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??''
const origin=Deno.env.get('APP_ORIGIN')??''
const redirect=Deno.env.get('APP_REDIRECT_URL')??''
const cors=(o:string|null)=>({'Access-Control-Allow-Origin':o===origin?origin:'null','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS','Vary':'Origin'})
const out=(body:unknown,status:number,o:string|null)=>new Response(JSON.stringify(body),{status,headers:{...cors(o),'Content-Type':'application/json','Cache-Control':'no-store'}})
Deno.serve(async req=>{
 const o=req.headers.get('Origin');
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors(o)});
 if(req.method!=='POST'||!o||o!==origin)return out({error:'Request not allowed.'},403,o);
 try{
  const auth=req.headers.get('Authorization')||'';const token=auth.match(/^Bearer\s+(.+)$/i)?.[1];if(!token)return out({error:'Sign in as Admin.'},401,o);
  const caller=createClient(url,publishable,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
  const {data:{user},error:ue}=await caller.auth.getUser(token);if(ue||!user)return out({error:'Session is invalid.'},401,o);
  const {data:profile,error:pe}=await caller.from('profiles').select('display_name,is_active').eq('user_id',user.id).maybeSingle();
  if(pe||!profile?.is_active)return out({error:'Active Admin access is required.'},403,o);
  const {data:adminMembership}=await caller.from('employee_roles').select('roles(code)').eq('employee_id',user.id).limit(20);
  if(!(adminMembership||[]).some((x:any)=>x.roles?.code==='ADMIN'))return out({error:'Only an Admin can invite employees.'},403,o);
  const body=await req.json();const name=String(body?.name||'').trim();const email=String(body?.email||'').trim().toLowerCase();
  if(!name||name.length>80||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))return out({error:'Enter a valid employee name and email.'},400,o);
  if(!url||!secret||!origin||!redirect)return out({error:'Employee invitation is not configured on the server.'},500,o);
  const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
  const {data,error}=await admin.auth.admin.inviteUserByEmail(email,{data:{display_name:name},redirectTo:redirect});
  if(error||!data.user)throw error||new Error('Invitation failed');
  const {error:profileError}=await admin.from('profiles').insert({user_id:data.user.id,email,display_name:name,is_active:true});
  if(profileError){await admin.auth.admin.deleteUser(data.user.id);throw profileError;}
  const {data:associate}=await admin.from('roles').select('id').eq('code','ASSOCIATE').maybeSingle();
  if(associate?.id)await admin.from('employee_roles').insert({employee_id:data.user.id,role_id:associate.id,assigned_by:user.id});
  await admin.from('audit_logs').insert({actor_id:user.id,module:'EMPLOYEES',action:'INVITE',record_id:data.user.id,new_value:{email,name}});
  return out({ok:true,user_id:data.user.id},200,o);
 }catch(e){return out({error:e instanceof Error?e.message:'Invitation failed.'},400,o)}
})

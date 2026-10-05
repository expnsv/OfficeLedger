(function(){'use strict';
  const ALLOWED_LENGTHS=[6,8],MAXAGE=30*86400000;
  const SYMBOL=/[^A-Za-z0-9\s]/;
  const EDGE_BASE=window.OFFICELEDGER_CONFIG.supabaseUrl+'/functions/v1';
  function normalizeUsername(v){return String(v||'').trim().toLowerCase();}
  function validateUsername(v){const x=normalizeUsername(v);if(!/^[a-z0-9][a-z0-9._-]{2,31}$/.test(x))throw new Error('Username must be 3–32 characters and use only letters, numbers, dot, underscore or hyphen.');return x;}
  function validatePassword(v){
    if(typeof v!=='string'||!ALLOWED_LENGTHS.includes(v.length))throw new Error('Password must be exactly 6 or 8 characters.');
    if(/\s/.test(v))throw new Error('Password cannot contain spaces.');
    if(!/[A-Z]/.test(v))throw new Error('Password must contain at least one uppercase letter.');
    if(!/[a-z]/.test(v))throw new Error('Password must contain at least one lowercase letter.');
    if(!/[0-9]/.test(v))throw new Error('Password must contain at least one number.');
    if(!SYMBOL.test(v))throw new Error('Password must contain at least one symbol.');
    return true;
  }
  async function resolveUsername(username){
    const name=validateUsername(username),api=OfficeDB.getClient();
    const {data,error}=await api.rpc('resolve_login_username',{p_username:name});
    if(error)throw error;if(!data)throw new Error('Username or password is incorrect.');return data;
  }
  async function bootstrapIfRequired(username,password){
    const name=normalizeUsername(username);
    if(name!=='admin')return false;
    const r=await fetch(EDGE_BASE+'/officeledger-bootstrap-admin',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:name,password})});
    if(r.status===401||r.status===403)return false;
    if(!r.ok)throw new Error('Initial administrator authentication is temporarily unavailable.');
    const data=await r.json();
    if(!data.ok)throw new Error(data.error||'Initial administrator authentication failed.');
    return true;
  }
  async function login(username,password){
    const api=OfficeDB.getClient();
    validateUsername(username);
    const bootstrapped=await bootstrapIfRequired(username,password);
    if(!bootstrapped)validatePassword(password);
    const email=await resolveUsername(username);
    const {data,error}=await api.auth.signInWithPassword({email,password});
    if(error||!data.user)throw new Error('Username or password is incorrect.');
    const ctx=await OfficeDB.bootstrapContext();
    if(!ctx.profile?.is_active){await api.auth.signOut({scope:'local'});throw new Error('This account is disabled or not configured.');}
    return ctx;
  }
  async function restore(){const api=OfficeDB.getClient();const {data:{session}}=await api.auth.getSession();if(!session)return null;try{const ctx=await OfficeDB.bootstrapContext();if(!ctx.profile?.is_active){await api.auth.signOut({scope:'local'});return null;}return ctx;}catch(e){await api.auth.signOut({scope:'local'});throw e;}}
  async function logout(){const {error}=await OfficeDB.getClient().auth.signOut({scope:'local'});if(error)throw error;}
  async function changePassword(current,next){validatePassword(next);if(!current)throw new Error('Current password is required.');const api=OfficeDB.getClient();const u=await OfficeDB.currentUser();if(!u?.email)throw new Error('Authenticated user email is unavailable.');const {error}=await api.auth.updateUser({password:next,current_password:current});if(error)throw error;await OfficeDB.update('profiles',u.id,{password_changed_at:new Date().toISOString()});}
  async function completeInitialPasswordSetup(next){
    validatePassword(next);const api=OfficeDB.getClient();
    const {error}=await api.auth.updateUser({password:next});if(error)throw error;
    const {error:rpcError}=await api.rpc('complete_initial_password_setup');if(rpcError)throw rpcError;
  }
  async function completeRecoveryPassword(next){
    validatePassword(next);const api=OfficeDB.getClient();
    const {error}=await api.auth.updateUser({password:next});if(error)throw error;
    const {data:user}=await api.auth.getUser();if(user?.user?.id)await OfficeDB.update('profiles',user.user.id,{must_change_password:false,password_changed_at:new Date().toISOString()});
  }
  async function sendPasswordReset(identifier){
    const api=OfficeDB.getClient();let email=String(identifier||'').trim();
    if(!email.includes('@'))email=await resolveUsername(email);
    const {error}=await api.auth.resetPasswordForEmail(email,{redirectTo:location.origin+location.pathname+'?recovery=1'});if(error)throw error;
    return true;
  }
  async function adminEmployeeAuth(action,userId,payload={}){
    const api=OfficeDB.getClient();const {data:{session}}=await api.auth.getSession();if(!session)throw new Error('Session expired.');
    const r=await fetch(EDGE_BASE+'/officeledger-admin-employee-auth',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+session.access_token},body:JSON.stringify({action,user_id:userId,...payload})});
    const data=await r.json().catch(()=>({}));if(!r.ok)throw new Error(data.error||'Employee authentication operation failed.');return data;
  }
  window.OfficeAuth={normalizeUsername,validateUsername,validatePassword,resolveUsername,login,restore,logout,changePassword,completeInitialPasswordSetup,completeRecoveryPassword,sendPasswordReset,adminEmployeeAuth,ALLOWED_LENGTHS,MAXAGE};
})();

(function(){
'use strict';
const BUCKET='office-files';let client=null;
function getClient(){
 if(client)return client;
 const c=window.OFFICELEDGER_CONFIG||{};
 if(!c.supabaseUrl||!c.supabasePublishableKey)throw new Error('Supabase is not configured.');
 if(!window.supabase?.createClient)throw new Error('Supabase client library failed to load.');
 client=window.supabase.createClient(c.supabaseUrl,c.supabasePublishableKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true,flowType:'pkce'}});
 return client;
}
function cleanError(e){return e?.message||e?.error_description||e?.details||'Database request failed.'}
async function list(table,opts={}){let q=getClient().from(table).select(opts.select||'*');if(opts.eq)for(const[k,v]of Object.entries(opts.eq))q=q.eq(k,v);if(opts.neq)for(const[k,v]of Object.entries(opts.neq))q=q.neq(k,v);if(opts.order)q=q.order(opts.order,{ascending:opts.ascending??false,nullsFirst:false});if(opts.limit)q=q.limit(opts.limit);if(opts.range)q=q.range(opts.range[0],opts.range[1]);const{data,error}=await q;if(error)throw error;return data||[]}
async function get(table,id){const{data,error}=await getClient().from(table).select('*').eq('id',id).maybeSingle();if(error)throw error;return data}
async function insert(table,row){const{data,error}=await getClient().from(table).insert(row).select('*').single();if(error)throw error;return data}
async function update(table,id,row){const{data,error}=await getClient().from(table).update(row).eq('id',id).select('*').single();if(error)throw error;return data}
async function remove(table,id){const{error}=await getClient().from(table).delete().eq('id',id);if(error)throw error;return true}
async function rpc(fn,args={}){const{data,error}=await getClient().rpc(fn,args);if(error)throw error;return data}
async function upload(file,path){if(!file)throw new Error('File is missing.');if(file.size>25*1024*1024)throw new Error('Maximum file size is 25 MB.');const{error}=await getClient().storage.from(BUCKET).upload(path,file,{upsert:false,contentType:file.type||'application/octet-stream',cacheControl:'3600'});if(error)throw error;return path}
async function download(path){if(!path)throw new Error('File path is missing.');const{data,error}=await getClient().storage.from(BUCKET).download(path);if(error)throw error;return data}
async function removeFile(path){if(!path)return;const{error}=await getClient().storage.from(BUCKET).remove([path]);if(error)throw error}
async function currentUser(){const{data,error}=await getClient().auth.getUser();if(error)throw error;return data.user||null}
async function myProfile(){const u=await currentUser();if(!u)return null;const{data,error}=await getClient().from('profiles').select('*').eq('user_id',u.id).maybeSingle();if(error)throw error;return data}
async function myRoles(){const u=await currentUser();if(!u)return[];const{data,error}=await getClient().from('employee_roles').select('role_id,roles(id,code,name,description)').eq('employee_id',u.id);if(error)throw error;return(data||[]).map(x=>x.roles).filter(Boolean)}
async function myPermissions(){const u=await currentUser();if(!u)return[];const{data,error}=await getClient().from('employee_roles').select('roles(role_permissions(scope,permissions(code,module,action,field_name)))').eq('employee_id',u.id);if(error)throw error;const out=[];(data||[]).forEach(er=>(er.roles?.role_permissions||[]).forEach(rp=>{if(rp.permissions)out.push({...rp.permissions,scope:rp.scope})}));return out}
async function myDepartments(){const u=await currentUser();if(!u)return[];const{data,error}=await getClient().from('employee_departments').select('department_id,departments(id,code,name)').eq('employee_id',u.id);if(error)throw error;return(data||[]).map(x=>x.departments).filter(Boolean)}
async function bootstrapContext(){const[profile,roles,permissions,departments]=await Promise.all([myProfile(),myRoles(),myPermissions(),myDepartments()]);if(!profile)throw new Error('Employee profile is not configured.');return{profile,roles,permissions,departments}}
function subscribe(table,event,callback){const channel=getClient().channel(`officeledger:${table}:${crypto.randomUUID()}`).on('postgres_changes',{event, schema:'public',table},payload=>callback(payload));channel.subscribe();return()=>{getClient().removeChannel(channel)}}
window.OfficeDB={getClient,list,get,insert,update,remove,rpc,upload,download,removeFile,currentUser,bootstrapContext,cleanError,subscribe,BUCKET};
})();

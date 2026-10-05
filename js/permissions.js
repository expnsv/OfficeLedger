(function(){'use strict';
  const state={permissions:[],roles:[],departments:[]};
  function set(ctx){state.permissions=ctx?.permissions||[];state.roles=ctx?.roles||[]; state.departments=ctx?.departments||[];}
  function isAdmin(){return state.roles.some(r=>r.code==='ADMIN');}
  function has(code,action,scope){return state.permissions.some(p=>p.code===code&&(!action||p.action===action)&&(!scope||p.scope===scope));}
  function any(code,action){return state.permissions.some(p=>p.code===code&&(!action||p.action===action));}
  function field(code){return state.permissions.some(p=>p.code===code&&p.field_name===code.split(':')[1]);}
  function roles(){return state.roles;}
  function departments(){return state.departments;}
  function inDepartment(code){return isAdmin()||state.departments.some(d=>d.code===code);}
  window.OfficePermissions={set,isAdmin,has,any,field,roles,departments,inDepartment,state};
})();

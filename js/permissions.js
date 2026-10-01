/* Authorization rules are checked in the data mutation path, not only in the UI. */
(function(){
  'use strict';
  function isAdmin(user){return user?.role==='ADMIN';}
  function canSee(user,record){if(!user||!record||record.archivedAt)return false;if(isAdmin(user))return true;if(record.category==='Salaries')return record.employeeId===user.id;return true;}
  function canCreate(user,category){return Boolean(user&&user.active&&['ADMIN','EMPLOYEE'].includes(user.role)&&(category!=='Salaries'||isAdmin(user)));}
  function canUpdate(user,record){if(!user||!record||record.archivedAt)return false;if(isAdmin(user))return true;if(record.category==='Salaries')return record.employeeId===user.id;if(record.createdBy!==user.id)return false;return true;}
  function canDelete(user){return isAdmin(user);}
  function assertCreate(user,category){if(!canCreate(user,category))throw new Error(category==='Salaries'?'Only an Admin can create salary records.':'You do not have permission to add accounting entries.');}
  function assertUpdate(user,record){if(!canUpdate(user,record))throw new Error('You can update only entries you created. Salary entries are limited to your own account.');}
  function assertDelete(user){if(!canDelete(user))throw new Error('Employees cannot delete or archive accounting records. Ask an Admin for help.');}
  function assertAdmin(user,action='perform this action'){if(!isAdmin(user))throw new Error(`Only an Admin can ${action}.`);}
  function assertEmployeeSalaryUpdate(user,oldRecord,newRecord){if(user.role!=='EMPLOYEE'||oldRecord.category!=='Salaries')return;for(const key of ['employeeId','grossSalary','deductions','amount','salaryMonth'])if(String(oldRecord[key]??'')!==String(newRecord[key]??''))throw new Error('Employees may update salary payment details only. Ask an Admin to change salary amounts.');}
  window.OfficePermissions={isAdmin,canSee,canCreate,canUpdate,canDelete,assertCreate,assertUpdate,assertDelete,assertAdmin,assertEmployeeSalaryUpdate};
})();

/* Domain rules and calculations. Every screen and report reads these shared records. */
(function(){
  'use strict';
  const CATEGORIES=[
    {id:'Rent',name:'Rent',icon:'⌂',group:'Office costs'},
    {id:'Electricity',name:'Electricity',icon:'ϟ',group:'Office costs'},
    {id:'Salaries',name:'Salaries',icon:'♙',group:'People'},
    {id:'GST',name:'GST',icon:'%',group:'Tax'},
    {id:'Petty Cash',name:'Petty Cash',icon:'₹',group:'Cash'},
    {id:'Client Expenses',name:'Client Expenses',icon:'◇',group:'Client costs'},
    {id:'Refunded Payments',name:'Refunded Payments',icon:'↶',group:'Client costs'},
    {id:'Wi-Fi',name:'Wi-Fi',icon:'⌁',group:'Office costs'},
    {id:'Flat Maintenance',name:'Flat Maintenance',icon:'⌂',group:'Facilities'},
    {id:'Washroom Cleaning',name:'Washroom Cleaning',icon:'✦',group:'Facilities'},
    {id:'Drinking Water Supply',name:'Drinking Water Supply',icon:'◌',group:'Facilities'},
    {id:'Cleaner Expenses & Maintenance',name:'Cleaner Expenses & Maintenance',icon:'✧',group:'Facilities'},
    {id:'Tea Maker Expenses & Maintenance',name:'Tea Maker Expenses & Maintenance',icon:'☕',group:'Facilities'}
  ];
  const CATEGORY_MAP=Object.fromEntries(CATEGORIES.map(c=>[c.id,c]));
  const PAYMENT_METHODS=['Bank transfer','Cash','Card','Cheque','UPI','Other'];
  const PETTY_CASH_CATEGORIES=['Office supplies','Travel','Meals','Postage','Repairs','Transport','Washroom Cleaning','Drinking Water Supply','Cleaner Expenses & Maintenance','Tea Maker Expenses & Maintenance','Other'];
  const DEFAULT_SETTINGS={id:'main',companyName:'Office',currency:'INR',openingPettyCash:0};
  const today=()=>{const d=new Date();d.setMinutes(d.getMinutes()-d.getTimezoneOffset());return d.toISOString().slice(0,10);};
  const id=()=>crypto.randomUUID();
  function dateObj(s){const [y,m,d]=String(s||today()).slice(0,10).split('-').map(Number);return new Date(y,m-1,d,12);}
  function iso(d){return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;}
  function mondayOf(s){const d=dateObj(s);d.setDate(d.getDate()-((d.getDay()+6)%7));return iso(d);}
  function plusDays(s,n){const d=dateObj(s);d.setDate(d.getDate()+n);return iso(d);}
  function monthEnd(s){const d=dateObj(`${String(s).slice(0,7)}-01`);d.setMonth(d.getMonth()+1);d.setDate(0);return iso(d);}
  function formatDate(s,opts={month:'short',day:'numeric',year:'numeric'}){if(!s)return '—';return new Intl.DateTimeFormat(undefined,opts).format(dateObj(s));}
  function currencyCode(settings){return /^[A-Z]{3}$/.test(String(settings?.currency||''))?settings.currency:'INR';}
  function money(value,settings){const code=currencyCode(settings);try{return new Intl.NumberFormat(code==='INR'?'en-IN':undefined,{style:'currency',currency:code,minimumFractionDigits:2,maximumFractionDigits:2}).format(Number(value)||0);}catch{return `${code} ${(Number(value)||0).toFixed(2)}`;}}
  function cleanRecords(records){return records.filter(r=>!r.archivedAt);}
  function recordMonth(r){return (r.salaryMonth||r.month||r.billingMonth||r.gstPeriod||r.date||'').slice(0,7);}
  function recordPeriodDate(r){return r.date||r.paymentDate||r.createdAt?.slice(0,10)||'';}
  function refundTotalFor(originalId,records){return records.filter(r=>!r.archivedAt&&r.category==='Refunded Payments'&&r.originalRecordId===originalId).reduce((s,r)=>s+(Number(r.amount)||0),0);}
  function outstandingForClientExpense(expense,records){if(!expense.reimbursable)return 0;return Math.max(0,(Number(expense.amount)||0)-refundTotalFor(expense.id,records));}
  function totalRefunded(records){return cleanRecords(records).filter(r=>r.category==='Refunded Payments').reduce((s,r)=>s+(Number(r.amount)||0),0);}
  function totalClientExpenses(records){return cleanRecords(records).filter(r=>r.category==='Client Expenses').reduce((s,r)=>s+(Number(r.amount)||0),0);}
  function pendingReimbursements(records){return cleanRecords(records).filter(r=>r.category==='Client Expenses'&&r.reimbursable).reduce((s,r)=>s+outstandingForClientExpense(r,records),0);}
  function isOfficeExpense(r){return !r.archivedAt&&r.category!=='Refunded Payments'&&!(r.category==='Petty Cash'&&r.cashDirection==='Received');}
  function totalExpenses(records){return cleanRecords(records).filter(isOfficeExpense).reduce((s,r)=>s+(Number(r.amount)||0),0);}
  function netOfficeExpenses(records){return totalExpenses(records)-totalRefunded(records);}
  function pettyTotals(records){const rows=cleanRecords(records).filter(r=>r.category==='Petty Cash');const received=rows.filter(r=>r.cashDirection==='Received').reduce((s,r)=>s+(Number(r.amount)||0),0);const spent=rows.filter(r=>r.cashDirection==='Spent').reduce((s,r)=>s+(Number(r.amount)||0),0);return {received,spent};}
  function pettyBalance(records,settings){const p=pettyTotals(records);return (Number(settings?.openingPettyCash)||0)+p.received-p.spent;}
  function totalForCategory(records,category,month=null){return cleanRecords(records).filter(r=>r.category===category&&(!month||recordMonth(r)===month)&&!(category==='Petty Cash'&&r.cashDirection==='Received')).reduce((s,r)=>s+(Number(r.amount)||0),0);}
  function monthlySummary(records,month){const byCategory={};for(const c of CATEGORIES)byCategory[c.id]=totalForCategory(records,c.id,month);const refunded=byCategory['Refunded Payments']||0;const total=Object.values(byCategory).reduce((a,b)=>a+b,0);const totalExpenses=total-refunded;const clientExpense=byCategory['Client Expenses']||0;return {month,byCategory,totalExpenses,clientExpense,refunded,netOfficeExpenses:totalExpenses-refunded,pendingReimbursements:cleanRecords(records).filter(r=>r.category==='Client Expenses'&&recordMonth(r)===month&&r.reimbursable).reduce((s,r)=>s+outstandingForClientExpense(r,records),0),salary:byCategory.Salaries||0};}
  function dateRangeForPreset(preset,anchor=today()){
    const d=dateObj(anchor),startMonth=`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-01`;
    if(preset==='Today')return {from:anchor,to:anchor};
    if(preset==='This week'){const from=mondayOf(anchor);return {from,to:plusDays(from,6)};}
    if(preset==='This month')return {from:startMonth,to:monthEnd(anchor)};
    if(preset==='Previous month'){const first=dateObj(startMonth);first.setMonth(first.getMonth()-1);const from=iso(first);return {from,to:monthEnd(from)};}
    return {from:'',to:''};
  }
  function lastMonths(count=6,anchor=today()){const end=dateObj(`${anchor.slice(0,7)}-01`);const out=[];for(let i=count-1;i>=0;i--){const d=new Date(end);d.setMonth(d.getMonth()-i);out.push(`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`);}return out;}
  function clientOutstandingRows(records){return cleanRecords(records).filter(r=>r.category==='Client Expenses'&&r.reimbursable&&outstandingForClientExpense(r,records)>0.005).map(r=>({...r,refundedAmount:refundTotalFor(r.id,records),outstanding:outstandingForClientExpense(r,records)}));}
  function canRefund(expense,records){return expense&&expense.category==='Client Expenses'&&expense.reimbursable&&outstandingForClientExpense(expense,records)>0.005;}
  function buildLedgerRow(r,users,records){const created=users.find(u=>u.id===r.createdBy);const debit=(r.category==='Refunded Payments'||(r.category==='Petty Cash'&&r.cashDirection==='Received'))?0:Number(r.amount)||0;const credit=(r.category==='Refunded Payments'||(r.category==='Petty Cash'&&r.cashDirection==='Received'))?Number(r.amount)||0:0;const direction=credit?'Credit':'Debit';return {date:recordPeriodDate(r),id:r.transactionId||r.id,category:r.category,description:r.description||r.remarks||r.subcategory||r.category,debit,credit,amount:Number(r.amount)||0,paymentMethod:r.paymentMethod||'—',reference:r.referenceNumber||'—',createdBy:created?.name||r.createdByName||'—',status:r.status||'Paid',client:r.client||'',project:r.project||'',employee:r.employeeName||r.person||'',vendor:r.vendor||r.payee||'',direction,record:r};}
  window.OfficeAccounting={CATEGORIES,CATEGORY_MAP,PAYMENT_METHODS,PETTY_CASH_CATEGORIES,DEFAULT_SETTINGS,today,id,dateObj,iso,mondayOf,plusDays,monthEnd,formatDate,currencyCode,money,cleanRecords,recordMonth,recordPeriodDate,refundTotalFor,outstandingForClientExpense,totalRefunded,totalClientExpenses,pendingReimbursements,totalExpenses,netOfficeExpenses,pettyTotals,pettyBalance,totalForCategory,monthlySummary,dateRangeForPreset,lastMonths,clientOutstandingRows,canRefund,buildLedgerRow,isOfficeExpense};
})();

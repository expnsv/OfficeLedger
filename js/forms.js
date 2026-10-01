/* Category-specific entry forms. Shared field definitions live here once. */
(function () {
  'use strict';

  function field(name, label, type = 'text', options = {}) {
    return { name, label, type, ...options };
  }

  function fieldsFor(category, context = {}) {
    const accounting = context.accounting || window.OfficeAccounting;
    const user = context.user;
    const users = context.users || [];
    const records = context.records || [];
    const record = context.record || null;
    const formatMoney = context.formatMoney || (value => accounting.money(value));
    const payment = field('paymentMethod', 'Payment method', 'select', { required: true, options: accounting.PAYMENT_METHODS });
    const status = field('status', 'Status', 'select', { required: true, options: ['Paid', 'Pending'] });
    const reference = field('referenceNumber', 'Reference number', 'text', { maxLength: 80 });
    const remarks = field('remarks', 'Remarks', 'textarea', { full: true, maxLength: 500 });
    const attachment = field('attachmentFile', 'Attachment', 'file', {
      full: true,
      accept: '.pdf,.png,.jpg,.jpeg,.webp,.doc,.docx,.xls,.xlsx',
      help: record?.attachmentName ? `Current attachment: ${record.attachmentName}` : 'Optional. Stored in private shared file storage.'
    });

    let fields;
    switch (category) {
      case 'Rent':
        fields = [field('month', 'Month', 'month', { required: true }), field('property', 'Property / flat', 'text', { required: true, maxLength: 100 }), field('date', 'Paid date', 'date', { required: true }), field('amount', 'Amount', 'number', { required: true, min: 0.01, step: 0.01 }), field('vendor', 'Payee / landlord', 'text', { maxLength: 100 }), payment, reference, status, remarks, attachment];
        break;
      case 'Electricity':
        fields = [field('billingMonth', 'Billing month', 'month', { required: true }), field('meterFlat', 'Meter / flat', 'text', { maxLength: 100 }), field('billNumber', 'Bill number', 'text', { maxLength: 80 }), field('dueDate', 'Due date', 'date'), field('date', 'Paid date', 'date'), field('amount', 'Bill amount', 'number', { required: true, min: 0.01, step: 0.01 }), field('vendor', 'Provider', 'text', { maxLength: 100 }), payment, reference, status, remarks, attachment];
        break;
      case 'Salaries': {
        const employees = users.filter(person => person.role === 'EMPLOYEE');
        const allowed = user?.role === 'EMPLOYEE' ? employees.filter(person => person.id === user.id) : employees;
        fields = [field('employeeId', 'Employee', 'select', { required: true, options: allowed.map(person => [person.id, person.name]), disabled: user?.role === 'EMPLOYEE' }), field('salaryMonth', 'Salary month', 'month', { required: true, disabled: user?.role === 'EMPLOYEE' && Boolean(record) }), field('grossSalary', 'Gross salary', 'number', { required: true, min: 0, step: 0.01, disabled: user?.role === 'EMPLOYEE' && Boolean(record) }), field('deductions', 'Deductions', 'number', { required: true, min: 0, step: 0.01, disabled: user?.role === 'EMPLOYEE' && Boolean(record) }), field('netComputed', 'Net salary', 'computed', { full: true }), field('date', 'Payment date', 'date'), field('status', 'Payment status', 'select', { required: true, options: ['Pending', 'Paid'] }), payment, reference, remarks, attachment];
        break;
      }
      case 'GST':
        fields = [field('gstPeriod', 'GST period', 'month', { required: true }), field('gstType', 'GST type', 'select', { required: true, options: ['GST payment', 'Input tax credit', 'Output tax', 'Return filing', 'Other'] }), field('taxableAmount', 'Taxable amount', 'number', { min: 0, step: 0.01 }), field('amount', 'GST amount', 'number', { required: true, min: 0.01, step: 0.01 }), field('date', 'Filing / payment date', 'date'), field('dueDate', 'Due date', 'date'), field('status', 'Filing status', 'select', { required: true, options: ['Pending', 'Filed', 'Paid'] }), payment, reference, remarks, attachment];
        break;
      case 'Petty Cash':
        fields = [field('cashDirection', 'Movement', 'select', { required: true, options: ['Spent', 'Received'] }), field('date', 'Date', 'date', { required: true }), field('subcategory', 'Transaction category', 'select', { required: true, options: accounting.PETTY_CASH_CATEGORIES }), field('amount', 'Amount', 'number', { required: true, min: 0.01, step: 0.01 }), field('person', 'Person responsible', 'text', { required: true, maxLength: 80 }), payment, reference, field('description', 'Description', 'text', { required: true, maxLength: 160 }), status, attachment];
        break;
      case 'Client Expenses':
        fields = [field('client', 'Client', 'text', { required: true, maxLength: 100 }), field('project', 'Project', 'text', { required: true, maxLength: 100 }), field('expenseType', 'Expense type', 'text', { required: true, maxLength: 80 }), field('date', 'Expense date', 'date', { required: true }), field('amount', 'Expense amount', 'number', { required: true, min: 0.01, step: 0.01 }), field('paidBy', 'Paid by', 'select', { required: true, options: ['Company', 'Employee', 'Client'] }), field('person', 'Employee / person', 'text', { maxLength: 80 }), field('reimbursable', 'Reimbursable?', 'checkbox'), field('refundRequested', 'Refund requested?', 'checkbox'), payment, reference, status, remarks, attachment];
        break;
      case 'Refunded Payments': {
        const eligible = records.filter(item => item.category === 'Client Expenses' && item.reimbursable && !item.archivedAt && (accounting.canRefund(item, records) || item.id === record?.originalRecordId));
        const options = eligible.map(item => {
          const editCredit = record?.originalRecordId === item.id ? Number(record.amount) || 0 : 0;
          return [item.id, `${item.transactionId} · ${item.client} · ${formatMoney(accounting.outstandingForClientExpense(item, records) + editCredit)} due`];
        });
        fields = [field('originalRecordId', 'Original client expense', 'select', { required: true, options }), field('refundInfo', 'Original expense', 'computed', { full: true }), field('date', 'Refund received date', 'date', { required: true }), field('amount', 'Refund amount', 'number', { required: true, min: 0.01, step: 0.01 }), payment, reference, field('reason', 'Reason / note', 'text', { required: true, maxLength: 160 }), attachment];
        break;
      }
      default:
        if (!accounting.CATEGORY_MAP[category]) throw new Error(`Unknown accounting category: ${category}`);
        fields = [field('date', 'Date', 'date', { required: true }), field('dueDate', 'Due date', 'date'), field('vendor', 'Vendor / person', 'text', { required: true, maxLength: 100 }), field('amount', 'Amount', 'number', { required: true, min: 0.01, step: 0.01 }), payment, reference, field('description', 'Description', 'text', { required: true, maxLength: 160 }), status, attachment];
    }

    const names = new Set();
    for (const item of fields) {
      if (names.has(item.name)) throw new Error(`Duplicate field “${item.name}” in the ${category} form.`);
      names.add(item.name);
    }
    return fields;
  }

  window.OfficeForms = { fieldsFor };
})();

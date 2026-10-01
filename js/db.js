/* Supabase data adapter. Role enforcement lives in Postgres RLS and triggers. */
(function () {
  'use strict';

  const ATTACHMENT_BUCKET = 'office-attachments';
  const COMMON_KEYS = new Set([
    'id', 'transactionId', 'category', 'date', 'amount', 'paymentMethod', 'referenceNumber',
    'description', 'createdBy', 'createdByName', 'createdAt', 'updatedBy', 'updatedByName',
    'updatedAt', 'status', 'client', 'project', 'vendor', 'person', 'employeeId',
    'originalRecordId', 'archivedAt', 'archivedBy', 'attachmentId', 'attachmentName', 'attachmentPath', 'paymentDate'
  ]);
  let client = null;

  function config() {
    const value = window.OFFICELEDGER_CONFIG || {};
    const url = String(value.supabaseUrl || '').trim();
    const key = String(value.supabasePublishableKey || '').trim();
    if (!url || !key) throw new Error('Supabase is not configured yet. Add your project URL and publishable key to js/config.js.');
    let parsed;
    try { parsed = new URL(url); } catch { throw new Error('The Supabase project URL in js/config.js is invalid.'); }
    if (parsed.protocol !== 'https:' && !['localhost', '127.0.0.1'].includes(parsed.hostname)) {
      throw new Error('Supabase must use HTTPS outside local development.');
    }
    let containsServerSecret = /service[_-]?role|sb_secret_/i.test(key);
    if (!containsServerSecret && key.split('.').length === 3) {
      try { containsServerSecret = JSON.parse(atob(key.split('.')[1])).role === 'service_role'; } catch { /* Not a legacy JWT key. */ }
    }
    if (containsServerSecret) throw new Error('A server secret was placed in browser configuration. Remove it and use the publishable key only.');
    if (!window.supabase?.createClient) throw new Error('The Supabase JavaScript library could not load. Check the network connection.');
    return { url: parsed.origin, key };
  }

  function getClient() {
    if (client) return client;
    const settings = config();
    client = window.supabase.createClient(settings.url, settings.key, {
      auth: { storage: window.sessionStorage, persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
    });
    return client;
  }

  async function open() {
    getClient();
    window.OfficeAuth?.bindAuthEvents?.();
    return true;
  }

  function userFromRow(row) {
    if (!row) return null;
    return { id: row.user_id, name: row.display_name, email: row.email, username: row.email, role: row.role,
      active: Boolean(row.is_active), createdAt: row.created_at, updatedAt: row.updated_at };
  }

  function recordFromRow(row) {
    if (!row) return null;
    return { ...(row.details || {}), id: row.id, transactionId: row.transaction_id, category: row.category,
      date: row.record_date, amount: Number(row.amount), paymentMethod: row.payment_method || '',
      referenceNumber: row.reference_number || '', description: row.description || '', createdBy: row.created_by,
      createdByName: row.created_by_name, createdAt: row.created_at, updatedBy: row.updated_by,
      updatedByName: row.updated_by_name, updatedAt: row.updated_at, status: row.status || '',
      client: row.client || '', project: row.project || '', vendor: row.vendor || '', person: row.person || '',
      employeeId: row.employee_id, originalRecordId: row.related_record_id, archivedAt: row.archived_at,
      archivedBy: row.archived_by, attachmentId: row.attachment_id, attachmentName: row.attachment_name,
      attachmentPath: row.attachment_path };
  }

  function recordToRow(item) {
    const sourceDate = item.date || item.paymentDate || item.createdAt?.slice(0, 10) || new Date().toISOString().slice(0, 10);
    const details = {};
    for (const [key, value] of Object.entries(item)) {
      if (!COMMON_KEYS.has(key) && key !== 'type' && value !== undefined) details[key] = value;
    }
    return { id: item.id, transaction_id: String(item.transactionId || '').trim(), category: item.category,
      record_date: sourceDate, amount: Number(item.amount) || 0, payment_method: item.paymentMethod || null,
      reference_number: item.referenceNumber || null, description: item.description || null,
      created_by: item.createdBy || null, created_by_name: item.createdByName || '', created_at: item.createdAt || undefined,
      status: item.status || null, client: item.client || null, project: item.project || null,
      vendor: item.vendor || item.payee || null, person: item.person || null,
      employee_id: item.employeeId || null, related_record_id: item.originalRecordId || null,
      archived_at: item.archivedAt || null, archived_by: item.archivedBy || null,
      attachment_id: item.attachmentId || null, attachment_name: item.attachmentName || null,
      attachment_path: item.attachmentPath || null, details };
  }

  function auditFromRow(row) {
    return { id: row.id, userId: row.actor_id, userName: row.actor_name, role: row.actor_role,
      action: row.action, recordId: row.record_id, category: row.category,
      previousValue: row.previous_value, newValue: row.new_value, timestamp: row.occurred_at };
  }

  function settingsFromRow(row) {
    return row ? { id: row.id, companyName: row.company_name, currency: row.currency,
      openingPettyCash: Number(row.opening_petty_cash), updatedBy: row.updated_by, updatedAt: row.updated_at } : null;
  }

  async function allRows(table, orderColumn) {
    const api = getClient(), rows = [], pageSize = 500;
    for (let offset = 0; ; offset += pageSize) {
      let request = api.from(table).select('*').range(offset, offset + pageSize - 1);
      if (orderColumn) request = request.order(orderColumn, { ascending: false }).order(table === 'profiles' ? 'user_id' : 'id', { ascending: true });
      const { data, error } = await request;
      if (error) throw error;
      rows.push(...(data || []));
      if (!data || data.length < pageSize) return rows;
    }
  }

  async function getAll(store) {
    if (store === 'users') return (await allRows('profiles', 'created_at')).map(userFromRow);
    if (store === 'records') return (await allRows('records', 'record_date')).map(recordFromRow);
    if (store === 'audit') return (await allRows('audit_events', 'occurred_at')).map(auditFromRow);
    if (store === 'settings') {
      const { data, error } = await getClient().from('settings').select('*').eq('id', 'main').limit(1);
      if (error) throw error;
      return (data || []).map(settingsFromRow);
    }
    if (store === 'attachments') return [];
    throw new Error(`Unknown data area: ${store}`);
  }

  async function get(store, id) {
    const api = getClient();
    if (store === 'users') {
      const { data, error } = await api.from('profiles').select('*').eq('user_id', id).maybeSingle();
      if (error) throw error;
      return userFromRow(data);
    }
    if (store === 'records') {
      const { data, error } = await api.from('records').select('*').eq('id', id).maybeSingle();
      if (error) throw error;
      return recordFromRow(data);
    }
    if (store === 'settings' && id === 'main') {
      const { data, error } = await api.from('settings').select('*').eq('id', 'main').maybeSingle();
      if (error) throw error;
      return settingsFromRow(data);
    }
    return null;
  }

  async function count(store) { return (await getAll(store)).length; }

  async function commit(store, item) {
    const api = getClient();
    if (store === 'records') {
      const row = recordToRow(item);
      const existing = await get('records', item.id);
      let request;
      if (existing) {
        for (const key of ['id', 'transaction_id', 'category', 'created_by', 'created_by_name', 'created_at']) delete row[key];
        request = api.from('records').update(row).eq('id', item.id);
      } else {
        request = api.from('records').insert(row);
      }
      const { data, error } = await request.select('*').single();
      if (error) throw error;
      return recordFromRow(data);
    }
    if (store === 'users') {
      const { data, error } = await api.from('profiles').update({
        is_active: Boolean(item.active), display_name: String(item.name || '').trim()
      }).eq('user_id', item.id).select('*').single();
      if (error) throw error;
      return userFromRow(data);
    }
    if (store === 'settings') return commitSetting(item);
    throw new Error('This data area cannot be edited directly.');
  }

  async function commitSetting(item) {
    const row = { company_name: String(item.companyName || 'Office').trim(),
      currency: item.currency, opening_petty_cash: Number(item.openingPettyCash) || 0, updated_by: item.updatedBy || null };
    const { data, error } = await getClient().from('settings').update(row).eq('id', 'main').select('*').single();
    if (error) throw error;
    return settingsFromRow(data);
  }

  async function addAttachment(item) {
    const api = getClient();
    const { data: { user }, error: userError } = await api.auth.getUser();
    if (userError || !user) throw new Error('Sign in before adding an attachment.');
    if (!item?.blob || item.blob.size > 4 * 1024 * 1024) throw new Error('Attachment is missing or larger than 4 MB.');
    const id = crypto.randomUUID(), path = `${user.id}/${id}`;
    const { error } = await api.storage.from(ATTACHMENT_BUCKET).upload(path, item.blob, {
      contentType: item.mimeType || 'application/octet-stream', upsert: false
    });
    if (error) throw error;
    return { id, path, fileName: String(item.fileName || 'attachment').slice(0, 180),
      mimeType: item.mimeType || 'application/octet-stream', uploadedBy: user.id };
  }

  async function attachmentMetadata(id) {
    const { data, error } = await getClient().from('records')
      .select('attachment_id, attachment_path, attachment_name').eq('attachment_id', id).limit(1).maybeSingle();
    if (error) throw error;
    return data;
  }

  async function getAttachment(id) {
    if (!id) return null;
    const item = await attachmentMetadata(id);
    if (!item?.attachment_path) return null;
    const { data, error } = await getClient().storage.from(ATTACHMENT_BUCKET).download(item.attachment_path);
    if (error) throw error;
    return { id: item.attachment_id, fileName: item.attachment_name || 'attachment', blob: data };
  }

  async function deleteAttachmentPath(path) {
    if (!path) return;
    const { error } = await getClient().storage.from(ATTACHMENT_BUCKET).remove([path]);
    if (error) throw error;
  }

  async function commitBusinessImport(records, settings) {
    const api = getClient(), actor = await OfficeAuth.restoreSession();
    if (!actor || actor.role !== 'ADMIN') throw new Error('Only an Admin can import a backup.');
    const profiles = await getAll('users'), knownUsers = new Set(profiles.map(person => person.id));
    const existing = await getAll('records');
    const knownIds = new Set(existing.map(record => record.id));
    const knownTransactions = new Set(existing.map(record => record.transactionId));
    let imported = 0;
    const pendingArchive = [];
    const insertOrder = [...records].sort((a, b) => Number(a.category === 'Refunded Payments') - Number(b.category === 'Refunded Payments'));
    for (const source of insertOrder) {
      if (knownIds.has(source.id) || knownTransactions.has(source.transactionId)) continue;
      const item = { ...source, legacyCreatedByName: source.createdByName || '', legacyCreatedAt: source.createdAt || null,
        createdBy: actor.id, createdByName: actor.name, archivedAt: null, archivedBy: null };
      if (item.employeeId && !knownUsers.has(item.employeeId)) item.employeeId = actor.id;
      const { error } = await api.from('records').insert(recordToRow(item));
      if (error) throw error;
      knownIds.add(item.id);
      knownTransactions.add(item.transactionId);
      if (source.archivedAt) pendingArchive.push({ id: item.id, at: source.archivedAt });
      imported += 1;
    }
    for (const archived of pendingArchive.sort((a, b) => Number(records.find(r => r.id === a.id)?.category !== 'Refunded Payments') - Number(records.find(r => r.id === b.id)?.category !== 'Refunded Payments'))) {
      const { error } = await api.from('records').update({ archived_at: archived.at, archived_by: actor.id }).eq('id', archived.id);
      if (error) throw error;
    }
    if (settings?.[0]) await commitSetting(settings[0]);
    return { imported };
  }

  window.OfficeDB = { open, getAll, get, count, commit, commitSetting, addAttachment, getAttachment,
    deleteAttachmentPath, commitBusinessImport, getClient, recordFromRow, recordToRow };
})();

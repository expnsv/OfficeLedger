(function () {
  'use strict';
  const DB_NAME = 'officeledger-db';
  const STORE_NAMES = ['users', 'records', 'audit', 'settings', 'attachments'];
  const button = document.getElementById('exportButton');
  const status = document.getElementById('status');

  function readStore(db, name) {
    return new Promise((resolve, reject) => {
      const request = db.transaction(name, 'readonly').objectStore(name).getAll();
      request.onsuccess = () => resolve(request.result || []);
      request.onerror = () => reject(request.error || new Error('Could not read local OfficeLedger data.'));
    });
  }

  function sanitize(value) {
    if (Array.isArray(value)) return value.map(sanitize);
    if (!value || typeof value !== 'object') return value;
    const out = {};
    for (const [key, item] of Object.entries(value)) {
      if (!/password|salt|secret|token/i.test(key)) out[key] = sanitize(item);
    }
    return out;
  }

  function openExistingDatabase() {
    return new Promise((resolve, reject) => {
      let missing = false;
      const request = indexedDB.open(DB_NAME);
      request.onupgradeneeded = () => {
        missing = true;
        request.transaction.abort();
      };
      request.onsuccess = () => {
        if (missing) {
          request.result.close();
          reject(new Error('No previous local OfficeLedger database was found in this browser profile.'));
          return;
        }
        resolve(request.result);
      };
      request.onerror = () => reject(missing
        ? new Error('No previous local OfficeLedger database was found in this browser profile.')
        : (request.error || new Error('Could not open the old local database.')));
      request.onblocked = () => reject(new Error('Close the old OfficeLedger tab and try again.'));
    });
  }

  function download(text) {
    const blob = new Blob([text], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `officeledger-legacy-backup-${new Date().toISOString().slice(0, 10)}.json`;
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1500);
  }

  async function exportPreviousData() {
    button.disabled = true;
    status.textContent = 'Reading local accounting records…';
    let db;
    try {
      if (!('indexedDB' in window)) throw new Error('IndexedDB is unavailable in this browser.');
      db = await openExistingDatabase();
      const [users, records, audit, settings, attachments] = await Promise.all(STORE_NAMES.map(name => readStore(db, name)));
      const packedAttachments = [];
      for (const item of attachments) {
        if (!(item.blob instanceof Blob)) continue;
        const data = await new Promise((resolve, reject) => {
          const reader = new FileReader();
          reader.onload = () => resolve(reader.result);
          reader.onerror = () => reject(reader.error || new Error('Could not read an attachment.'));
          reader.readAsDataURL(item.blob);
        });
        packedAttachments.push({ id: item.id, fileName: item.fileName, mimeType: item.mimeType,
          uploadedBy: item.uploadedBy, createdAt: item.createdAt, data });
      }
      const bundle = {
        app: 'OfficeLedger', schemaVersion: 1, exportedAt: new Date().toISOString(),
        settings: settings.find(item => item.id === 'main') || { id: 'main', companyName: 'Office', currency: 'INR', openingPettyCash: 0 },
        users: users.map(user => ({ id: user.id, name: user.name, username: user.username,
          role: user.role, active: Boolean(user.active), createdAt: user.createdAt })),
        records: sanitize(records), audit: sanitize(audit), attachments: packedAttachments
      };
      download(JSON.stringify(bundle, null, 2));
      status.textContent = `Exported ${records.length} accounting record(s) and ${packedAttachments.length} attachment(s). Passwords and local sessions were excluded.`;
    } catch (error) {
      status.textContent = error.message || 'The local data could not be exported.';
      status.classList.add('error');
    } finally {
      db?.close();
      button.disabled = false;
    }
  }

  button.addEventListener('click', exportPreviousData);
})();

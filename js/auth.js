/* Supabase Auth and profile helpers. Authorization is checked again in Postgres. */
(function () {
  'use strict';

  const MIN_PASSWORD_LENGTH = 12;
  const MAX_PASSWORD_LENGTH = 128;
  let recoveryCallback = false;
  let authListenerInstalled = false;

  function safeUser(user) {
    if (!user) return null;
    return { id: user.id, name: user.name, email: user.email, username: user.email, role: user.role,
      active: Boolean(user.active), createdAt: user.createdAt, updatedAt: user.updatedAt };
  }

  function normalizeEmail(value) { return String(value || '').trim().toLowerCase(); }

  function validatePassword(password) {
    if (typeof password !== 'string' || password.length < MIN_PASSWORD_LENGTH || password.length > MAX_PASSWORD_LENGTH) {
      throw new Error(`Use a password between ${MIN_PASSWORD_LENGTH} and ${MAX_PASSWORD_LENGTH} characters.`);
    }
  }

  function validateIdentity(name, email) {
    const cleanName = String(name || '').trim(), cleanEmail = normalizeEmail(email);
    if (!cleanName || cleanName.length > 80) throw new Error('Enter a name no longer than 80 characters.');
    if (cleanEmail.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cleanEmail)) throw new Error('Enter a valid email address.');
    return { name: cleanName, email: cleanEmail };
  }

  function assertAdmin(actor, action) {
    if (actor?.role !== 'ADMIN' || !actor.active) throw new Error(`Only an active Admin can ${action}.`);
  }

  function bindAuthEvents() {
    if (authListenerInstalled) return;
    OfficeDB.getClient().auth.onAuthStateChange(event => {
      if (event === 'PASSWORD_RECOVERY') recoveryCallback = true;
    });
    authListenerInstalled = true;
  }

  async function login(email, password) {
    const normalized = normalizeEmail(email);
    if (normalized.length > 254 || !normalized.includes('@') || typeof password !== 'string' || password.length > MAX_PASSWORD_LENGTH) {
      throw new Error('Email or password is incorrect.');
    }
    const api = OfficeDB.getClient();
    const { data, error } = await api.auth.signInWithPassword({ email: normalized, password });
    if (error || !data.user) throw new Error('Email or password is incorrect.');
    const profile = await OfficeDB.get('users', data.user.id);
    if (!profile?.active || !['ADMIN', 'EMPLOYEE'].includes(profile.role)) {
      await api.auth.signOut({ scope: 'local' });
      throw new Error('This account is disabled or not configured for OfficeLedger. Ask your Admin for help.');
    }
    return safeUser(profile);
  }

  async function restoreSession() {
    const api = OfficeDB.getClient();
    bindAuthEvents();
    const { data: { session }, error } = await api.auth.getSession();
    if (error || !session) return null;
    const { data: { user }, error: userError } = await api.auth.getUser(session.access_token);
    if (userError || !user) {
      await api.auth.signOut({ scope: 'local' });
      return null;
    }
    const profile = await OfficeDB.get('users', user.id);
    if (!profile?.active || !['ADMIN', 'EMPLOYEE'].includes(profile.role)) {
      await api.auth.signOut({ scope: 'local' });
      return null;
    }
    return safeUser(profile);
  }

  async function logout() {
    const { error } = await OfficeDB.getClient().auth.signOut({ scope: 'local' });
    if (error) throw error;
  }

  async function createEmployee({ name, email }, actor) {
    assertAdmin(actor, 'invite employees');
    const identity = validateIdentity(name, email);
    const { error } = await OfficeDB.getClient().functions.invoke('create-employee', { body: identity });
    if (error) throw new Error('The employee invitation could not be sent. Check Edge Function setup and email delivery.');
    return true;
  }

  async function changePassword(user, currentPassword, nextPassword) {
    validatePassword(nextPassword);
    const api = OfficeDB.getClient();
    if (currentPassword) {
      const { error: verifyError } = await api.auth.signInWithPassword({ email: user.email, password: currentPassword });
      if (verifyError) throw new Error('Current password is incorrect.');
    }
    const { data, error } = await api.auth.updateUser({ password: nextPassword });
    if (error) throw error;
    const profile = await OfficeDB.get('users', data.user?.id || user.id);
    return safeUser(profile || user);
  }

  async function resetPassword(userId, actor) {
    assertAdmin(actor, 'send employee password reset links');
    const employee = await OfficeDB.get('users', userId);
    if (!employee || employee.role !== 'EMPLOYEE') throw new Error('Employee account not found.');
    const redirectTo = `${window.location.origin}${window.location.pathname}`;
    const { error } = await OfficeDB.getClient().auth.resetPasswordForEmail(employee.email, { redirectTo });
    if (error) throw error;
    return true;
  }

  async function setActive(userId, active, actor) {
    assertAdmin(actor, 'change employee access');
    const saved = await OfficeDB.get('users', userId);
    if (!saved || saved.role !== 'EMPLOYEE') throw new Error('Employee account not found.');
    const updated = await OfficeDB.commit('users', { ...saved, active: Boolean(active) });
    return safeUser(updated);
  }

  function isRecoveryOrInvite() {
    if (recoveryCallback) return true;
    const hash = new URLSearchParams(window.location.hash.replace(/^#/, ''));
    const query = new URLSearchParams(window.location.search);
    return ['recovery', 'invite'].includes(hash.get('type')) || ['recovery', 'invite'].includes(query.get('type'));
  }

  window.OfficeAuth = { normalizeEmail, safeUser, validateIdentity, validatePassword, login, restoreSession,
    logout, createEmployee, changePassword, resetPassword, setActive, isRecoveryOrInvite, bindAuthEvents };
})();

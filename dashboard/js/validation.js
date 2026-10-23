/* Regras de validação compartilhadas.
 *
 * A fonte da verdade é a tabela public.apps (code_pattern / normalize_upper).
 * O banco valida de novo em devices_before_write() e device_checkin(); este
 * arquivo só antecipa a mensagem para o usuário.
 */
(function () {
  'use strict';

  function normalizeCode(app, value) {
    var v = String(value == null ? '' : value).trim();
    if (app && app.normalize_upper) v = v.toUpperCase();
    return v;
  }

  function patternFor(app) {
    if (!app || !app.code_pattern) return null;
    try {
      return new RegExp(app.code_pattern);
    } catch (_err) {
      return null;
    }
  }

  function validateCode(app, value) {
    var normalized = normalizeCode(app, value);
    var re = patternFor(app);
    if (!normalized) {
      return { ok: false, value: normalized, message: 'Informe o código do aparelho.' };
    }
    if (!re) {
      return { ok: false, value: normalized, message: 'O app está com uma regra de código inválida.' };
    }
    if (!re.test(normalized)) {
      return {
        ok: false,
        value: normalized,
        message:
          'Código inválido para ' +
          (app.name || 'o app') +
          '. ' +
          (app.code_hint || 'Confira o formato permitido.')
      };
    }
    return { ok: true, value: normalized, message: '' };
  }

  function macDigits(value) {
    return String(value == null ? '' : value)
      .replace(/[^0-9A-Fa-f]/g, '')
      .toUpperCase();
  }

  // Formata enquanto digita (aceita parcial, máx. 12 hex).
  function formatMacInput(value) {
    var hex = macDigits(value).slice(0, 12);
    var parts = [];
    for (var i = 0; i < hex.length; i += 2) parts.push(hex.slice(i, i + 2));
    return parts.join(':');
  }

  function normalizeMac(value) {
    var raw = String(value == null ? '' : value).trim();
    if (!raw) return { ok: true, value: null, message: '' };
    var hex = macDigits(raw);
    if (hex.length !== 12) {
      return {
        ok: false,
        value: null,
        message: 'MAC inválido. Use 12 dígitos hexadecimais (AA:BB:CC:DD:EE:FF).'
      };
    }
    var parts = [];
    for (var i = 0; i < 12; i += 2) parts.push(hex.slice(i, i + 2));
    return { ok: true, value: parts.join(':'), message: '' };
  }

  // Comprimento esperado do código, lido da regex do app (ex.: ^[0-9]{6}$ -> 6).
  // Apps novos podem usar outro tamanho sem alterar o frontend.
  function codeLength(app) {
    var pattern = app && app.code_pattern ? String(app.code_pattern) : '';
    var m = pattern.match(/\{(\d+)(?:,\d*)?\}/);
    if (m) {
      var n = Number(m[1]);
      if (n > 0 && n <= 64) return n;
    }
    return 6;
  }

  // Conjunto de caracteres para gerar códigos válidos para a regex do app.
  function codeCharset(app) {
    var pattern = app && app.code_pattern ? String(app.code_pattern) : '';
    var hasUpper = /A-Z/.test(pattern);
    var hasLower = /a-z/.test(pattern);
    var hasDigits = /0-9/.test(pattern) || /\\d/.test(pattern);
    if (hasUpper && hasDigits) return '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (hasLower && hasDigits) return '0123456789abcdefghijklmnopqrstuvwxyz';
    if (hasUpper) return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (hasLower) return 'abcdefghijklmnopqrstuvwxyz';
    if (hasDigits) return '0123456789';
    return '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  }

  function generateCode(app) {
    var re = patternFor(app);
    if (!re) return '';
    var chars = codeCharset(app);
    var len = codeLength(app);
    for (var attempt = 0; attempt < 2000; attempt++) {
      var out = '';
      for (var i = 0; i < len; i++) out += chars.charAt(Math.floor(Math.random() * chars.length));
      if (re.test(out)) return out;
    }
    return '';
  }

  function macMatches(deviceMac, query) {
    var q = macDigits(query);
    if (!q) return false;
    return macDigits(deviceMac).indexOf(q) !== -1;
  }

  function codeMatches(code, query) {
    var q = String(query == null ? '' : query).trim().toUpperCase();
    if (!q) return false;
    return String(code == null ? '' : code).toUpperCase().indexOf(q) !== -1;
  }

  function todayISO() {
    var d = new Date();
    var m = String(d.getMonth() + 1).padStart(2, '0');
    var day = String(d.getDate()).padStart(2, '0');
    return d.getFullYear() + '-' + m + '-' + day;
  }

  function parseDateOnly(iso) {
    if (!iso) return null;
    var p = String(iso).slice(0, 10).split('-');
    if (p.length !== 3) return null;
    var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
    return isNaN(d.getTime()) ? null : d;
  }

  function formatDateBR(iso) {
    var d = parseDateOnly(iso);
    if (!d) return '—';
    return (
      String(d.getDate()).padStart(2, '0') +
      '/' +
      String(d.getMonth() + 1).padStart(2, '0') +
      '/' +
      d.getFullYear()
    );
  }

  function daysUntil(iso) {
    var d = parseDateOnly(iso);
    if (!d) return null;
    var today = parseDateOnly(todayISO());
    return Math.round((d.getTime() - today.getTime()) / 86400000);
  }

  function addDays(iso, days) {
    var base = parseDateOnly(iso) || parseDateOnly(todayISO());
    base.setDate(base.getDate() + days);
    var m = String(base.getMonth() + 1).padStart(2, '0');
    var d = String(base.getDate()).padStart(2, '0');
    return base.getFullYear() + '-' + m + '-' + d;
  }

  function whatsappPhone(phone) {
    var digits = String(phone == null ? '' : phone).replace(/\D/g, '');
    if (!digits) return '';
    if (digits.indexOf('55') === 0 && (digits.length === 12 || digits.length === 13)) return digits;
    if (digits.length === 10 || digits.length === 11) return '55' + digits;
    return digits;
  }

  window.Validation = {
    normalizeCode: normalizeCode,
    validateCode: validateCode,
    normalizeMac: normalizeMac,
    formatMacInput: formatMacInput,
    macDigits: macDigits,
    codeLength: codeLength,
    codeCharset: codeCharset,
    generateCode: generateCode,
    macMatches: macMatches,
    codeMatches: codeMatches,
    todayISO: todayISO,
    formatDateBR: formatDateBR,
    daysUntil: daysUntil,
    addDays: addDays,
    whatsappPhone: whatsappPhone
  };
})();

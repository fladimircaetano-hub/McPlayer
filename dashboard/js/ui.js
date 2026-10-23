/* Utilidades visuais (escaping, modais, toasts, badges e mensagens de erro). */
(function () {
  'use strict';

  function esc(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function qs(sel, root) {
    return (root || document).querySelector(sel);
  }

  function qsa(sel, root) {
    return Array.prototype.slice.call((root || document).querySelectorAll(sel));
  }

  function openModal(id) {
    var el = document.getElementById(id);
    if (!el) return;
    el.classList.add('open');
    document.body.classList.add('modal-open');
    var first = el.querySelector('input:not([type=hidden]), select, textarea, button');
    if (first) setTimeout(function () { first.focus(); }, 30);
  }

  function closeModal(id) {
    var el = document.getElementById(id);
    if (!el) return;
    el.classList.remove('open');
    if (!qs('.modal-overlay.open')) document.body.classList.remove('modal-open');
  }

  function closeAllModals() {
    qsa('.modal-overlay.open').forEach(function (el) { el.classList.remove('open'); });
    document.body.classList.remove('modal-open');
  }

  function toast(message, type, ms) {
    var wrap = document.getElementById('toastWrap');
    if (!wrap) return;
    var el = document.createElement('div');
    el.className = 'toast toast-' + (type || 'ok');
    el.textContent = message;
    wrap.appendChild(el);
    setTimeout(function () {
      el.classList.add('toast-out');
      setTimeout(function () { el.remove(); }, 220);
    }, ms || 4200);
  }

  function badge(status) {
    var s = String(status || 'pending').toLowerCase();
    var map = {
      pending: ['Pendente', 'badge-pending'],
      approved: ['Aprovado', 'badge-approved'],
      blocked: ['Bloqueado', 'badge-blocked'],
      rejected: ['Bloqueado', 'badge-blocked']
    };
    var item = map[s] || [s, 'badge-neutral'];
    return '<span class="badge ' + item[1] + '">' + esc(item[0]) + '</span>';
  }

  function appChip(name) {
    return '<span class="app-chip">' + esc(name || '—') + '</span>';
  }

  function actionLabel(action) {
    var map = {
      insert: 'Inserir',
      update: 'Editar',
      delete: 'Excluir',
      approve: 'Aprovar',
      block: 'Bloquear',
      unblock: 'Liberar',
      link_mac: 'Vincular MAC',
      unlink_mac: 'Desvincular MAC',
      change_mac: 'Editar MAC',
      change_code: 'Editar código',
      list_change: 'Trocar lista'
    };
    return map[action] || action;
  }

  function actionClass(action) {
    if (action === 'insert' || action === 'approve' || action === 'unblock' || action === 'link_mac') return 'act-ok';
    if (action === 'delete' || action === 'block' || action === 'unlink_mac') return 'act-danger';
    return 'act-neutral';
  }

  function entityLabel(entity) {
    var map = { device: 'Aparelho', playlist: 'Lista', client: 'Cliente', app: 'App' };
    return map[entity] || entity || '—';
  }

  function formatDateTime(value) {
    if (!value) return '—';
    var d = new Date(value);
    if (isNaN(d.getTime())) return esc(value);
    return d.toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' });
  }

  function errorMessage(err) {
    var msg =
      (err && (err.message || err.error_description || err.hint || err.details)) ||
      String(err || 'Erro desconhecido.');

    if (
      (err && err.code === '42501') ||
      /permission denied|sem permissão|row-level security/i.test(msg)
    ) {
      return 'Sem permissão de administrador. Entre com uma conta admin.';
    }
    if (/devices_app_code_key|duplicate key.*device_id/i.test(msg)) {
      return 'Já existe um aparelho com este código neste app.';
    }
    if (/devices_app_mac_key|duplicate key.*mac/i.test(msg)) {
      return 'Este MAC já está vinculado a outro aparelho deste app. Desvincule de lá primeiro.';
    }
    if (/apps_name_lower_key|apps_pkey|duplicate key.*apps/i.test(msg)) {
      return 'Já existe um app com este nome (nomes não diferenciam maiúsculas de minúsculas).';
    }
    if (/playlists_app_name_key|duplicate key.*name/i.test(msg) && /playlists/i.test(msg)) {
      return 'Já existe uma lista com este nome neste app.';
    }
    if (/apps.*foreign key|foreign key constraint "(devices|playlists|clients)_app_name_fkey"/i.test(msg)) {
      return 'Este app ainda tem aparelhos, listas ou clientes vinculados. Exclua ou mova esses registros antes.';
    }
    if (/clients_device_fk|violates foreign key/i.test(msg)) {
      return 'O código informado não existe neste app. Cadastre o aparelho primeiro.';
    }
    if (/devices_before_write|Código inválido/i.test(msg)) {
      return msg.replace(/^.*?Código inválido/i, 'Código inválido');
    }
    if (/MAC inválido/i.test(msg)) {
      return 'MAC inválido. Use o formato AA:BB:CC:DD:EE:FF.';
    }
    if (/JWT|token.*expired|not authenticated/i.test(msg)) {
      return 'Sessão expirada. Entre novamente.';
    }
    if (/relation .* does not exist|Could not find the table|schema cache/i.test(msg)) {
      return 'Estrutura do banco não encontrada. Rode os scripts SQL (001_schema.sql) no Supabase.';
    }
    if (/Could not find the function|function .* does not exist/i.test(msg)) {
      return 'Funções do banco não encontradas. Rode o 001_schema.sql no Supabase.';
    }
    return msg;
  }

  function setBusy(btn, busy, busyText) {
    if (!btn) return;
    if (busy) {
      btn.dataset.originalText = btn.textContent;
      btn.textContent = busyText || 'Salvando...';
      btn.disabled = true;
    } else {
      if (btn.dataset.originalText) btn.textContent = btn.dataset.originalText;
      btn.disabled = false;
    }
  }

  function debounce(fn, wait) {
    var t = null;
    return function () {
      var args = arguments;
      var self = this;
      clearTimeout(t);
      t = setTimeout(function () { fn.apply(self, args); }, wait);
    };
  }

  function downloadJSON(filename, data) {
    var blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    var ta = document.createElement('textarea');
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    ta.remove();
    return Promise.resolve();
  }

  function jsonPretty(value) {
    if (value == null) return '—';
    try {
      return JSON.stringify(value, null, 2);
    } catch (_e) {
      return String(value);
    }
  }

  function maskSecret(value) {
    if (!value) return '—';
    return '••••••••';
  }

  window.UI = {
    esc: esc,
    qs: qs,
    qsa: qsa,
    openModal: openModal,
    closeModal: closeModal,
    closeAllModals: closeAllModals,
    toast: toast,
    badge: badge,
    appChip: appChip,
    actionLabel: actionLabel,
    actionClass: actionClass,
    entityLabel: entityLabel,
    formatDateTime: formatDateTime,
    errorMessage: errorMessage,
    setBusy: setBusy,
    debounce: debounce,
    downloadJSON: downloadJSON,
    copyText: copyText,
    jsonPretty: jsonPretty,
    maskSecret: maskSecret
  };
})();

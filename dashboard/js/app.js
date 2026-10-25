/* Aplicação do painel.
 *
 * Um único fluxo para todos os apps: a lista de apps e as regras de código
 * vêm de public.apps. McPlayer e NexPlay usam exatamente o mesmo componente;
 * a diferença é só o code_pattern/normalize_upper configurado no banco.
 */
(function () {
  'use strict';

  var V = window.Validation;
  var U = window.UI;
  var Api = window.Api;
  var cfg = window.DASHBOARD_CONFIG;

  if (!V || !U || !Api) return;

  var state = {
    user: null,
    adminReady: false,
    entering: false,
    tab: 'overview',
    apps: [],
    devices: [],
    playlists: [],
    clients: [],
    audit: [],
    admins: [],
    deleteTarget: null,
    editDevice: null,
    editPlaylist: null,
    editClient: null,
    editApp: null,
    filters: {
      devices: { q: '', app: 'all', status: 'all' },
      playlists: { q: '', app: 'all' },
      clients: { q: '', app: 'all' },
      audit: { q: '', app: 'all', action: 'all' }
    },
    unsubscribe: null,
    pollTimer: null,
    refreshing: false,
    refreshAgain: false,
    setupError: ''
  };

  var refreshDebounced = U.debounce(function () { refreshAll(true); }, 400);

  window.Dashboard = {
    onRealtimeStatus: function (status) {
      setRealtimeStatus(status === 'SUBSCRIBED' ? 'online' : 'offline', status);
    }
  };

  document.addEventListener('DOMContentLoaded', init);

  function init() {
    bindStaticEvents();
    Api.onAuthStateChange(function (event, session) {
      if (event === 'SIGNED_OUT' || !session) {
        if (state.adminReady || event === 'SIGNED_OUT') resetToLogin();
        return;
      }
      if (!state.adminReady && !state.entering) {
        enterApp(session);
      }
    });

    Api.getSession()
      .then(function (session) {
        if (session) return enterApp(session);
        showLogin();
      })
      .catch(function (err) {
        showLogin(U.errorMessage(err), false);
      });
  }

  /* ============================== AUTENTICAÇÃO ============================ */

  function showLogin(message, ok) {
    document.getElementById('appView').classList.add('hidden');
    document.getElementById('loginView').classList.remove('hidden');
    if (message) showLoginMsg(message, ok);
    else hideLoginMsg();
  }

  function showLoginMsg(message, ok) {
    var el = document.getElementById('loginMsg');
    el.textContent = message;
    el.className = 'auth-msg' + (ok ? ' ok' : '');
  }

  function hideLoginMsg() {
    document.getElementById('loginMsg').className = 'auth-msg hidden';
  }

  function setRealtimeStatus(cls, label) {
    var el = document.getElementById('rtStatus');
    var lb = document.getElementById('rtLabel');
    if (!el || !lb) return;
    el.className = 'rt ' + cls;
    if (cls === 'online') {
      lb.textContent = 'tempo real';
    } else {
      var map = {
        CHANNEL_ERROR: 'reconectando',
        TIMED_OUT: 'sem conexão',
        CLOSED: 'desconectado',
        SUBSCRIBED: 'tempo real'
      };
      lb.textContent = map[label] || 'reconectando';
    }
  }

  async function enterApp(session) {
    if (state.entering || state.adminReady) return;
    state.entering = true;
    try {
      state.user = session.user;

      var admin = await Api.isAdmin();
      if (!admin) admin = await Api.claimAdmin();
      if (!admin) {
        await Api.signOut();
        showLogin('Esta conta não tem permissão de administrador. Peça para um admin liberar seu e-mail.', false);
        return;
      }

      state.adminReady = true;
      document.getElementById('loginView').classList.add('hidden');
      document.getElementById('appView').classList.remove('hidden');
      var email = session.user.email || '';
      document.getElementById('userEmail').textContent = email;
      document.getElementById('sessionEmail').textContent = email;

      await refreshAll(true);
      subscribe();
      startPolling();
    } catch (err) {
      state.adminReady = false;
      showLogin(U.errorMessage(err), false);
    } finally {
      state.entering = false;
    }
  }

  async function logout() {
    stopPolling();
    if (state.unsubscribe) {
      state.unsubscribe();
      state.unsubscribe = null;
    }
    try {
      await Api.signOut();
    } catch (_err) {
      /* segue para a tela de login de qualquer forma */
    }
    resetToLogin();
  }

  function resetToLogin() {
    stopPolling();
    if (state.unsubscribe) {
      state.unsubscribe();
      state.unsubscribe = null;
    }
    state.adminReady = false;
    state.user = null;
    state.apps = [];
    state.devices = [];
    state.playlists = [];
    state.clients = [];
    state.audit = [];
    state.admins = [];
    document.getElementById('appView').classList.add('hidden');
    document.getElementById('loginView').classList.remove('hidden');
    document.getElementById('loginPassword').value = '';
  }

  /* ================================ DADOS ================================= */

  async function refreshAll(silent) {
    if (!state.adminReady) return;
    if (state.refreshing) {
      state.refreshAgain = true;
      return;
    }
    state.refreshing = true;

    try {
      var rows = await Promise.all([
        Api.loadApps(),
        Api.loadDevices(),
        Api.loadPlaylists(),
        Api.loadClients(),
        Api.loadAudit(cfg.auditPageSize || 500),
        Api.loadAdmins()
      ]);

      state.apps = rows[0] || [];
      state.devices = rows[1] || [];
      state.playlists = rows[2] || [];
      state.clients = rows[3] || [];
      state.audit = rows[4] || [];
      state.admins = rows[5] || [];
      state.setupError = '';
      hideSetupBanner();
      renderAll();
    } catch (err) {
      var msg = U.errorMessage(err);
      state.setupError = msg;
      if (/Estrutura do banco|does not exist|schema cache/i.test(msg)) {
        showSetupBanner(msg);
      }
      if (!silent) U.toast(msg, 'err', 9000);
    } finally {
      state.refreshing = false;
      if (state.refreshAgain) {
        state.refreshAgain = false;
        refreshAll(true);
      }
    }
  }

  function subscribe() {
    if (state.unsubscribe) state.unsubscribe();
    state.unsubscribe = Api.subscribe(refreshDebounced);
  }

  function startPolling() {
    stopPolling();
    state.pollTimer = setInterval(function () {
      if (state.adminReady && document.visibilityState === 'visible') refreshAll(true);
    }, cfg.pollIntervalMs || 20000);
  }

  function stopPolling() {
    if (state.pollTimer) {
      clearInterval(state.pollTimer);
      state.pollTimer = null;
    }
  }

  function showSetupBanner(detail) {
    var el = document.getElementById('setupBanner');
    document.getElementById('setupBannerDetail').textContent = detail || '';
    el.classList.remove('hidden');
  }

  function hideSetupBanner() {
    document.getElementById('setupBanner').classList.add('hidden');
  }

  /* ================================ RENDER ================================ */

  function renderAll() {
    renderCounts();
    renderFilterOptions();
    renderOverview();
    renderDevices();
    renderPlaylists();
    renderClients();
    renderAudit();
    renderSettings();
  }

  function renderCounts() {
    document.getElementById('countDevices').textContent = state.devices.length;
    document.getElementById('countPlaylists').textContent = state.playlists.length;
    document.getElementById('countClients').textContent = state.clients.length;
    document.getElementById('countAudit').textContent = state.audit.length;
  }

  function fillAppSelect(id, current, includeAll, includeInactive) {
    var sel = document.getElementById(id);
    if (!sel) return;
    var html = includeAll ? '<option value="all">Todos os apps</option>' : '';
    state.apps
      .filter(function (a) { return includeInactive || a.active; })
      .forEach(function (a) {
        html += '<option value="' + U.esc(a.name) + '">' + U.esc(a.name) + '</option>';
      });
    sel.innerHTML = html;

    var valid = Array.prototype.slice.call(sel.options).some(function (o) { return o.value === current; });
    if (valid) sel.value = current;
    else if (includeAll) sel.value = 'all';
    else if (sel.options.length) sel.value = sel.options[0].value;
  }

  function renderFilterOptions() {
    fillAppSelect('filterDeviceApp', state.filters.devices.app, true, true);
    fillAppSelect('filterPlaylistApp', state.filters.playlists.app, true, true);
    fillAppSelect('filterClientApp', state.filters.clients.app, true, true);
    fillAppSelect('filterAuditApp', state.filters.audit.app, true, true);
  }

  function appByName(name) {
    return state.apps.filter(function (a) { return a.name === name; })[0] || null;
  }

  function deviceById(id) {
    return state.devices.filter(function (d) { return d.id === id; })[0] || null;
  }

  function playlistById(id) {
    return state.playlists.filter(function (p) { return p.id === id; })[0] || null;
  }

  function linkedDevices(playlistId) {
    return state.devices.filter(function (d) { return d.playlist_id === playlistId; });
  }

  // Nomes de cliente ligados a um aparelho: o campo do aparelho + cadastros
  // em public.clients que apontam para o mesmo app/código.
  function clientNamesForDevice(d) {
    var names = [];
    if (d.client_name) names.push(d.client_name);
    state.clients.forEach(function (c) {
      if (c.app_name === d.app_name && c.device_id === d.device_id &&
          c.name && names.indexOf(c.name) === -1) {
        names.push(c.name);
      }
    });
    return names;
  }

  function listDataFromPlaylist(p) {
    if (String(p.type).toLowerCase() === 'xtream') {
      return {
        type: 'xtream',
        serverUrl: p.server_url || '',
        server_url: p.server_url || '',
        username: p.username || '',
        password: p.password || ''
      };
    }
    return { type: 'm3u', url: p.url || '' };
  }

  function expiryBadge(iso) {
    var days = V.daysUntil(iso);
    if (days === null) return '';
    if (days < 0) return '<span class="badge badge-blocked">vencido ' + Math.abs(days) + 'd</span>';
    if (days === 0) return '<span class="badge badge-pending">vence hoje</span>';
    if (days <= 3) return '<span class="badge badge-pending">vence em ' + days + 'd</span>';
    return '<span class="badge badge-approved">' + days + 'd</span>';
  }

  function listSummary(device) {
    var ld = device.list_data;
    var pl = device.playlist_id ? playlistById(device.playlist_id) : null;
    var plText = pl ? ' <span class="pill-soft">playlist: ' + U.esc(pl.name) + '</span>' : '';

    if (!ld) {
      return '<div class="list-summary"><span class="warn">Sem lista vinculada.</span>' + plText + '</div>';
    }
    if (String(ld.type).toLowerCase() === 'xtream') {
      return (
        '<div class="list-summary"><b>Xtream:</b> <span class="mono">' +
        U.esc(ld.serverUrl || ld.server_url || '—') +
        '</span> · usuário <b>' + U.esc(ld.username || '—') +
        '</b> · senha <b>••••••••</b>' + plText + '</div>'
      );
    }
    return (
      '<div class="list-summary"><b>M3U:</b> <span class="mono">' +
      U.esc(ld.url || '—') + '</span>' + plText + '</div>'
    );
  }

  function renderOverview() {
    var total = state.devices.length;
    var pending = state.devices.filter(function (d) { return d.status === 'pending'; }).length;
    var approved = state.devices.filter(function (d) { return d.status === 'approved'; }).length;
    var blocked = state.devices.filter(function (d) { return d.status === 'blocked'; }).length;
    var withMac = state.devices.filter(function (d) { return !!d.mac; }).length;
    var withoutMac = total - withMac;

    document.getElementById('overviewStats').innerHTML =
      statCard('Aparelhos', total, state.apps.length + ' app(s) monitorado(s)', '') +
      statCard('Pendentes', pending, 'aguardando aprovação', pending ? 'warn' : '') +
      statCard('Aprovados', approved, 'com acesso liberado', 'ok') +
      statCard('Bloqueados', blocked, 'acesso cancelado', blocked ? 'danger' : '');

    document.getElementById('overviewApps').innerHTML = state.apps
      .map(function (app) {
        var list = state.devices.filter(function (d) { return d.app_name === app.name; });
        var p = list.filter(function (d) { return d.status === 'pending'; }).length;
        var a = list.filter(function (d) { return d.status === 'approved'; }).length;
        var b = list.filter(function (d) { return d.status === 'blocked'; }).length;
        var m = list.filter(function (d) { return !!d.mac; }).length;
        return (
          '<div class="app-stat">' +
          '<div class="app-stat-head"><span class="name">' + U.esc(app.name) + '</span>' +
          (app.active ? U.badge('approved').replace('Aprovado', 'Ativo') : U.badge('blocked').replace('Bloqueado', 'Inativo')) +
          '</div>' +
          '<div class="app-stat-grid">' +
          '<div><b>' + list.length + '</b><span>total</span></div>' +
          '<div><b>' + p + '</b><span>pendentes</span></div>' +
          '<div><b>' + a + '</b><span>aprovados</span></div>' +
          '<div><b>' + b + '</b><span>bloqueados</span></div>' +
          '</div>' +
          '<div class="small muted" style="margin-top:8px;">' + m + ' com MAC · ' + (list.length - m) + ' sem MAC</div>' +
          '</div>'
        );
      })
      .join('') || emptyState('Nenhum app cadastrado', 'Rode o 001_schema.sql ou cadastre um app em Configuração.');

    var recent = state.devices.slice(0, 6);
    document.getElementById('overviewDevices').innerHTML = recent.length
      ? recent.map(miniDevice).join('')
      : emptyState('Nenhum aparelho', 'Clique em Aparelhos → Novo aparelho.');

    var audit = state.audit.slice(0, 5);
    document.getElementById('overviewAudit').innerHTML = audit.length
      ? audit.map(auditRow).join('')
      : emptyState('Sem ações registradas', 'As alterações aparecem aqui automaticamente.');

    // MACs sem vínculo (rodapé informativo)
    if (withoutMac > 0) {
      document.getElementById('overviewStats').title =
        withoutMac + ' aparelho(s) sem MAC vinculado. O código continua funcionando normalmente.';
    }
  }

  function statCard(label, value, foot, cls) {
    return (
      '<div class="stat ' + (cls || '') + '">' +
      '<div class="stat-label">' + U.esc(label) + '</div>' +
      '<div class="stat-value">' + U.esc(value) + '</div>' +
      '<div class="stat-foot">' + U.esc(foot) + '</div>' +
      '</div>'
    );
  }

  function miniDevice(d) {
    return (
      '<div class="row-card" style="padding:11px 12px;">' +
      '<div class="device-idline">' +
      '<span class="tag-mono">' + U.esc(d.device_id) + '</span>' +
      U.badge(d.status) + U.appChip(d.app_name) +
      (d.mac ? '<span class="device-mac">' + U.esc(d.mac) + '</span>' : '<span class="pill-soft">sem MAC</span>') +
      '</div>' +
      '<div class="small muted" style="margin-top:6px;">' +
      (d.client_name ? U.esc(d.client_name) + ' · ' : '') +
      'criado em ' + U.formatDateTime(d.created_at) +
      '</div></div>'
    );
  }

  /* ------------------------------- devices -------------------------------- */

  function filteredDevices() {
    var f = state.filters.devices;
    var q = f.q.trim();
    return state.devices.filter(function (d) {
      if (f.app !== 'all' && d.app_name !== f.app) return false;
      if (f.status !== 'all' && d.status !== f.status) return false;
      if (!q) return true;
      return (
        V.codeMatches(d.device_id, q) ||
        V.macMatches(d.mac, q) ||
        String(d.client_name || '').toLowerCase().indexOf(q.toLowerCase()) !== -1
      );
    });
  }

  function renderDevices() {
    var list = filteredDevices();
    var el = document.getElementById('devicesList');

    if (!list.length) {
      el.innerHTML = state.devices.length
        ? emptyState('Nenhum aparelho com esses filtros', 'Ajuste a busca, o app ou o status.')
        : emptyState('Nenhum aparelho cadastrado', 'Clique em "+ Novo aparelho" ou aguarde o check-in dos apps.');
      return;
    }

    el.innerHTML = list.map(deviceCard).join('');
  }

  function deviceCard(d) {
    var blocked = d.status === 'blocked';
    var toggledLabel = blocked ? '🔓 Liberar' : '⛔ Bloquear';
    var expiry = d.expires_at
      ? U.esc(V.formatDateBR(d.expires_at)) + ' ' + expiryBadge(d.expires_at)
      : '—';

    return (
      '<div class="device-card">' +
      '<div class="device-top">' +
      '<div>' +
      '<div class="device-idline">' +
      '<span class="device-code">' + U.esc(d.device_id) + '</span>' +
      U.badge(d.status) + U.appChip(d.app_name) +
      (d.mac
        ? '<span class="device-mac">MAC ' + U.esc(d.mac) + '</span>'
        : '<span class="pill-soft">MAC não vinculado</span>') +
      '</div>' +
      '<div class="device-meta">' +
      '<span>Cliente: <b>' + U.esc(d.client_name || '—') + '</b></span>' +
      '<span>Vencimento: <b>' + expiry + '</b></span>' +
      '<span>Criado: <b>' + U.formatDateTime(d.created_at) + '</b></span>' +
      (blocked && d.block_reason ? '<span>Motivo: <b>' + U.esc(d.block_reason) + '</b></span>' : '') +
      '</div>' +
      '</div>' +
      '<div class="device-actions">' +
      '<button type="button" class="btn-outline btn-sm" data-action="copy-code" data-id="' + U.esc(d.id) + '" title="Copiar o código para enviar ao cliente">📋 Código</button>' +
      (d.mac ? '<button type="button" class="btn-outline btn-sm" data-action="copy-mac" data-id="' + U.esc(d.id) + '" title="Copiar o MAC">📋 MAC</button>' : '') +
      '<button type="button" class="btn-outline btn-sm" data-action="edit" data-id="' + U.esc(d.id) + '">✏️ Editar</button>' +
      '<button type="button" class="btn-outline btn-sm" data-action="toggle" data-id="' + U.esc(d.id) + '">' + toggledLabel + '</button>' +
      '<button type="button" class="btn-danger btn-sm" data-action="delete" data-id="' + U.esc(d.id) + '">🗑️ Excluir</button>' +
      '</div>' +
      '</div>' +
      listSummary(d) +
      '</div>'
    );
  }

  /* ------------------------------ playlists ------------------------------- */

  function filteredPlaylists() {
    var f = state.filters.playlists;
    var q = f.q.trim().toLowerCase();
    return state.playlists.filter(function (p) {
      if (f.app !== 'all' && p.app_name !== f.app) return false;
      if (!q) return true;
      var linkedText = linkedDevices(p.id)
        .map(function (d) { return d.device_id + ' ' + (d.client_name || ''); })
        .join(' ')
        .toLowerCase();
      return (
        String(p.name || '').toLowerCase().indexOf(q) !== -1 ||
        String(p.server_url || '').toLowerCase().indexOf(q) !== -1 ||
        String(p.url || '').toLowerCase().indexOf(q) !== -1 ||
        String(p.username || '').toLowerCase().indexOf(q) !== -1 ||
        linkedText.indexOf(q) !== -1
      );
    });
  }

  function renderPlaylists() {
    var list = filteredPlaylists();
    var el = document.getElementById('playlistsList');
    if (!list.length) {
      el.innerHTML = state.playlists.length
        ? emptyState('Nenhuma lista com esses filtros', 'Ajuste a busca ou o app.')
        : emptyState('Nenhuma lista cadastrada', 'Cadastre uma playlist M3U/Xtream para reutilizar nos aparelhos.');
      return;
    }
    el.innerHTML = list.map(playlistCard).join('');
  }

  function playlistCard(p) {
    var devs = linkedDevices(p.id);
    var linked = devs.length;
    var endpoint =
      p.type === 'xtream'
        ? '<b>Servidor:</b> <span class="mono">' + U.esc(p.server_url || '—') + '</span> · <b>Usuário:</b> ' + U.esc(p.username || '—') + ' · <b>Senha:</b> ••••••••'
        : '<b>URL:</b> <span class="mono">' + U.esc(p.url || '—') + '</span>';

    var clientNames = [];
    devs.forEach(function (d) {
      clientNamesForDevice(d).forEach(function (n) {
        if (clientNames.indexOf(n) === -1) clientNames.push(n);
      });
    });

    var whereBits = devs.slice(0, 3).map(function (d) {
      return '<span class="pill-soft mono">' + U.esc(d.device_id) + '</span>';
    }).join(' ');
    if (devs.length > 3) {
      whereBits += ' <span class="pill-soft">+' + (devs.length - 3) + '</span>';
    }

    var whereLine = linked
      ? '<div class="small" style="margin-top:6px;">📍 <b>Onde:</b> ' + whereBits +
        ' · 👤 <b>Cliente:</b> ' + U.esc(clientNames.length ? clientNames.join(', ') : 'não informado') + '</div>'
      : '<div class="small muted" style="margin-top:6px;">📍 Ainda não vinculada a nenhum aparelho</div>';

    return (
      '<div class="row-card">' +
      '<div class="device-top">' +
      '<div>' +
      '<div class="device-idline">' +
      '<b style="font-size:15px;">' + U.esc(p.name) + '</b>' +
      U.appChip(p.app_name) +
      '<span class="pill-soft">' + U.esc(p.type.toUpperCase()) + '</span>' +
      '<span class="pill-soft">' + linked + ' aparelho(s)</span>' +
      '</div>' +
      '<div class="small secondary" style="margin-top:7px; overflow-wrap:anywhere;">' + endpoint + '</div>' +
      '<div class="small muted" style="margin-top:4px;">ID do app: <span class="mono">' + U.esc(p.app_name) + '</span></div>' +
      whereLine +
      (p.notes ? '<div class="small muted" style="margin-top:5px;">' + U.esc(p.notes) + '</div>' : '') +
      '</div>' +
      '<div class="device-actions">' +
      '<button type="button" class="btn-outline btn-sm" data-playlist-action="edit" data-id="' + U.esc(p.id) + '">✏️ Editar</button>' +
      '<button type="button" class="btn-danger btn-sm" data-playlist-action="delete" data-id="' + U.esc(p.id) + '">🗑️ Excluir</button>' +
      '</div>' +
      '</div></div>'
    );
  }

  /* ------------------------------- clients -------------------------------- */

  function filteredClients() {
    var f = state.filters.clients;
    var q = f.q.trim().toLowerCase();
    return state.clients.filter(function (c) {
      if (f.app !== 'all' && c.app_name !== f.app) return false;
      if (!q) return true;
      var dev = state.devices.filter(function (d) {
        return d.app_name === c.app_name && d.device_id === c.device_id;
      })[0];
      return (
        String(c.name || '').toLowerCase().indexOf(q) !== -1 ||
        String(c.phone || '').toLowerCase().indexOf(q) !== -1 ||
        V.codeMatches(c.device_id, q) ||
        (dev && V.macMatches(dev.mac, q))
      );
    });
  }

  function renderClients() {
    var list = filteredClients();
    var el = document.getElementById('clientsList');
    if (!list.length) {
      el.innerHTML = state.clients.length
        ? emptyState('Nenhum cliente com esses filtros', 'Ajuste a busca ou o app.')
        : emptyState('Nenhum cliente cadastrado', 'Cadastre o cliente e vincule ao aparelho/código.');
      return;
    }
    el.innerHTML = list.map(clientCard).join('');
  }

  function clientCard(c) {
    var dev = state.devices.filter(function (d) {
      return d.app_name === c.app_name && d.device_id === c.device_id;
    })[0];
    var expiry = c.expires_at ? V.formatDateBR(c.expires_at) : '—';
    var wa = V.whatsappPhone(c.phone);
    var waText = encodeURIComponent(
      'Olá ' + c.name + ', tudo bem? Passando para lembrar do seu acesso ' +
      (c.app_name || '') + ' com vencimento em ' + expiry + '. Qualquer dúvida estamos à disposição!'
    );

    return (
      '<div class="row-card">' +
      '<div class="device-top">' +
      '<div>' +
      '<div class="device-idline">' +
      '<b style="font-size:15px;">' + U.esc(c.name) + '</b>' +
      (c.app_name ? U.appChip(c.app_name) : '') +
      (c.expires_at ? expiryBadge(c.expires_at) : '<span class="badge badge-neutral">sem data</span>') +
      '</div>' +
      '<div class="device-meta">' +
      '<span>📱 <b>' + U.esc(c.phone) + '</b></span>' +
      '<span>Chave: <b>' + U.esc(c.device_id || 'não vinculada') + '</b></span>' +
      (dev && dev.mac ? '<span>MAC: <b class="mono">' + U.esc(dev.mac) + '</b></span>' : '') +
      '<span>Vencimento: <b>' + U.esc(expiry) + '</b></span>' +
      '</div>' +
      (c.notes ? '<div class="small muted" style="margin-top:5px;">' + U.esc(c.notes) + '</div>' : '') +
      '</div>' +
      '<div class="device-actions">' +
      (wa ? '<a class="btn-wa btn-sm" href="https://wa.me/' + U.esc(wa) + '?text=' + waText + '" target="_blank" rel="noopener">💬 WhatsApp</a>' : '') +
      '<button type="button" class="btn-outline btn-sm" data-client-action="add30" data-id="' + U.esc(c.id) + '">+30 dias</button>' +
      '<button type="button" class="btn-outline btn-sm" data-client-action="edit" data-id="' + U.esc(c.id) + '">✏️ Editar</button>' +
      '<button type="button" class="btn-danger btn-sm" data-client-action="delete" data-id="' + U.esc(c.id) + '">🗑️ Excluir</button>' +
      '</div>' +
      '</div></div>'
    );
  }

  /* -------------------------------- audit --------------------------------- */

  function filteredAudit() {
    var f = state.filters.audit;
    var q = f.q.trim().toLowerCase();
    return state.audit.filter(function (a) {
      if (f.app !== 'all' && a.app_name !== f.app) return false;
      if (f.action !== 'all' && a.action !== f.action) return false;
      if (!q) return true;
      return (
        V.codeMatches(a.device_id, q) ||
        V.macMatches(a.mac, q) ||
        String(a.actor_email || '').toLowerCase().indexOf(q) !== -1
      );
    });
  }

  function renderAudit() {
    var list = filteredAudit();
    var el = document.getElementById('auditList');
    if (!list.length) {
      el.innerHTML = emptyState(
        state.audit.length ? 'Nenhuma ação com esses filtros' : 'Sem ações registradas',
        'Cada inserção, edição, exclusão, bloqueio e vínculo de MAC aparece aqui.'
      );
      return;
    }
    var html =
      '<div class="small muted" style="margin-bottom:8px;">Mostrando ' + list.length +
      ' de ' + state.audit.length + ' registro(s) (limite de ' +
      (cfg.auditPageSize || 500) + ' por consulta).</div>' +
      list.map(auditRow).join('');
    el.innerHTML = html;
  }

  function auditRow(a) {
    var name = '';
    if (a.entity !== 'device' && (a.after || a.before)) {
      var obj = a.after || a.before || {};
      name = obj.name || '';
    }
    var detailBits = [];
    if (a.entity === 'device') {
      if (a.device_id) detailBits.push('código <b class="mono">' + U.esc(a.device_id) + '</b>');
      if (a.mac) detailBits.push('MAC <b class="mono">' + U.esc(a.mac) + '</b>');
    } else if (name) {
      detailBits.push('<b>' + U.esc(name) + '</b>');
    }
    if (a.app_name) detailBits.push(U.esc(a.app_name));

    var diff =
      '<details class="diff"><summary>Ver antes/depois</summary>' +
      '<pre class="json">' +
      U.esc('ANTES:\n' + U.jsonPretty(a.before) + '\n\nDEPOIS:\n' + U.jsonPretty(a.after)) +
      '</pre></details>';

    return (
      '<div class="audit-row">' +
      '<div class="audit-head">' +
      '<span class="badge badge-neutral">' + U.esc(U.entityLabel(a.entity)) + '</span>' +
      '<span class="' + U.actionClass(a.action) + '"><b>' + U.esc(U.actionLabel(a.action)) + '</b></span>' +
      (a.app_name ? U.appChip(a.app_name) : '') +
      '<span class="audit-when">' + U.formatDateTime(a.created_at) + '</span>' +
      '</div>' +
      '<div class="audit-detail">' +
      '<span>por <b>' + U.esc(a.actor_email || 'sistema') + '</b></span>' +
      (a.source === 'activation' ? '<span class="pill-soft">check-in do app</span>' : '') +
      (detailBits.length ? '<span>' + detailBits.join(' · ') + '</span>' : '') +
      '</div>' +
      diff +
      '</div>'
    );
  }

  /* ------------------------------- settings ------------------------------- */

  function renderSettings() {
    var tbody = document.getElementById('appsTableBody');
    tbody.innerHTML = state.apps
      .map(function (a) {
        return (
          '<tr>' +
          '<td><b>' + U.esc(a.name) + '</b></td>' +
          '<td class="mono">' + U.esc(a.code_pattern) + '</td>' +
          '<td>' + U.esc(a.code_hint || '—') + '</td>' +
          '<td>' + (a.normalize_upper ? 'Sim' : 'Não') + '</td>' +
          '<td>' + (a.active ? 'Sim' : 'Não') + '</td>' +
          '<td><button type="button" class="btn-outline btn-xs" data-app-edit="' + U.esc(a.name) + '">Editar</button> ' +
          '<button type="button" class="btn-danger btn-xs" data-app-delete="' + U.esc(a.name) + '">Excluir</button></td>' +
          '</tr>'
        );
      })
      .join('') || '<tr><td colspan="6" class="muted">Nenhum app cadastrado.</td></tr>';

    document.getElementById('adminsList').innerHTML = state.admins.length
      ? state.admins
          .map(function (a) {
            return (
              '<div class="row-card" style="padding:10px 12px;">' +
              '<div class="device-idline"><b>' + U.esc(a.email) + '</b>' +
              (a.active ? U.badge('approved').replace('Aprovado', 'Ativo') : U.badge('blocked').replace('Bloqueado', 'Inativo')) +
              '</div>' +
              '<div class="small muted" style="margin-top:4px;">desde ' + U.formatDateTime(a.created_at) + '</div>' +
              '</div>'
            );
          })
          .join('')
      : '<div class="muted small">Nenhum admin visível. Rode o 003_admin.sql.</div>';

    document.getElementById('backupInfo').innerHTML =
      state.devices.length + ' aparelho(s), ' + state.playlists.length + ' lista(s), ' +
      state.clients.length + ' cliente(s), ' + state.audit.length + ' evento(s) de auditoria.';

    document.getElementById('configInfo').innerHTML =
      '<dt>Supabase URL</dt><dd class="mono">' + U.esc(cfg.supabaseUrl) + '</dd>' +
      '<dt>Chave usada</dt><dd class="mono">' + U.esc(U.maskSecret(cfg.supabaseAnonKey)) + ' (anon key pública)</dd>' +
      '<dt>Conta</dt><dd>' + U.esc(state.user && state.user.email) + '</dd>' +
      '<dt>Permissão</dt><dd>Administrador (validado por RLS no banco)</dd>' +
      '<dt>Tempo real</dt><dd>Supabase Realtime + atualização automática a cada ' +
      Math.round((cfg.pollIntervalMs || 20000) / 1000) + 's</dd>';
  }

  function emptyState(title, sub) {
    return '<div class="empty-state"><b>' + U.esc(title) + '</b>' + U.esc(sub) + '</div>';
  }

  /* =============================== MODAIS ================================= */

  function fillDeviceAppSelect(currentName) {
    var sel = document.getElementById('devApp');
    var html = '';
    state.apps.forEach(function (a) {
      html += '<option value="' + U.esc(a.name) + '">' + U.esc(a.name) +
        (a.active ? '' : ' (inativo)') + '</option>';
    });
    sel.innerHTML = html;
    if (currentName) sel.value = currentName;
  }

  function fillPlaylistSelect(appName, currentId) {
    var sel = document.getElementById('devPlaylist');
    var html = '<option value="">— Nenhuma —</option>';
    state.playlists
      .filter(function (p) { return !appName || p.app_name === appName; })
      .forEach(function (p) {
        html += '<option value="' + U.esc(p.id) + '">' + U.esc(p.name) + ' (' + U.esc(p.type) + ')</option>';
      });
    sel.innerHTML = html;
    if (currentId) sel.value = currentId;
  }

  function updateDeviceAppHints() {
    var app = appByName(document.getElementById('devApp').value);
    var hint = document.getElementById('devCodeHint');
    var code = document.getElementById('devCode');
    if (!app) {
      hint.textContent = '';
      return;
    }
    hint.className = app.active ? '' : 'field-warn';
    hint.textContent = app.code_hint + ' — regex: ' + app.code_pattern +
      (app.active ? '' : ' — app inativo: o check-in dos apps está bloqueado, mas o admin ainda pode editar.');
    var len = V.codeLength(app);
    code.maxLength = len;
    var charset = V.codeCharset(app);
    code.placeholder = charset.indexOf('0') !== -1 && charset.length === 10
      ? new Array(len + 1).join('0')
      : new Array(len + 1).join('A');
    if (app.normalize_upper) code.style.textTransform = 'uppercase';
    else code.style.textTransform = 'none';
  }

  function updateDeviceListBoxes() {
    var type = document.getElementById('devListType').value;
    document.getElementById('devM3uBox').style.display = type === 'm3u' ? '' : 'none';
    document.getElementById('devXtreamBox').style.display = type === 'xtream' ? '' : 'none';
    var summary = document.getElementById('devListSummary');
    if (!type) summary.textContent = 'sem lista';
    else if (type === 'm3u') summary.textContent = 'M3U';
    else summary.textContent = 'Xtream';
  }

  function resetDeviceForm() {
    document.getElementById('devId').value = '';
    document.getElementById('devStatus').value = 'pending';
    document.getElementById('devCode').value = '';
    document.getElementById('devMac').value = '';
    document.getElementById('devClientName').value = '';
    document.getElementById('devExpires').value = '';
    document.getElementById('devBlockReason').value = '';
    document.getElementById('devNotes').value = '';
    document.getElementById('devListType').value = '';
    document.getElementById('devM3uUrl').value = '';
    document.getElementById('devServer').value = '';
    document.getElementById('devUser').value = '';
    document.getElementById('devPass').value = '';
    document.getElementById('btnDeleteDeviceFromModal').style.display = 'none';
    var codeHint = document.getElementById('devCodeHint');
    codeHint.className = '';
    codeHint.textContent = '';
    var macHint = document.getElementById('devMacHint');
    macHint.className = '';
    macHint.textContent = 'Aceita com hífen, sem separador ou minúsculo. Normaliza para AA:BB:CC:DD:EE:FF.';
    updateDeviceListBoxes();
  }

  function openDeviceModal(device) {
    state.editDevice = device || null;
    resetDeviceForm();

    var firstApp = state.apps.filter(function (a) { return a.active; })[0] || state.apps[0];
    var appName = device ? device.app_name : firstApp ? firstApp.name : '';
    fillDeviceAppSelect(appName);
    updateDeviceAppHints();

    if (device) {
      document.getElementById('deviceModalTitle').textContent = 'Editar aparelho ' + device.device_id;
      document.getElementById('devId').value = device.id;
      document.getElementById('devStatus').value = device.status;
      document.getElementById('devCode').value = device.device_id;
      document.getElementById('devMac').value = device.mac || '';
      document.getElementById('devClientName').value = device.client_name || '';
      document.getElementById('devExpires').value = device.expires_at ? String(device.expires_at).slice(0, 10) : '';
      document.getElementById('devBlockReason').value = device.block_reason || '';
      document.getElementById('devNotes').value = device.notes || '';
      document.getElementById('btnDeleteDeviceFromModal').style.display = '';

      var ld = device.list_data || {};
      var type = String(ld.type || '').toLowerCase();
      document.getElementById('devListType').value = type === 'xtream' || type === 'm3u' ? type : '';
      if (type === 'xtream') {
        document.getElementById('devServer').value = ld.serverUrl || ld.server_url || '';
        document.getElementById('devUser').value = ld.username || '';
        document.getElementById('devPass').value = ld.password || '';
      } else if (type === 'm3u') {
        document.getElementById('devM3uUrl').value = ld.url || '';
      }
    } else {
      document.getElementById('deviceModalTitle').textContent = 'Novo aparelho';
    }

    fillPlaylistSelect(document.getElementById('devApp').value, device ? device.playlist_id : '');
    updateDeviceListBoxes();
    U.openModal('modalDevice');
  }

  async function saveDevice() {
    var app = appByName(document.getElementById('devApp').value);
    var code = document.getElementById('devCode').value;
    var macInput = document.getElementById('devMac').value;
    var status = document.getElementById('devStatus').value;
    var codeCheck = V.validateCode(app, code);
    var macCheck = V.normalizeMac(macInput);

    var hint = document.getElementById('devCodeHint');
    hint.className = '';
    if (!codeCheck.ok) {
      hint.textContent = codeCheck.message;
      hint.className = 'field-error';
      document.getElementById('devCode').focus();
      return;
    }
    if (!macCheck.ok) {
      document.getElementById('devMacHint').textContent = macCheck.message;
      document.getElementById('devMacHint').className = 'field-error';
      document.getElementById('devMac').focus();
      return;
    }
    document.getElementById('devMacHint').className = '';
    document.getElementById('devMacHint').textContent =
      'Aceita com hífen, sem separador ou minúsculo. Normaliza para AA:BB:CC:DD:EE:FF.';

    var listType = document.getElementById('devListType').value;
    var listData = null;
    if (listType === 'm3u') {
      var url = document.getElementById('devM3uUrl').value.trim();
      if (!url) return U.toast('Informe a URL da lista M3U.', 'err');
      listData = { type: 'm3u', url: url };
    } else if (listType === 'xtream') {
      var server = document.getElementById('devServer').value.trim();
      var user = document.getElementById('devUser').value.trim();
      var pass = document.getElementById('devPass').value;
      if (!server || !user || !pass) return U.toast('Preencha servidor, usuário e senha do Xtream.', 'err');
      listData = {
        type: 'xtream',
        serverUrl: server,
        server_url: server,
        username: user,
        password: pass
      };
    }

    if (status === 'approved' && !listData) {
      if (!confirm('Aprovar este aparelho SEM lista vinculada?\n\nO app vai ficar aprovado, mas sem conteúdo até você enviar uma lista.')) return;
    }

    var payload = {
      id: state.editDevice ? state.editDevice.id : null,
      app_name: app.name,
      device_id: codeCheck.value,
      mac: macCheck.value,
      status: status,
      list_data: listData,
      playlist_id: document.getElementById('devPlaylist').value || null,
      client_name: document.getElementById('devClientName').value.trim(),
      expires_at: document.getElementById('devExpires').value || null,
      notes: document.getElementById('devNotes').value.trim(),
      block_reason: status === 'blocked'
        ? document.getElementById('devBlockReason').value.trim()
        : null
    };

    var btn = document.getElementById('btnSaveDevice');
    U.setBusy(btn, true, 'Salvando...');
    try {
      await Api.saveDevice(payload);
      U.closeModal('modalDevice');
      U.toast('Aparelho ' + payload.device_id + ' salvo. O app recebe em até 10s.', 'ok');
      await refreshAll(true);
    } catch (err) {
      U.toast(U.errorMessage(err), 'err', 9000);
    } finally {
      U.setBusy(btn, false);
    }
  }

  function openDeleteDeviceModal(device) {
    if (!device) return;
    state.deleteTarget = device;
    document.getElementById('delDeviceName').textContent = device.device_id + ' (' + device.app_name + ')';
    document.getElementById('delDeviceCode').value = '';
    document.getElementById('btnConfirmDeleteDevice').disabled = true;
    document.getElementById('delDeviceError').className = 'auth-msg hidden';
    U.openModal('modalDeleteDevice');
  }

  async function confirmDeleteDevice() {
    var d = state.deleteTarget;
    if (!d) return;
    var typed = document.getElementById('delDeviceCode').value.trim().toUpperCase();
    if (typed !== String(d.device_id).toUpperCase()) return;

    var btn = document.getElementById('btnConfirmDeleteDevice');
    U.setBusy(btn, true, 'Excluindo...');
    try {
      await Api.deleteDevice(d.id, typed);
      U.closeModal('modalDeleteDevice');
      U.closeModal('modalDevice');
      state.deleteTarget = null;
      U.toast('Aparelho ' + d.device_id + ' excluído. O histórico ficou na auditoria.', 'ok');
      await refreshAll(true);
    } catch (err) {
      var el = document.getElementById('delDeviceError');
      el.textContent = U.errorMessage(err);
      el.className = 'auth-msg';
    } finally {
      U.setBusy(btn, false);
    }
  }

  function openPlaylistModal(playlist) {
    state.editPlaylist = playlist || null;
    document.getElementById('playlistModalTitle').textContent = playlist ? 'Editar lista' : 'Nova lista';
    document.getElementById('plId').value = playlist ? playlist.id : '';
    fillAppSelectForModal('plApp', playlist ? playlist.app_name : (state.apps[0] && state.apps[0].name));
    document.getElementById('plName').value = playlist ? playlist.name : '';
    document.getElementById('plType').value = playlist ? playlist.type : 'm3u';
    document.getElementById('plUrl').value = playlist && playlist.type === 'm3u' ? playlist.url || '' : '';
    document.getElementById('plServer').value = playlist && playlist.type === 'xtream' ? playlist.server_url || '' : '';
    document.getElementById('plUser').value = playlist && playlist.type === 'xtream' ? playlist.username || '' : '';
    document.getElementById('plPass').value = playlist && playlist.type === 'xtream' ? playlist.password || '' : '';
    document.getElementById('plNotes').value = playlist ? playlist.notes || '' : '';
    fillPlaylistDeviceSelect(
      playlist ? playlist.app_name : (state.apps[0] && state.apps[0].name),
      playlist
    );
    updatePlaylistBoxes();
    updatePlAppIdLine();
    U.openModal('modalPlaylist');
  }

  function fillPlaylistDeviceSelect(appName, playlist) {
    var sel = document.getElementById('plDevice');
    var devs = state.devices.filter(function (d) { return d.app_name === appName; });
    var linked = playlist ? linkedDevices(playlist.id) : [];
    var current = linked.length === 1 ? linked[0].id : '';
    var hint = document.getElementById('plDeviceHint');

    sel.innerHTML = '<option value="">— não vincular agora —</option>' +
      devs.map(function (d) {
        return '<option value="' + U.esc(d.id) + '">' + U.esc(d.device_id) +
          ' — ' + U.esc(d.client_name || 'sem cliente') +
          ' (' + U.esc(d.status) + ')</option>';
      }).join('');
    sel.value = current;

    hint.textContent = linked.length > 1
      ? 'Esta lista já está em ' + linked.length +
        ' aparelhos. Escolher um aqui atualiza só esse aparelho.'
      : 'Opcional. Ao salvar, a lista é enviada para este aparelho.';

    applyPlaylistDeviceSelection();
  }

  function applyPlaylistDeviceSelection() {
    var sel = document.getElementById('plDevice');
    var input = document.getElementById('plClient');
    var dev = sel.value ? deviceById(sel.value) : null;

    input.disabled = !dev;
    if (!dev) {
      input.value = '';
      input.placeholder = 'Selecione o aparelho para preencher';
      return;
    }
    var names = clientNamesForDevice(dev);
    input.placeholder = 'Ex.: João';
    input.value = names.length ? names[0] : '';
  }

  function updatePlAppIdLine() {
    var app = document.getElementById('plApp').value || '—';
    var dev = deviceById(document.getElementById('plDevice').value);
    document.getElementById('plAppIdLine').textContent =
      'ID do app: ' + app + (dev ? ' · Aparelho: ' + dev.device_id : '');
  }

  function fillAppSelectForModal(id, current) {
    var sel = document.getElementById(id);
    sel.innerHTML = state.apps
      .map(function (a) {
        return '<option value="' + U.esc(a.name) + '">' + U.esc(a.name) + '</option>';
      })
      .join('');
    if (current) sel.value = current;
  }

  function updatePlaylistBoxes() {
    var type = document.getElementById('plType').value;
    document.getElementById('plM3uBox').style.display = type === 'm3u' ? '' : 'none';
    document.getElementById('plXtreamBox').style.display = type === 'xtream' ? '' : 'none';
  }

  async function savePlaylist() {
    var app = document.getElementById('plApp').value;
    var name = document.getElementById('plName').value.trim();
    var type = document.getElementById('plType').value;
    var url = document.getElementById('plUrl').value.trim();
    var server = document.getElementById('plServer').value.trim();
    var user = document.getElementById('plUser').value.trim();
    var pass = document.getElementById('plPass').value;

    if (!app) return U.toast('Escolha o app da lista.', 'err');
    if (!name) return U.toast('Informe o nome da lista.', 'err');
    if (type === 'm3u' && !url) return U.toast('Informe a URL M3U.', 'err');
    if (type === 'xtream' && (!server || !user || !pass)) {
      return U.toast('Preencha servidor, usuário e senha do Xtream.', 'err');
    }
    if (state.editPlaylist && state.editPlaylist.app_name !== app) {
      var linked = linkedDevices(state.editPlaylist.id);
      if (linked.length) {
        return U.toast(
          'Esta lista está vinculada a ' + linked.length +
          ' aparelho(s). Troque o app desses aparelhos antes de mover a lista.',
          'err',
          9000
        );
      }
    }

    var payload = {
      id: state.editPlaylist ? state.editPlaylist.id : null,
      app_name: app,
      name: name,
      type: type,
      url: type === 'm3u' ? url : null,
      server_url: type === 'xtream' ? server : null,
      username: type === 'xtream' ? user : null,
      password: type === 'xtream' ? pass : null,
      notes: document.getElementById('plNotes').value.trim()
    };

    var btn = document.getElementById('btnSavePlaylist');
    U.setBusy(btn, true, 'Salvando...');
    try {
      var saved = await Api.savePlaylist(payload);
      var targetId = document.getElementById('plDevice').value;
      if (targetId) {
        var dev = deviceById(targetId);
        if (dev) {
          await Api.saveDevice({
            id: dev.id,
            app_name: dev.app_name,
            device_id: dev.device_id,
            mac: dev.mac,
            status: dev.status,
            list_data: listDataFromPlaylist(saved),
            playlist_id: saved.id,
            client_name: document.getElementById('plClient').value.trim() || dev.client_name || '',
            expires_at: dev.expires_at,
            notes: dev.notes,
            block_reason: dev.block_reason
          });
        }
      }
      U.closeModal('modalPlaylist');
      U.toast(targetId ? 'Lista salva e enviada para o aparelho.' : 'Lista salva.', 'ok');
      await refreshAll(true);
    } catch (err) {
      U.toast(U.errorMessage(err), 'err', 9000);
    } finally {
      U.setBusy(btn, false);
    }
  }

  async function deletePlaylist(playlist) {
    var linked = linkedDevices(playlist.id).length;
    var msg =
      'Excluir a lista "' + playlist.name + '"?' +
      (linked
        ? '\n\n' + linked + ' aparelho(s) continuam com a lista copiada, mas perdem o vínculo com esta playlist.'
        : '');
    if (!confirm(msg)) return;
    try {
      await Api.deletePlaylist(playlist.id);
      U.toast('Lista excluída.', 'ok');
      await refreshAll(true);
    } catch (err) {
      U.toast(U.errorMessage(err), 'err');
    }
  }

  function fillClientAppSelect(current) {
    var sel = document.getElementById('clApp');
    var html = '<option value="">— Nenhum —</option>';
    state.apps.forEach(function (a) {
      html += '<option value="' + U.esc(a.name) + '">' + U.esc(a.name) + '</option>';
    });
    sel.innerHTML = html;
    if (current) sel.value = current;
  }

  function fillClientDeviceSelect(appName, currentCode) {
    var sel = document.getElementById('clDevice');
    var html = '<option value="">— Nenhum —</option>';
    state.devices
      .filter(function (d) { return !appName || d.app_name === appName; })
      .sort(function (a, b) { return String(a.device_id).localeCompare(String(b.device_id)); })
      .forEach(function (d) {
        html +=
          '<option value="' + U.esc(d.device_id) + '">' +
          U.esc(d.device_id) + ' — ' + U.esc(d.status) +
          (d.mac ? ' — ' + U.esc(d.mac) : '') +
          (d.client_name ? ' — ' + U.esc(d.client_name) : '') +
          '</option>';
      });
    sel.innerHTML = html;
    if (currentCode) sel.value = currentCode;
  }

  function openClientModal(client) {
    state.editClient = client || null;
    document.getElementById('clientModalTitle').textContent = client ? 'Editar cliente' : 'Novo cliente';
    document.getElementById('clId').value = client ? client.id : '';
    fillClientAppSelect(client ? client.app_name : (state.apps[0] && state.apps[0].name));
    fillClientDeviceSelect(document.getElementById('clApp').value, client ? client.device_id : '');
    document.getElementById('clName').value = client ? client.name : '';
    document.getElementById('clPhone').value = client ? client.phone : '';
    document.getElementById('clExpires').value =
      client && client.expires_at ? String(client.expires_at).slice(0, 10) : V.addDays(V.todayISO(), 30);
    document.getElementById('clNotes').value = client ? client.notes || '' : '';
    U.openModal('modalClient');
  }

  async function saveClient() {
    var name = document.getElementById('clName').value.trim();
    var phone = document.getElementById('clPhone').value.trim();
    var appName = document.getElementById('clApp').value || null;
    var deviceId = document.getElementById('clDevice').value || null;

    if (!name) return U.toast('Informe o nome do cliente.', 'err');
    if (!phone) return U.toast('Informe o WhatsApp / telefone.', 'err');
    if (deviceId && !appName) {
      return U.toast('Escolha o app antes de vincular um aparelho ao cliente.', 'err');
    }

    var payload = {
      id: state.editClient ? state.editClient.id : null,
      name: name,
      phone: phone,
      app_name: appName,
      device_id: deviceId,
      expires_at: document.getElementById('clExpires').value || null,
      notes: document.getElementById('clNotes').value.trim()
    };

    var btn = document.getElementById('btnSaveClient');
    U.setBusy(btn, true, 'Salvando...');
    try {
      await Api.saveClient(payload);
      U.closeModal('modalClient');
      U.toast('Cliente salvo.', 'ok');
      await refreshAll(true);
    } catch (err) {
      U.toast(U.errorMessage(err), 'err', 9000);
    } finally {
      U.setBusy(btn, false);
    }
  }

  async function deleteClient(client) {
    if (!confirm('Excluir o cadastro do cliente "' + client.name + '"?')) return;
    try {
      await Api.deleteClient(client.id);
      U.toast('Cliente excluído.', 'ok');
      await refreshAll(true);
    } catch (err) {
      U.toast(U.errorMessage(err), 'err');
    }
  }

  async function addClientDays(client, days) {
    try {
      var updated = Object.assign({}, client, {
        expires_at: V.addDays(client.expires_at || V.todayISO(), days)
      });
      await Api.saveClient(updated);
      U.toast(
        '+' + days + ' dias para ' + client.name + '. Novo vencimento: ' + V.formatDateBR(updated.expires_at),
        'ok'
      );
      await refreshAll(true);
    } catch (err) {
      U.toast(U.errorMessage(err), 'err');
    }
  }

  function openAppModal(app) {
    state.editApp = app || null;
    document.getElementById('appModalTitle').textContent = app ? 'Editar app' : 'Novo app';
    document.getElementById('appOriginalName').value = app ? app.name : '';
    document.getElementById('appName').value = app ? app.name : '';
    document.getElementById('appPattern').value = app ? app.code_pattern : '';
    document.getElementById('appHint').value = app ? app.code_hint || '' : '';
    document.getElementById('appUpper').checked = app ? !!app.normalize_upper : true;
    document.getElementById('appActive').checked = app ? !!app.active : true;
    document.getElementById('appOrder').value = app ? app.sort_order : 100;
    U.openModal('modalApp');
  }

  async function saveApp() {
    var name = document.getElementById('appName').value.trim();
    var pattern = document.getElementById('appPattern').value.trim();
    var original = document.getElementById('appOriginalName').value || null;

    if (!name) return U.toast('Informe o nome do app.', 'err');
    if (!pattern) return U.toast('Informe a regex do código.', 'err');
    try {
      new RegExp(pattern);
    } catch (_err) {
      return U.toast('Regex inválida. Exemplo: ^[0-9]{6}$', 'err');
    }

    var re = new RegExp(pattern);
    var upper = document.getElementById('appUpper').checked;
    var invalid = state.devices.filter(function (d) {
      if (d.app_name !== (original || name)) return false;
      var code = upper ? String(d.device_id).toUpperCase() : String(d.device_id);
      return !re.test(code);
    });
    if (invalid.length) {
      var ok = confirm(
        invalid.length + ' aparelho(s) existente(s) não batem com a nova regex:\n' +
        invalid.slice(0, 8).map(function (d) { return d.device_id; }).join(', ') +
        (invalid.length > 8 ? '…' : '') +
        '\n\nEles continuam no banco, mas só poderão ser editados para um código válido. Continuar?'
      );
      if (!ok) return;
    }

    var payload = {
      name: name,
      code_pattern: pattern,
      code_hint: document.getElementById('appHint').value.trim(),
      normalize_upper: upper,
      active: document.getElementById('appActive').checked,
      sort_order: Number(document.getElementById('appOrder').value || 100)
    };

    var btn = document.getElementById('btnSaveApp');
    U.setBusy(btn, true, 'Salvando...');
    try {
      await Api.saveApp(payload, original);
      U.closeModal('modalApp');
      U.toast('App salvo.', 'ok');
      await refreshAll(true);
    } catch (err) {
      U.toast(U.errorMessage(err), 'err', 9000);
    } finally {
      U.setBusy(btn, false);
    }
  }

  async function deleteApp(app) {
    var linkedDevicesCount = state.devices.filter(function (d) { return d.app_name === app.name; }).length;
    var linkedPlaylistsCount = state.playlists.filter(function (p) { return p.app_name === app.name; }).length;
    var linkedClientsCount = state.clients.filter(function (c) { return c.app_name === app.name; }).length;

    if (linkedDevicesCount || linkedPlaylistsCount || linkedClientsCount) {
      U.toast(
        'Não é possível excluir "' + app.name + '": ' +
        linkedDevicesCount + ' aparelho(s), ' + linkedPlaylistsCount + ' lista(s) e ' +
        linkedClientsCount + ' cliente(s) ainda usam este app. Exclua ou mova esses registros primeiro.',
        'err',
        9000
      );
      return;
    }

    if (!confirm('Excluir o app "' + app.name + '"?\n\nA regra de código e a dica serão removidas. Esta ação não pode ser desfeita.')) {
      return;
    }

    try {
      await Api.deleteApp(app.name);
      U.toast('App "' + app.name + '" excluído.', 'ok');
      await refreshAll(true);
    } catch (err) {
      U.toast(U.errorMessage(err), 'err', 9000);
    }
  }

  /* ================================ EVENTOS =============================== */

  function bindStaticEvents() {
    // Login
    document.getElementById('loginForm').addEventListener('submit', onLogin);
    document.getElementById('signupForm').addEventListener('submit', onSignup);
    document.getElementById('btnShowSignup').addEventListener('click', function () {
      document.getElementById('loginTitle').textContent = 'Criar conta de administrador';
      document.getElementById('signupBox').classList.remove('hidden');
      this.classList.add('hidden');
      document.getElementById('btnBackLogin').classList.remove('hidden');
      hideLoginMsg();
    });
    document.getElementById('btnBackLogin').addEventListener('click', function () {
      document.getElementById('loginTitle').textContent = 'Entrar como administrador';
      document.getElementById('signupBox').classList.add('hidden');
      this.classList.add('hidden');
      document.getElementById('btnShowSignup').classList.remove('hidden');
      hideLoginMsg();
    });

    document.getElementById('btnLogout').addEventListener('click', logout);
    document.getElementById('btnLogout2').addEventListener('click', logout);

    // Olho para mostrar/ocultar senhas
    U.qsa('.pw-toggle').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var input = document.getElementById(btn.dataset.pw);
        if (!input) return;
        var show = input.type === 'password';
        input.type = show ? 'text' : 'password';
        btn.classList.toggle('is-on', show);
        btn.setAttribute('aria-pressed', show ? 'true' : 'false');
        btn.setAttribute('aria-label', show ? 'Ocultar senha' : 'Mostrar senha');
        btn.title = show ? 'Ocultar senha' : 'Mostrar senha';
        btn.textContent = show ? '🙈' : '👁';
      });
    });

    // Navegação
    U.qsa('.nav-btn').forEach(function (btn) {
      btn.addEventListener('click', function () { switchTab(btn.dataset.tab); });
    });
    U.qsa('[data-goto]').forEach(function (btn) {
      btn.addEventListener('click', function () { switchTab(btn.dataset.goto); });
    });

    // Filtros
    var devQ = document.getElementById('searchDevices');
    devQ.addEventListener('input', function () {
      state.filters.devices.q = devQ.value;
      renderDevices();
    });
    document.getElementById('filterDeviceApp').addEventListener('change', function () {
      state.filters.devices.app = this.value;
      renderDevices();
    });
    document.getElementById('filterDeviceStatus').addEventListener('change', function () {
      state.filters.devices.status = this.value;
      renderDevices();
    });

    var plQ = document.getElementById('searchPlaylists');
    plQ.addEventListener('input', function () {
      state.filters.playlists.q = plQ.value;
      renderPlaylists();
    });
    document.getElementById('filterPlaylistApp').addEventListener('change', function () {
      state.filters.playlists.app = this.value;
      renderPlaylists();
    });

    var clQ = document.getElementById('searchClients');
    clQ.addEventListener('input', function () {
      state.filters.clients.q = clQ.value;
      renderClients();
    });
    document.getElementById('filterClientApp').addEventListener('change', function () {
      state.filters.clients.app = this.value;
      renderClients();
    });

    var auQ = document.getElementById('searchAudit');
    auQ.addEventListener('input', function () {
      state.filters.audit.q = auQ.value;
      renderAudit();
    });
    document.getElementById('filterAuditApp').addEventListener('change', function () {
      state.filters.audit.app = this.value;
      renderAudit();
    });
    document.getElementById('filterAuditAction').addEventListener('change', function () {
      state.filters.audit.action = this.value;
      renderAudit();
    });
    document.getElementById('btnReloadAudit').addEventListener('click', function () {
      refreshAll(false);
    });

    // Botões de criação
    document.getElementById('btnNewDevice').addEventListener('click', function () { openDeviceModal(null); });
    document.getElementById('btnNewPlaylist').addEventListener('click', function () { openPlaylistModal(null); });
    document.getElementById('btnNewClient').addEventListener('click', function () { openClientModal(null); });
    document.getElementById('btnNewApp').addEventListener('click', function () { openAppModal(null); });
    document.getElementById('btnExport').addEventListener('click', exportBackup);

    // Ações em listas dinâmicas
    document.getElementById('devicesList').addEventListener('click', onDeviceAction);
    document.getElementById('playlistsList').addEventListener('click', onPlaylistAction);
    document.getElementById('clientsList').addEventListener('click', onClientAction);
    document.getElementById('appsTableBody').addEventListener('click', function (e) {
      var editBtn = e.target.closest('button[data-app-edit]');
      if (editBtn) {
        var app = appByName(editBtn.dataset.appEdit);
        if (app) openAppModal(app);
        return;
      }
      var delBtn = e.target.closest('button[data-app-delete]');
      if (delBtn) {
        var target = appByName(delBtn.dataset.appDelete);
        if (target) deleteApp(target);
      }
    });

    // Modal aparelho
    document.getElementById('devApp').addEventListener('change', function () {
      updateDeviceAppHints();
      fillPlaylistSelect(this.value, '');
    });
    document.getElementById('devCode').addEventListener('input', function () {
      var app = appByName(document.getElementById('devApp').value);
      if (app && app.normalize_upper) this.value = this.value.toUpperCase();
      var check = V.validateCode(app, this.value);
      var hint = document.getElementById('devCodeHint');
      hint.className = check.ok || !this.value ? '' : 'field-error';
      hint.textContent = check.ok ? (app ? app.code_hint + ' — regex: ' + app.code_pattern : '') : check.message;
    });
    document.getElementById('btnGenCode').addEventListener('click', function () {
      var app = appByName(document.getElementById('devApp').value);
      var code = V.generateCode(app);
      if (!code) return U.toast('Não foi possível gerar um código para esta regex.', 'err');
      document.getElementById('devCode').value = code;
      document.getElementById('devCode').dispatchEvent(new Event('input'));
    });
    document.getElementById('devMac').addEventListener('input', function () {
      this.value = V.formatMacInput(this.value);
    });
    document.getElementById('btnUnlinkMac').addEventListener('click', function () {
      document.getElementById('devMac').value = '';
      document.getElementById('devMacHint').className = '';
      document.getElementById('devMacHint').textContent =
        'MAC desvinculado. Clique em Salvar para aplicar. O histórico do aparelho é preservado.';
    });
    document.getElementById('devListType').addEventListener('change', updateDeviceListBoxes);
    document.getElementById('devPlaylist').addEventListener('change', function () {
      var pl = playlistById(this.value);
      if (!pl) return;
      document.getElementById('devListType').value = pl.type;
      if (pl.type === 'm3u') document.getElementById('devM3uUrl').value = pl.url || '';
      else {
        document.getElementById('devServer').value = pl.server_url || '';
        document.getElementById('devUser').value = pl.username || '';
        document.getElementById('devPass').value = pl.password || '';
      }
      updateDeviceListBoxes();
      U.toast('Campos preenchidos com a playlist "' + pl.name + '".', 'ok');
    });
    document.getElementById('devStatus').addEventListener('change', function () {
      if (this.value !== 'blocked') document.getElementById('devBlockReason').value = '';
    });
    document.getElementById('btnSaveDevice').addEventListener('click', saveDevice);
    document.getElementById('btnDeleteDeviceFromModal').addEventListener('click', function () {
      if (state.editDevice) {
        U.closeModal('modalDevice');
        openDeleteDeviceModal(state.editDevice);
      }
    });

    // Modal excluir aparelho
    document.getElementById('delDeviceCode').addEventListener('input', function () {
      var d = state.deleteTarget;
      var ok = d && this.value.trim().toUpperCase() === String(d.device_id).toUpperCase();
      document.getElementById('btnConfirmDeleteDevice').disabled = !ok;
      document.getElementById('delDeviceError').className = 'auth-msg hidden';
    });
    document.getElementById('btnConfirmDeleteDevice').addEventListener('click', confirmDeleteDevice);

    // Modal playlist
    document.getElementById('plType').addEventListener('change', updatePlaylistBoxes);
    document.getElementById('plApp').addEventListener('change', function () {
      fillPlaylistDeviceSelect(this.value, null);
      updatePlAppIdLine();
    });
    document.getElementById('plDevice').addEventListener('change', function () {
      applyPlaylistDeviceSelection();
      updatePlAppIdLine();
    });
    document.getElementById('btnSavePlaylist').addEventListener('click', savePlaylist);

    // Modal cliente
    document.getElementById('clApp').addEventListener('change', function () {
      fillClientDeviceSelect(this.value, '');
    });
    document.getElementById('btnSaveClient').addEventListener('click', saveClient);
    U.qsa('[data-add-days]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var input = document.getElementById('clExpires');
        input.value = V.addDays(input.value || V.todayISO(), Number(btn.dataset.addDays));
      });
    });

    // Modal app
    document.getElementById('btnSaveApp').addEventListener('click', saveApp);

    // Fechamentos
    document.addEventListener('click', function (e) {
      var closer = e.target.closest('[data-close]');
      if (closer) {
        U.closeModal(closer.dataset.close);
        return;
      }
      if (e.target.classList.contains('modal-overlay')) U.closeModal(e.target.id);
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') U.closeAllModals();
    });
  }

  function switchTab(tab) {
    state.tab = tab;
    U.qsa('.nav-btn').forEach(function (b) {
      b.classList.toggle('active', b.dataset.tab === tab);
    });
    U.qsa('.tab-panel').forEach(function (p) {
      p.classList.toggle('active', p.id === 'tab-' + tab);
    });
    if (tab === 'audit') renderAudit();
  }

  async function onLogin(e) {
    e.preventDefault();
    hideLoginMsg();
    var btn = document.getElementById('loginBtn');
    U.setBusy(btn, true, 'Entrando...');
    try {
      var response = await Api.signIn(
        document.getElementById('loginEmail').value.trim(),
        document.getElementById('loginPassword').value
      );
      if (response.session) await enterApp(response.session);
    } catch (err) {
      var msg = U.errorMessage(err);
      if (/Invalid login credentials/i.test(msg)) msg = 'E-mail ou senha inválidos.';
      if (/Email not confirmed/i.test(msg)) msg = 'Confirme seu e-mail antes de entrar.';
      showLoginMsg(msg, false);
    } finally {
      U.setBusy(btn, false);
    }
  }

  async function onSignup(e) {
    e.preventDefault();
    var box = document.getElementById('signupMsg');
    box.className = 'auth-msg hidden';
    var btn = document.getElementById('signupBtn');
    U.setBusy(btn, true, 'Criando...');
    try {
      var response = await Api.signUp(
        document.getElementById('signupEmail').value.trim(),
        document.getElementById('signupPassword').value
      );
      if (response.session) {
        await enterApp(response.session);
      } else {
        box.textContent =
          'Conta criada. Confirme o e-mail (link enviado pelo Supabase) e depois entre. ' +
          'Se o painel ainda não tiver admin, a primeira conta confirmada vira admin.';
        box.className = 'auth-msg ok';
      }
    } catch (err) {
      box.textContent = U.errorMessage(err);
      box.className = 'auth-msg';
    } finally {
      U.setBusy(btn, false);
    }
  }

  function onDeviceAction(e) {
    var btn = e.target.closest('button[data-action]');
    if (!btn) return;
    var d = deviceById(btn.dataset.id);
    if (!d) return;
    var action = btn.dataset.action;

    if (action === 'copy-code') {
      U.copyText(d.device_id).then(function () {
        U.toast('Código ' + d.device_id + ' copiado.', 'ok');
      });
      return;
    }
    if (action === 'copy-mac') {
      if (!d.mac) return;
      U.copyText(d.mac).then(function () {
        U.toast('MAC ' + d.mac + ' copiado.', 'ok');
      });
      return;
    }
    if (action === 'edit') return openDeviceModal(d);
    if (action === 'delete') return openDeleteDeviceModal(d);
    if (action === 'toggle') return toggleBlock(d, btn);
  }

  async function toggleBlock(device, btn) {
    if (device.status === 'blocked') {
      if (!confirm('Liberar o aparelho ' + device.device_id + '?\n\nSe ele tiver lista, volta como aprovado; se não tiver, volta como pendente.')) return;
      var next = device.list_data ? 'approved' : 'pending';
      U.setBusy(btn, true, '...');
      try {
        await Api.setDeviceStatus(device.id, next, null);
        U.toast('Aparelho ' + device.device_id + ' liberado.', 'ok');
        await refreshAll(true);
      } catch (err) {
        U.toast(U.errorMessage(err), 'err');
      } finally {
        U.setBusy(btn, false);
      }
      return;
    }

    var reason = prompt('Motivo do bloqueio de ' + device.device_id + ' (opcional):', device.block_reason || '');
    if (reason === null) return;
    U.setBusy(btn, true, '...');
    try {
      await Api.setDeviceStatus(device.id, 'blocked', reason.trim());
      U.toast('Aparelho ' + device.device_id + ' bloqueado.', 'ok');
      await refreshAll(true);
    } catch (err) {
      U.toast(U.errorMessage(err), 'err');
    } finally {
      U.setBusy(btn, false);
    }
  }

  function onPlaylistAction(e) {
    var btn = e.target.closest('button[data-playlist-action]');
    if (!btn) return;
    var p = playlistById(btn.dataset.id);
    if (!p) return;
    if (btn.dataset.playlistAction === 'edit') openPlaylistModal(p);
    else deletePlaylist(p);
  }

  function onClientAction(e) {
    var btn = e.target.closest('button[data-client-action]');
    if (!btn) return;
    var c = state.clients.filter(function (x) { return x.id === btn.dataset.id; })[0];
    if (!c) return;
    if (btn.dataset.clientAction === 'edit') openClientModal(c);
    else if (btn.dataset.clientAction === 'delete') deleteClient(c);
    else if (btn.dataset.clientAction === 'add30') addClientDays(c, 30);
  }

  async function exportBackup() {
    var btn = document.getElementById('btnExport');
    U.setBusy(btn, true, 'Gerando...');
    try {
      var data = await Api.exportAll();
      var stamp = new Date().toISOString().slice(0, 16).replace(/[:T]/g, '-');
      U.downloadJSON('mcplayer-backup-' + stamp + '.json', data);
      U.toast('Backup gerado com sucesso.', 'ok');
    } catch (err) {
      U.toast(U.errorMessage(err), 'err');
    } finally {
      U.setBusy(btn, false);
    }
  }
})();

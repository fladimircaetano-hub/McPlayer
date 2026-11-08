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
    recoveryMode: false,
    tab: 'overview',
    apps: [],
    devices: [],
    playlists: [],
    clients: [],
    audit: [],
    admins: [],
    xtreamServers: [],
    xtreamClients: [],
    xtreamMissing: false,
    deleteTarget: null,
    editDevice: null,
    editPlaylist: null,
    editClient: null,
    editApp: null,
    access: { mac: '', code: '', app: 'all', deviceId: null, matches: [], statusFilter: '' },
    filters: {
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

    // Link de recuperação: o Supabase cria a sessão e avisa em PASSWORD_RECOVERY.
    if (/type=recovery/.test(window.location.hash)) state.recoveryMode = true;

    Api.onAuthStateChange(function (event, session) {
      if (event === 'PASSWORD_RECOVERY') {
        state.recoveryMode = true;
        showNewPasswordModal();
        return;
      }
      if (event === 'SIGNED_OUT' || !session) {
        if (state.adminReady || event === 'SIGNED_OUT') resetToLogin();
        return;
      }
      if (!state.adminReady && !state.entering && !state.recoveryMode) {
        enterApp(session);
      }
    });

    Api.getSession()
      .then(function (session) {
        if (state.recoveryMode) {
          showNewPasswordModal();
          return;
        }
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
    if (state.entering || state.adminReady || state.recoveryMode) return;
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
        Api.loadAdmins(),
        Api.loadXtreamServers().catch(function () { return null; }),
        Api.loadXtreamClients().catch(function () { return null; })
      ]);

      state.apps = rows[0] || [];
      state.devices = rows[1] || [];
      state.playlists = rows[2] || [];
      state.clients = rows[3] || [];
      state.audit = rows[4] || [];
      state.admins = rows[5] || [];
      state.xtreamServers = rows[6];
      state.xtreamClients = rows[7];
      state.xtreamMissing = rows[6] === null || rows[7] === null;
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
    renderPlaylists();
    renderClients();
    renderXtream();
    renderAccess();
    renderAudit();
    renderSettings();
  }

  function renderCounts() {
    var playlists = document.getElementById('countPlaylists');
    var clients = document.getElementById('countClients');
    if (playlists) playlists.textContent = state.playlists.length;
    if (clients) clients.textContent = state.clients.length;
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
    fillAppSelect('filterPlaylistApp', state.filters.playlists.app, true, true);
    fillAppSelect('filterClientApp', state.filters.clients.app, true, true);
    fillAppSelect('filterAuditApp', state.filters.audit.app, true, true);
    fillAppSelect('accessApp', state.access.app, true, true);
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

  // Listas do aparelho. Formato atual: list_data com { lists: [...] } quando há
  // mais de uma; uma lista só continua salva no formato antigo { type, url }.
  function deviceLists(device) {
    if (!device || !device.list_data) return [];
    var ld = device.list_data;
    if (Array.isArray(ld.lists)) return ld.lists.slice();
    if (ld.type) return [ld];
    return [];
  }

  function listRowHtml(data) {
    var isXtream = data && String(data.type || '').toLowerCase() === 'xtream';
    var url = data ? data.url || '' : '';
    var server = data ? data.serverUrl || data.server_url || '' : '';
    var user = data ? data.username || '' : '';
    var pass = data ? data.password || '' : '';
    return (
      '<div class="list-entry" data-list-row>' +
      '<div class="list-entry-head">' +
      '<div><h4>Lista <span data-list-index>1</span></h4></div>' +
      '<button type="button" class="btn-danger btn-sm" data-remove-list>🗑️ Excluir</button>' +
      '</div>' +
      '<div class="form-grid">' +
      '<div class="field"><label>Tipo</label>' +
      '<select data-list-type>' +
      '<option value="m3u"' + (isXtream ? '' : ' selected') + '>M3U (URL)</option>' +
      '<option value="xtream"' + (isXtream ? ' selected' : '') + '>Xtream Codes</option>' +
      '</select></div>' +
      '</div>' +
      '<div class="field" data-list-m3u>' +
      '<label>URL da lista M3U</label>' +
      '<input data-list-url placeholder="https://servidor/lista.m3u" autocomplete="off" value="' + U.esc(url) + '">' +
      '</div>' +
      '<div class="form-grid-3" data-list-xtream>' +
      '<div class="field"><label>Servidor</label>' +
      '<input data-list-server placeholder="http://servidor:8080" autocomplete="off" value="' + U.esc(server) + '"></div>' +
      '<div class="field"><label>Usuário</label>' +
      '<input data-list-user placeholder="usuario" autocomplete="off" value="' + U.esc(user) + '"></div>' +
      '<div class="field"><label>Senha</label>' +
      '<input data-list-pass type="password" placeholder="senha" autocomplete="new-password" value="' + U.esc(pass) + '"></div>' +
      '</div>' +
      '</div>'
    );
  }

  function updateListRow(row) {
    var type = row.querySelector('[data-list-type]').value;
    row.querySelector('[data-list-m3u]').style.display = type === 'm3u' ? '' : 'none';
    row.querySelector('[data-list-xtream]').style.display = type === 'xtream' ? '' : 'none';
  }

  function renumberListRows() {
    var rows = document.querySelectorAll('#devLists [data-list-row]');
    Array.prototype.forEach.call(rows, function (row, i) {
      var label = row.querySelector('[data-list-index]');
      if (label) label.textContent = i + 1;
    });
    var empty = document.getElementById('devListsEmpty');
    if (empty) empty.style.display = rows.length ? 'none' : '';
  }

  function addDeviceListRow(data) {
    var wrap = document.getElementById('devLists');
    if (!wrap) return null;
    var holder = document.createElement('div');
    holder.innerHTML = listRowHtml(data);
    var row = holder.firstChild;
    wrap.appendChild(row);
    row.querySelector('[data-list-type]').addEventListener('change', function () {
      updateListRow(row);
    });
    row.querySelector('[data-remove-list]').addEventListener('click', function () {
      row.remove();
      renumberListRows();
    });
    updateListRow(row);
    renumberListRows();
    return row;
  }

  function renderDeviceLists(device) {
    var wrap = document.getElementById('devLists');
    if (!wrap) return;
    wrap.innerHTML = '';
    var lists = deviceLists(device);
    if (!lists.length && device && device.playlist_id) {
      var pl = playlistById(device.playlist_id);
      if (pl) lists = [listDataFromPlaylist(pl)];
    }
    lists.forEach(function (l) { addDeviceListRow(l); });
    renumberListRows();
  }

  function collectDeviceLists() {
    var rows = document.querySelectorAll('#devLists [data-list-row]');
    var lists = [];
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      var type = row.querySelector('[data-list-type]').value;
      var n = i + 1;
      if (type === 'xtream') {
        var server = row.querySelector('[data-list-server]').value.trim();
        var user = row.querySelector('[data-list-user]').value.trim();
        var pass = row.querySelector('[data-list-pass]').value;
        if (!server && !user && !pass) continue;
        if (!server || !user || !pass) {
          return { error: 'Complete servidor, usuário e senha da lista ' + n + '.' };
        }
        lists.push({ type: 'xtream', serverUrl: server, server_url: server, username: user, password: pass });
      } else {
        var url = row.querySelector('[data-list-url]').value.trim();
        if (!url) return { error: 'Informe a URL da lista ' + n + ' (ou exclua a lista).' };
        lists.push({ type: 'm3u', url: url });
      }
    }
    return { lists: lists };
  }

  function packListData(lists) {
    if (!lists.length) return null;
    if (lists.length === 1) return lists[0];
    return Object.assign({}, lists[0], { lists: lists });
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
    var lists = deviceLists(device);
    var ld = lists[0] || null;
    var pl = device.playlist_id ? playlistById(device.playlist_id) : null;
    var plText = pl ? ' <span class="pill-soft">playlist: ' + U.esc(pl.name) + '</span>' : '';
    var extraText = lists.length > 1
      ? ' <span class="pill-soft">' + lists.length + ' listas</span>'
      : '';

    if (!ld) {
      return '<div class="list-summary"><span class="warn">Sem lista vinculada.</span>' + plText + '</div>';
    }
    if (String(ld.type).toLowerCase() === 'xtream') {
      return (
        '<div class="list-summary"><b>Xtream:</b> <span class="mono">' +
        U.esc(ld.serverUrl || ld.server_url || '—') +
        '</span> · usuário <b>' + U.esc(ld.username || '—') +
        '</b> · senha <b>••••••••</b>' + extraText + plText + '</div>'
      );
    }
    return (
      '<div class="list-summary"><b>M3U:</b> <span class="mono">' +
      U.esc(ld.url || '—') + '</span>' + extraText + plText + '</div>'
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
      statCard('Aparelhos', total, state.apps.length + ' app(s) monitorado(s)', '', 'all') +
      statCard('Pendentes', pending, 'aguardando aprovação', pending ? 'warn' : '', 'pending') +
      statCard('Aprovados', approved, 'com acesso liberado', 'ok', 'approved') +
      statCard('Bloqueados', blocked, 'acesso cancelado', blocked ? 'danger' : '', 'blocked');

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
      : emptyState('Nenhum aparelho', 'Digite o MAC + código em Acesso / Auditoria para abrir ou cadastrar.');

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

  function statCard(label, value, foot, cls, status) {
    return (
      '<button type="button" class="stat ' + (cls || '') + '" data-stat-status="' + U.esc(status) + '">' +
      '<span class="stat-label">' + U.esc(label) + '</span>' +
      '<span class="stat-value">' + U.esc(value) + '</span>' +
      '<span class="stat-foot">' + U.esc(foot) + '</span>' +
      '</button>'
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
    var entry = dev && dev.start_date ? V.formatDateBR(dev.start_date) : '—';
    var playlist = dev && dev.playlist_id ? playlistById(dev.playlist_id) : null;
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
      (dev && (dev.device_type || dev.device_brand) ? '<span>Aparelho: <b>' + U.esc(deviceLabel(dev)) + '</b></span>' : '') +
      '<span>Entrada: <b>' + U.esc(entry) + '</b></span>' +
      '<span>Vencimento: <b>' + U.esc(expiry) + '</b></span>' +
      (playlist ? '<span>Lista: <b>' + U.esc(playlist.name) + '</b></span>' : '') +
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

  /* --------------------------- acesso MAC + código ----------------------- */

  function accessMsg(message, ok) {
    var el = document.getElementById('accessMsg');
    if (!el) return;
    if (!message) {
      el.className = 'auth-msg hidden';
      el.textContent = '';
      return;
    }
    el.textContent = message;
    el.className = 'auth-msg' + (ok ? ' ok' : '');
  }

  function clearAccess(keepQuery) {
    state.access.deviceId = null;
    state.access.matches = [];
    if (!keepQuery) {
      state.access.mac = '';
      state.access.code = '';
      state.access.app = 'all';
      state.access.statusFilter = '';
      var mac = document.getElementById('accessMac');
      var code = document.getElementById('accessCode');
      var app = document.getElementById('accessApp');
      if (mac) mac.value = '';
      if (code) code.value = '';
      if (app) app.value = 'all';
    }
    accessMsg('');
    renderAccess();
  }

  function onAccessSubmit(e) {
    e.preventDefault();
    var macCheck = V.normalizeMac(document.getElementById('accessMac').value);
    var codeRaw = document.getElementById('accessCode').value.trim();
    var appName = document.getElementById('accessApp').value || 'all';

    if (!macCheck.ok) {
      accessMsg(macCheck.message);
      document.getElementById('accessMac').focus();
      return;
    }
    if (!macCheck.value) {
      accessMsg('Informe o MAC do aparelho.');
      document.getElementById('accessMac').focus();
      return;
    }
    if (!codeRaw) {
      accessMsg('Informe o código do app (ID do aparelho).');
      document.getElementById('accessCode').focus();
      return;
    }

    var code = codeRaw.toUpperCase();
    var matches = state.devices.filter(function (d) {
      if (appName !== 'all' && d.app_name !== appName) return false;
      if (!d.mac || d.mac !== macCheck.value) return false;
      return String(d.device_id).toUpperCase() === code;
    });

    state.access.mac = macCheck.value;
    state.access.code = code;
    state.access.app = appName;
    state.access.statusFilter = '';
    state.access.matches = matches.map(function (d) { return d.id; });
    state.access.deviceId = matches.length === 1 ? matches[0].id : null;

    if (!matches.length) {
      accessMsg(
        'Nenhum aparelho com este MAC + código' +
        (appName === 'all' ? '.' : ' no app ' + appName + '.') +
        ' Confira os dados ou cadastre o aparelho abaixo.'
      );
      renderAccess();
      return;
    }

    if (matches.length > 1) {
      accessMsg('Encontrei ' + matches.length + ' aparelhos com esses dados. Escolha abaixo.', true);
      renderAccess();
      return;
    }

    accessMsg('');
    renderAccess();
    openDeviceModal(matches[0]);
  }

  function onAccessAction(e) {
    var pick = e.target.closest('button[data-access-pick]');
    if (pick) {
      var picked = deviceById(pick.dataset.accessPick);
      state.access.deviceId = pick.dataset.accessPick;
      accessMsg('');
      renderAccess();
      if (picked) openDeviceModal(picked);
      return;
    }

    var btn = e.target.closest('button[data-access-action]');
    if (!btn) return;
    var action = btn.dataset.accessAction;
    if (action === 'close') return clearAccess(false);
    if (action === 'close-list') {
      state.access.statusFilter = '';
      return renderAccess();
    }

    if (action === 'create') {
      var chosenApp;
      if (state.access.app !== 'all') {
        chosenApp = state.access.app;
      } else {
        var active = state.apps.filter(function (a) { return a.active; });
        var byCode = active.filter(function (a) {
          return V.validateCode(a, state.access.code).ok;
        })[0];
        chosenApp = (byCode || active[0] || state.apps[0] || {}).name;
      }
      // O app pode já ter registrado este código (check-in) com outro MAC,
      // ou o código existir em outro app. Nesse caso abre o cadastro
      // existente em vez de tentar inserir de novo.
      var codeUpper = String(state.access.code).toUpperCase();
      var candidates = state.devices.filter(function (d) {
        return String(d.device_id).toUpperCase() === codeUpper;
      });
      var sameCode =
        candidates.filter(function (d) { return state.access.mac && d.mac === state.access.mac; })[0] ||
        candidates.filter(function (d) { return d.app_name === chosenApp; })[0] ||
        candidates[0];
      if (sameCode) {
        state.access.deviceId = sameCode.id;
        state.access.matches = [sameCode.id];
        accessMsg(
          'Já existe um aparelho ' + sameCode.device_id + ' em ' + sameCode.app_name +
          '. Abri o cadastro dele para você conferir o MAC e atualizar.',
          true
        );
        renderAccess();
        openDeviceModal(sameCode);
        return;
      }
      return openDeviceModal(null, {
        mac: state.access.mac,
        code: state.access.code,
        app_name: chosenApp
      });
    }

    var d = state.access.deviceId ? deviceById(state.access.deviceId) : null;
    if (!d) {
      state.access.matches = [];
      state.access.deviceId = null;
      accessMsg('Este aparelho não está mais na lista. Digite o MAC + código de novo.');
      renderAccess();
      return;
    }

    if (action === 'edit') return openDeviceModal(d);
    if (action === 'list') {
      openDeviceModal(d);
      setTimeout(function () {
        var addBtn = document.getElementById('btnAddDevList');
        if (addBtn) {
          addBtn.focus();
          addBtn.scrollIntoView({ block: 'center', behavior: 'smooth' });
        }
      }, 120);
      return;
    }
    if (action === 'toggle') return toggleBlock(d, btn);
    if (action === 'delete') return openDeleteDeviceModal(d);
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
    }
  }

  function openStatusList(status) {
    state.access.statusFilter = status;
    state.access.mac = '';
    state.access.code = '';
    state.access.matches = [];
    state.access.deviceId = null;
    document.getElementById('accessMac').value = '';
    document.getElementById('accessCode').value = '';
    accessMsg('');
    switchTab('audit');
    renderAccess();
  }

  function renderStatusList(el) {
    var status = state.access.statusFilter;
    var list = state.devices.filter(function (d) {
      return status === 'all' || d.status === status;
    });
    var titles = {
      all: 'Todos os aparelhos',
      pending: 'Aparelhos pendentes',
      approved: 'Aparelhos aprovados',
      blocked: 'Aparelhos bloqueados'
    };

    el.innerHTML =
      '<div class="card access-device">' +
      '<div class="card-head">' +
      '<div><h2>' + U.esc(titles[status] || 'Aparelhos') + ' (' + list.length + ')</h2>' +
      '<p>Clique em <b>Abrir formulário</b> para ver e editar todas as informações.</p></div>' +
      '<button type="button" class="btn-outline btn-sm" data-access-action="close-list">Fechar lista</button>' +
      '</div>' +
      (list.length
        ? '<div class="card-list">' + list.map(statusRow).join('') + '</div>'
        : emptyState('Nenhum aparelho', 'Nada encontrado para este status.')) +
      '</div>';
  }

  function statusRow(d) {
    var meta = [];
    if (d.client_name) meta.push(U.esc(d.client_name));
    if (d.device_type || d.device_brand) meta.push(U.esc(deviceLabel(d)));
    if (d.expires_at) meta.push('vence ' + U.esc(V.formatDateBR(d.expires_at)));
    return (
      '<div class="row-card" style="padding:11px 12px;">' +
      '<div class="device-idline">' +
      '<span class="tag-mono">' + U.esc(d.device_id) + '</span>' +
      U.badge(d.status) + U.appChip(d.app_name) +
      (d.mac ? '<span class="device-mac">' + U.esc(d.mac) + '</span>' : '<span class="pill-soft">sem MAC</span>') +
      '</div>' +
      (meta.length ? '<div class="small muted" style="margin-top:6px;">' + meta.join(' · ') + '</div>' : '') +
      '<div class="device-actions" style="margin-top:8px;">' +
      '<button type="button" class="btn-primary btn-sm" data-access-pick="' + U.esc(d.id) + '">Abrir formulário</button>' +
      '</div></div>'
    );
  }

  /* ----------------------------- contas Xtream ---------------------------- */

  function xtreamStatusBadge(status) {
    var s = String(status || '').toLowerCase();
    if (s === 'active') return '<span class="badge badge-approved">Ativo</span>';
    if (s === 'expired') return '<span class="badge badge-blocked">Vencido</span>';
    if (s === 'disabled' || s === 'banned') {
      return '<span class="badge badge-blocked">Bloqueado</span>';
    }
    return '<span class="badge badge-neutral">' + U.esc(s || '—') + '</span>';
  }

  function formatDateOnly(value) {
    if (!value) return '—';
    var d = new Date(value);
    if (isNaN(d.getTime())) return U.esc(value);
    return d.toLocaleDateString('pt-BR');
  }

  function renderXtream() {
    var missing = state.xtreamMissing;
    var clients = state.xtreamClients || [];
    var servers = state.xtreamServers || [];

    document.getElementById('countXtream').textContent = missing ? '—' : clients.length;

    document.getElementById('xtreamClientsBody').innerHTML = missing
      ? '<tr><td colspan="6" class="muted">Rode o dashboard/sql/006_xtream_accounts.sql no Supabase para ativar.</td></tr>'
      : clients.length
        ? clients.map(function (c) {
            var device = [c.mac, c.device_id].filter(Boolean).join(' · ');
            return '<tr>' +
              '<td><b>' + U.esc(c.username) + '</b></td>' +
              '<td class="mono small">' + U.esc(c.server_url) + '</td>' +
              '<td class="small">' + U.esc(device || '—') + '</td>' +
              '<td>' + xtreamStatusBadge(c.status) + '</td>' +
              '<td>' + formatDateOnly(c.exp_date) + '</td>' +
              '<td>' + U.formatDateTime(c.last_seen_at) + '</td>' +
              '</tr>';
          }).join('')
        : '<tr><td colspan="6" class="muted">Nenhuma conta entrou ainda.</td></tr>';

    document.getElementById('serversTableBody').innerHTML = missing
      ? '<tr><td colspan="4" class="muted">Rode o dashboard/sql/006_xtream_accounts.sql no Supabase para ativar.</td></tr>'
      : servers.length
        ? servers.map(function (s) {
            return '<tr>' +
              '<td><b>' + U.esc(s.name) + '</b></td>' +
              '<td class="mono small">' + U.esc(s.url) + '</td>' +
              '<td>' + (s.active ? 'Sim' : 'Não') + '</td>' +
              '<td><button type="button" class="btn-outline btn-xs" data-server-toggle="' + U.esc(s.id) + '">' +
                (s.active ? 'Desativar' : 'Ativar') + '</button> ' +
              '<button type="button" class="btn-danger btn-xs" data-server-delete="' + U.esc(s.id) + '">Excluir</button></td>' +
              '</tr>';
          }).join('')
        : '<tr><td colspan="4" class="muted">Nenhum servidor cadastrado.</td></tr>';
  }

  function renderAccess() {
    var el = document.getElementById('accessResult');
    if (!el) return;

    if (state.access.statusFilter) {
      renderStatusList(el);
      return;
    }

    var matches = state.access.matches.map(deviceById).filter(Boolean);

    if (!matches.length) {
      if (!state.access.mac || !state.access.code) {
        el.innerHTML = '';
        return;
      }
      el.innerHTML =
        '<div class="card access-device">' +
        '<div class="card-head">' +
        '<div><h2>Aparelho não encontrado</h2>' +
        '<p>MAC <b class="mono">' + U.esc(state.access.mac) + '</b> · código <b class="mono">' +
        U.esc(state.access.code) + '</b>' +
        (state.access.app !== 'all' ? ' · ' + U.esc(state.access.app) : '') + '</p></div>' +
        '</div>' +
        '<p class="small secondary">Se este é um aparelho novo, cadastre abaixo com os dados já preenchidos. ' +
        'Se ele já usa o app, confira o MAC e o código.</p>' +
        '<div class="access-actions">' +
        '<button type="button" class="btn-primary btn-sm" data-access-action="create">➕ Cadastrar este aparelho</button>' +
        '</div></div>';
      return;
    }

    var device = state.access.deviceId ? deviceById(state.access.deviceId) : null;

    if (!device && matches.length > 1) {
      el.innerHTML =
        '<div class="card access-device">' +
        '<div class="card-head"><div><h2>Escolha o aparelho</h2>' +
        '<p>O mesmo MAC + código existe em mais de um app.</p></div></div>' +
        '<div class="card-list">' +
        matches.map(function (d) {
          return (
            '<div class="row-card" style="padding:11px 12px;">' +
            '<div class="device-idline">' +
            '<span class="device-code">' + U.esc(d.device_id) + '</span>' +
            U.badge(d.status) + U.appChip(d.app_name) +
            '<span class="device-mac">' + U.esc(d.mac) + '</span>' +
            '</div>' +
            '<div class="device-actions" style="margin-top:8px;">' +
            '<button type="button" class="btn-primary btn-sm" data-access-pick="' + U.esc(d.id) + '">Abrir este aparelho</button>' +
            '</div></div>'
          );
        }).join('') +
        '</div></div>';
      return;
    }

    if (!device) {
      state.access.matches = [];
      state.access.deviceId = null;
      el.innerHTML = '';
      return;
    }

    var expiry = device.expires_at
      ? U.esc(V.formatDateBR(device.expires_at)) + ' ' + expiryBadge(device.expires_at)
      : '—';
    var entry = device.start_date ? U.esc(V.formatDateBR(device.start_date)) : '—';
    var playlist = device.playlist_id ? playlistById(device.playlist_id) : null;
    var blocked = device.status === 'blocked';

    el.innerHTML =
      '<div class="card access-device">' +
      '<div class="card-head">' +
      '<div>' +
      '<h2><span class="device-code">' + U.esc(device.device_id) + '</span> ' +
      U.badge(device.status) + ' ' + U.appChip(device.app_name) + '</h2>' +
      '<p>MAC <b class="mono">' + U.esc(device.mac || '—') + '</b> · cliente <b>' +
      U.esc(device.client_name || '—') + '</b></p>' +
      '</div>' +
      '<button type="button" class="btn-outline btn-sm" data-access-action="close">Fechar acesso</button>' +
      '</div>' +
      '<div class="access-grid">' +
      '<div><span>Data de entrada</span><b>' + entry + '</b></div>' +
      '<div><span>Data de saída</span><b>' + expiry + '</b></div>' +
      '<div><span>Status</span><b>' + U.badge(device.status) + '</b></div>' +
      '<div><span>Dispositivo</span><b>' + U.esc(deviceLabel(device)) + '</b></div>' +
      '<div><span>Playlist</span><b>' + U.esc(playlist ? playlist.name : '—') + '</b></div>' +
      '</div>' +
      listSummary(device) +
      (blocked && device.block_reason
        ? '<p class="small" style="color:#fca5a5;margin-top:8px;">Motivo do bloqueio: <b>' +
          U.esc(device.block_reason) + '</b></p>'
        : '') +
      '<div class="access-actions">' +
      '<button type="button" class="btn-primary btn-sm" data-access-action="edit">✏️ Editar tudo</button>' +
      '<button type="button" class="btn-outline btn-sm" data-access-action="list">🎬 Inserir / trocar lista</button>' +
      '<button type="button" class="btn-outline btn-sm" data-access-action="toggle">' +
      (blocked ? '🔓 Liberar' : '⛔ Bloquear') + '</button>' +
      '<button type="button" class="btn-outline btn-sm" data-access-action="copy-code">📋 Copiar código</button>' +
      (device.mac
        ? '<button type="button" class="btn-outline btn-sm" data-access-action="copy-mac">📋 Copiar MAC</button>'
        : '') +
      '<button type="button" class="btn-danger btn-sm" data-access-action="delete">🗑️ Excluir aparelho</button>' +
      '</div>' +
      '<p class="small muted" style="margin-top:10px;">O app recebe qualquer mudança em até 10 segundos (polling).</p>' +
      '</div>';
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



  function resetDeviceForm() {
    document.getElementById('devId').value = '';
    document.getElementById('devCode').value = '';
    document.getElementById('devMac').value = '';
    document.getElementById('devDeviceType').value = '';
    document.getElementById('devDeviceBrand').value = '';
    document.getElementById('devClientName').value = '';
    document.getElementById('devClientPhone').value = '';
    document.getElementById('devStart').value = '';
    document.getElementById('devExpires').value = '';
    document.getElementById('devNotes').value = '';
    var listWrap = document.getElementById('devLists');
    if (listWrap) listWrap.innerHTML = '';
    var listEmpty = document.getElementById('devListsEmpty');
    if (listEmpty) listEmpty.style.display = '';
    document.getElementById('btnDeleteDeviceFromModal').style.display = 'none';
    var codeHint = document.getElementById('devCodeHint');
    codeHint.className = '';
    codeHint.textContent = '';
    var macHint = document.getElementById('devMacHint');
    macHint.className = '';
    macHint.textContent = 'Aceita com hífen, sem separador ou minúsculo. Normaliza para AA:BB:CC:DD:EE:FF.';
  }

  function openDeviceModal(device, prefill) {
    state.editDevice = device || null;
    resetDeviceForm();

    var firstApp = state.apps.filter(function (a) { return a.active; })[0] || state.apps[0];
    var appName = device ? device.app_name : (prefill && prefill.app_name) || (firstApp ? firstApp.name : '');
    fillDeviceAppSelect(appName);
    updateDeviceAppHints();

    if (device) {
      document.getElementById('deviceModalTitle').textContent = 'Aparelho ' + device.device_id;
      document.getElementById('devId').value = device.id;
      document.getElementById('devCode').value = device.device_id;
      document.getElementById('devMac').value = device.mac || '';
      document.getElementById('devDeviceType').value = device.device_type || '';
      document.getElementById('devDeviceBrand').value = device.device_brand || '';
      document.getElementById('devClientName').value = device.client_name || '';
      document.getElementById('devClientPhone').value = device.client_phone || linkedClientPhone(device);
      document.getElementById('devStart').value = device.start_date ? String(device.start_date).slice(0, 10) : '';
      document.getElementById('devExpires').value = device.expires_at ? String(device.expires_at).slice(0, 10) : '';
      document.getElementById('devNotes').value = device.notes || '';
      document.getElementById('btnDeleteDeviceFromModal').style.display = '';
    } else {
      document.getElementById('deviceModalTitle').textContent = 'Novo aparelho';
      if (prefill) {
        document.getElementById('devMac').value = prefill.mac || '';
        document.getElementById('devCode').value = prefill.code || '';
        document.getElementById('devCode').dispatchEvent(new Event('input'));
      }
    }

    renderDeviceLists(device);
    fillPlaylistSelect(document.getElementById('devApp').value, device ? device.playlist_id : '');
    U.openModal('modalDevice');
  }

  function linkedClientPhone(device) {
    var c = state.clients.filter(function (x) {
      return x.app_name === device.app_name && x.device_id === device.device_id;
    })[0];
    return c ? c.phone || '' : '';
  }

  function deviceLabel(device) {
    var type = String((device && device.device_type) || '').trim();
    var brand = String((device && device.device_brand) || '').trim();
    if (type && brand) return type + ' · ' + brand;
    return type || brand || '—';
  }

  async function saveDevice() {
    var app = appByName(document.getElementById('devApp').value);
    var code = document.getElementById('devCode').value;
    var macInput = document.getElementById('devMac').value;
    var clientName = document.getElementById('devClientName').value.trim();
    var clientPhone = document.getElementById('devClientPhone').value.trim();
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

    if (!clientName) {
      document.getElementById('devClientName').focus();
      return U.toast('Informe o nome do cliente para aprovar o aparelho.', 'err');
    }
    if (String(clientPhone).replace(/\D/g, '').length < 10) {
      document.getElementById('devClientPhone').focus();
      return U.toast('Informe o WhatsApp do cliente (com DDD) para aprovar.', 'err');
    }

    var collected = collectDeviceLists();
    if (collected.error) return U.toast(collected.error, 'err');
    var lists = collected.lists;

    var playlistId = document.getElementById('devPlaylist').value || null;
    var linkedPlaylist = playlistId ? playlistById(playlistId) : null;

    if (!lists.length && linkedPlaylist) {
      // Só escolheu a playlist: ela vira a lista do aparelho e vai para o app.
      lists = [listDataFromPlaylist(linkedPlaylist)];
    }
    var listData = packListData(lists);

    if (!listData) {
      if (!confirm('Aprovar este aparelho SEM lista vinculada?\n\nO app vai ficar aprovado, mas sem conteúdo até você enviar uma lista.')) return;
    }

    var existingDevice = state.editDevice || state.devices.filter(function (d) {
      return d.app_name === app.name &&
        String(d.device_id).toUpperCase() === String(codeCheck.value).toUpperCase();
    })[0] || null;
    var wasCreate = !state.editDevice;
    if (existingDevice && wasCreate) state.editDevice = existingDevice;

    var payload = {
      id: existingDevice ? existingDevice.id : null,
      app_name: app.name,
      device_id: codeCheck.value,
      mac: macCheck.value,
      status: 'approved',
      list_data: listData,
      playlist_id: playlistId,
      device_type: document.getElementById('devDeviceType').value || null,
      device_brand: document.getElementById('devDeviceBrand').value.trim() || null,
      client_name: clientName,
      client_phone: clientPhone,
      start_date: document.getElementById('devStart').value || null,
      expires_at: document.getElementById('devExpires').value || null,
      notes: document.getElementById('devNotes').value.trim(),
      block_reason: null
    };

    var btn = document.getElementById('btnApproveDevice');
    U.setBusy(btn, true, 'Aprovando...');
    try {
      var saved = await Api.saveDevice(payload);
      var sync = await syncApprovedClient(saved, clientPhone);
      U.closeModal('modalDevice');

      // Mantém o cartão de acesso apontando para o aparelho salvo,
      // inclusive no cadastro novo, para o "Editar tudo" continuar disponível.
      state.access.mac = saved.mac || state.access.mac;
      state.access.code = saved.device_id || state.access.code;
      state.access.matches = [saved.id];
      state.access.deviceId = saved.id;
      state.access.statusFilter = '';

      var missing = [];
      if (payload.start_date && !saved.start_date) missing.push('data de entrada');
      if (payload.device_type && !saved.device_type) missing.push('dispositivo em uso');
      if (payload.device_brand && !saved.device_brand) missing.push('marca/modelo');
      if (payload.client_phone && !saved.client_phone) missing.push('WhatsApp no aparelho');

      if (missing.length) {
        U.toast(
          (wasCreate && existingDevice
            ? 'Cadastro existente atualizado, mas não gravou: '
            : 'Aparelho ' + saved.device_id + ' salvo, mas não gravou: ') + missing.join(', ') + '. ' +
          'Rode o sql/005_access_reset.sql no Supabase e salve de novo.' +
          (saved.status === 'approved' && sync.ok ? ' O cliente já está em Clientes.' : ''),
          'err',
          12000
        );
      } else if (sync.ok) {
        U.toast(
          wasCreate && existingDevice
            ? 'Cadastro existente atualizado e enviado para Clientes.'
            : 'Aparelho ' + saved.device_id + ' aprovado e enviado para Clientes.',
          'ok',
          8000
        );
      } else {
        U.toast('Aparelho ' + saved.device_id + ' aprovado. O app recebe em até 10s.', 'ok');
      }
      await refreshAll(true);
    } catch (err) {
      U.toast(U.errorMessage(err), 'err', 9000);
    } finally {
      U.setBusy(btn, false);
    }
  }

  async function syncApprovedClient(device, phone) {
    if (device.status !== 'approved') return { ok: false, reason: 'not-approved' };
    var name = String(device.client_name || '').trim();
    if (!name || !phone) return { ok: false, reason: 'missing' };

    var existing = state.clients.filter(function (c) {
      return c.app_name === device.app_name && c.device_id === device.device_id;
    })[0];

    await Api.saveClient({
      id: existing ? existing.id : null,
      name: name,
      phone: phone,
      app_name: device.app_name,
      device_id: device.device_id,
      expires_at: device.expires_at || null,
      notes: device.notes || ''
    });
    return { ok: true, created: !existing };
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
      if (state.access.deviceId === d.id) clearAccess(true);
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

    if (linked.length > 1) {
      hint.textContent = 'Esta lista já está em ' + linked.length +
        ' aparelhos. Ao salvar, todos recebem a versão atualizada.';
    } else if (linked.length === 1) {
      hint.textContent = 'Ao salvar, o aparelho ' + linked[0].device_id + ' recebe a lista atualizada.';
    } else {
      hint.textContent = 'Opcional. Ao salvar, a lista é enviada para este aparelho.';
    }

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
      var targetClient = document.getElementById('plClient').value.trim();

      // Aparelhos que já usavam esta lista + o aparelho escolhido no modal.
      var toUpdate = [];
      if (state.editPlaylist) {
        linkedDevices(state.editPlaylist.id).forEach(function (d) { toUpdate.push(d); });
      }
      if (targetId) {
        var chosen = deviceById(targetId);
        if (chosen && !toUpdate.some(function (d) { return d.id === chosen.id; })) {
          toUpdate.push(chosen);
        }
      }

      if (toUpdate.length) {
        await Promise.all(toUpdate.map(function (d) {
          var isChosen = targetId && d.id === targetId;
          return Api.saveDevice({
            id: d.id,
            app_name: d.app_name,
            device_id: d.device_id,
            mac: d.mac,
            status: d.status,
            list_data: listDataFromPlaylist(saved),
            playlist_id: saved.id,
            client_name: (isChosen ? targetClient : '') || d.client_name || '',
            start_date: d.start_date,
            expires_at: d.expires_at,
            notes: d.notes,
            block_reason: d.block_reason
          });
        }));
      }

      U.closeModal('modalPlaylist');
      U.toast(
        toUpdate.length
          ? 'Lista salva e enviada para ' + toUpdate.length + ' aparelho(s).'
          : 'Lista salva.',
        'ok'
      );
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
      await syncDeviceFromClient(payload.app_name, payload.device_id, payload);
      U.closeModal('modalClient');
      U.toast('Cliente salvo.', 'ok');
      await refreshAll(true);
    } catch (err) {
      U.toast(U.errorMessage(err), 'err', 9000);
    } finally {
      U.setBusy(btn, false);
    }
  }

  async function syncDeviceFromClient(appName, deviceCode, client) {
    if (!appName || !deviceCode) return;
    var d = state.devices.filter(function (x) {
      return x.app_name === appName && x.device_id === deviceCode;
    })[0];
    if (!d) return;
    await Api.saveDevice({
      id: d.id,
      app_name: d.app_name,
      device_id: d.device_id,
      mac: d.mac,
      status: d.status,
      list_data: d.list_data,
      playlist_id: d.playlist_id,
      client_name: client.name || '',
      client_phone: client.phone || '',
      start_date: d.start_date,
      expires_at: client.expires_at || null,
      notes: d.notes,
      block_reason: d.block_reason
    });
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
      await syncDeviceFromClient(updated.app_name, updated.device_id, updated);
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

  /* --------------------------- servidores Xtream -------------------------- */

  function xtreamSqlMissing() {
    if (!state.xtreamMissing) return false;
    U.toast('Rode o dashboard/sql/006_xtream_accounts.sql no Supabase primeiro.', 'err', 9000);
    return true;
  }

  async function addXtreamServer() {
    if (xtreamSqlMissing()) return;
    var name = document.getElementById('srvName').value.trim();
    var url = document.getElementById('srvUrl').value.trim();
    if (!name) return U.toast('Informe o nome do servidor.', 'err');
    if (!/^https?:\/\//i.test(url)) {
      return U.toast('Endereço inválido. Use http:// ou https://.', 'err');
    }

    try {
      await Api.saveXtreamServer({
        app_name: 'McPlayer',
        name: name,
        url: url,
        sort_order: 100,
        active: true
      });
      document.getElementById('srvName').value = '';
      document.getElementById('srvUrl').value = '';
      U.toast('Servidor adicionado.', 'ok');
      await refreshAll(true);
    } catch (err) {
      U.toast(U.errorMessage(err), 'err', 9000);
    }
  }

  async function toggleXtreamServer(id) {
    if (xtreamSqlMissing()) return;
    var server = (state.xtreamServers || []).find(function (s) {
      return String(s.id) === String(id);
    });
    if (!server) return;

    try {
      await Api.saveXtreamServer({
        id: server.id,
        app_name: server.app_name,
        name: server.name,
        url: server.url,
        sort_order: server.sort_order,
        active: !server.active
      });
      U.toast(server.active ? 'Servidor desativado.' : 'Servidor ativado.', 'ok');
      await refreshAll(true);
    } catch (err) {
      U.toast(U.errorMessage(err), 'err', 9000);
    }
  }

  async function deleteXtreamServer(id) {
    if (xtreamSqlMissing()) return;
    var server = (state.xtreamServers || []).find(function (s) {
      return String(s.id) === String(id);
    });
    if (!server) return;
    if (!confirm('Excluir o servidor "' + server.name + '"?\n\nO app deixa de testar este servidor no login.')) {
      return;
    }

    try {
      await Api.deleteXtreamServer(server.id);
      U.toast('Servidor excluído.', 'ok');
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
      document.getElementById('resetBox').classList.add('hidden');
      this.classList.add('hidden');
      document.getElementById('btnForgot').classList.add('hidden');
      document.getElementById('btnBackLogin').classList.remove('hidden');
      hideLoginMsg();
    });
    document.getElementById('btnBackLogin').addEventListener('click', function () {
      document.getElementById('loginTitle').textContent = 'Entrar como administrador';
      document.getElementById('signupBox').classList.add('hidden');
      document.getElementById('resetBox').classList.add('hidden');
      this.classList.add('hidden');
      document.getElementById('btnShowSignup').classList.remove('hidden');
      document.getElementById('btnForgot').classList.remove('hidden');
      hideLoginMsg();
    });

    document.getElementById('btnForgot').addEventListener('click', showResetForm);
    document.getElementById('resetForm').addEventListener('submit', onResetPassword);
    document.getElementById('btnSaveNewPass').addEventListener('click', saveNewPassword);

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
    document.getElementById('overviewStats').addEventListener('click', function (e) {
      var card = e.target.closest('button[data-stat-status]');
      if (card) openStatusList(card.dataset.statStatus);
    });

    // Filtros
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

    // Acesso por MAC + código
    document.getElementById('accessForm').addEventListener('submit', onAccessSubmit);
    document.getElementById('accessMac').addEventListener('input', function () {
      this.value = V.formatMacInput(this.value);
    });
    document.getElementById('accessCode').addEventListener('input', function () {
      this.value = this.value.toUpperCase();
    });
    document.getElementById('accessApp').addEventListener('change', function () {
      state.access.app = this.value;
    });
    document.getElementById('accessResult').addEventListener('click', onAccessAction);

    // Botões de criação
    document.getElementById('btnNewPlaylist').addEventListener('click', function () { openPlaylistModal(null); });
    document.getElementById('btnNewClient').addEventListener('click', function () { openClientModal(null); });
    document.getElementById('btnNewApp').addEventListener('click', function () { openAppModal(null); });
    document.getElementById('btnExport').addEventListener('click', exportBackup);

    // Ações em listas dinâmicas
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
    document.getElementById('btnAddDevList').addEventListener('click', function () {
      var row = addDeviceListRow({ type: 'm3u' });
      if (row) {
        var input = row.querySelector('[data-list-url]');
        if (input) input.focus();
      }
    });
    document.getElementById('devPlaylist').addEventListener('change', function () {
      var pl = playlistById(this.value);
      if (!pl) return;
      addDeviceListRow(listDataFromPlaylist(pl));
      U.toast('Playlist "' + pl.name + '" adicionada à relação de listas.', 'ok');
    });
    document.getElementById('btnApproveDevice').addEventListener('click', saveDevice);
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

    // Servidores Xtream
    var btnAddServer = document.getElementById('btnAddServer');
    if (btnAddServer) btnAddServer.addEventListener('click', addXtreamServer);
    var serversBody = document.getElementById('serversTableBody');
    if (serversBody) {
      serversBody.addEventListener('click', function (e) {
        var toggle = e.target.closest('[data-server-toggle]');
        if (toggle) {
          toggleXtreamServer(toggle.dataset.serverToggle);
          return;
        }
        var del = e.target.closest('[data-server-delete]');
        if (del) deleteXtreamServer(del.dataset.serverDelete);
      });
    }

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
    if (tab === 'audit') {
      renderAccess();
      renderAudit();
    }
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

  /* --------------------------- recuperar senha --------------------------- */

  function showResetForm() {
    document.getElementById('loginTitle').textContent = 'Recuperar senha';
    document.getElementById('resetBox').classList.remove('hidden');
    document.getElementById('signupBox').classList.add('hidden');
    document.getElementById('btnShowSignup').classList.add('hidden');
    document.getElementById('btnForgot').classList.add('hidden');
    document.getElementById('btnBackLogin').classList.remove('hidden');
    document.getElementById('resetMsg').className = 'auth-msg hidden';
    document.getElementById('resetEmail').value = document.getElementById('loginEmail').value.trim();
    hideLoginMsg();
  }

  async function onResetPassword(e) {
    e.preventDefault();
    var box = document.getElementById('resetMsg');
    box.className = 'auth-msg hidden';
    var email = document.getElementById('resetEmail').value.trim();
    if (!email) {
      box.textContent = 'Informe o e-mail da conta.';
      box.className = 'auth-msg';
      return;
    }
    var btn = document.getElementById('resetBtn');
    U.setBusy(btn, true, 'Enviando...');
    try {
      await Api.resetPassword(email);
      box.textContent =
        'Se este e-mail estiver cadastrado, o link de recuperação chega em instantes. ' +
        'Confira também a caixa de spam.';
      box.className = 'auth-msg ok';
    } catch (err) {
      box.textContent = U.errorMessage(err);
      box.className = 'auth-msg';
    } finally {
      U.setBusy(btn, false);
    }
  }

  function showNewPasswordModal() {
    document.getElementById('loginView').classList.add('hidden');
    document.getElementById('appView').classList.add('hidden');
    document.getElementById('newPassMsg').className = 'auth-msg hidden';
    document.getElementById('newPass1').value = '';
    document.getElementById('newPass2').value = '';
    U.openModal('modalNewPassword');
  }

  async function saveNewPassword() {
    var box = document.getElementById('newPassMsg');
    box.className = 'auth-msg hidden';
    var p1 = document.getElementById('newPass1').value;
    var p2 = document.getElementById('newPass2').value;

    if (p1.length < 6) {
      box.textContent = 'A senha precisa ter pelo menos 6 caracteres.';
      box.className = 'auth-msg';
      return;
    }
    if (p1 !== p2) {
      box.textContent = 'As duas senhas não conferem.';
      box.className = 'auth-msg';
      return;
    }

    var btn = document.getElementById('btnSaveNewPass');
    U.setBusy(btn, true, 'Salvando...');
    try {
      await Api.updatePassword(p1);
      state.recoveryMode = false;
      U.closeModal('modalNewPassword');
      try { await Api.signOut(); } catch (_err) { /* segue para o login */ }
      if (window.history && window.history.replaceState) {
        window.history.replaceState(null, '', window.location.pathname + window.location.search);
      }
      showLogin('Senha alterada com sucesso. Entre com a nova senha.', true);
    } catch (err) {
      box.textContent = U.errorMessage(err);
      box.className = 'auth-msg';
    } finally {
      U.setBusy(btn, false);
    }
  }

  async function toggleBlock(device, btn) {
    if (device.status === 'blocked') {
      if (!confirm('Liberar o aparelho ' + device.device_id + '?\n\nSe ele tiver lista, volta como aprovado; se não tiver, volta como pendente.')) return;
      var next = device.list_data ? 'approved' : 'pending';
      U.setBusy(btn, true, '...');
      try {
        var updated = await Api.setDeviceStatus(device.id, next, null);
        var sync = updated.status === 'approved'
          ? await syncApprovedClient(updated, updated.client_phone || linkedClientPhone(updated))
          : { ok: false };
        if (updated.status === 'approved' && sync.ok) {
          U.toast('Aparelho ' + device.device_id + ' liberado e enviado para Clientes.', 'ok');
        } else if (updated.status === 'approved') {
          U.toast('Aparelho ' + device.device_id + ' liberado. Informe nome e WhatsApp no cadastro para aparecer em Clientes.', 'err', 9000);
        } else {
          U.toast('Aparelho ' + device.device_id + ' liberado.', 'ok');
        }
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

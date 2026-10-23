/* Camada única de acesso ao Supabase.
 *
 * Todo o painel usa este módulo. As regras de código/MAC vêm de public.apps,
 * então McPlayer, NexPlay e qualquer app futuro passam pelo MESMO caminho.
 */
(function () {
  'use strict';

  var cfg = window.DASHBOARD_CONFIG;
  var lib = window.supabase;

  if (!lib || !lib.createClient) {
    document.addEventListener('DOMContentLoaded', function () {
      document.body.innerHTML =
        '<div class="fatal">Não foi possível carregar a biblioteca do Supabase. ' +
        'Verifique sua conexão e recarregue a página.</div>';
    });
    return;
  }

  var sb = lib.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true
    },
    realtime: { params: { eventsPerSecond: 10 } }
  });

  function unwrap(res) {
    if (res.error) throw res.error;
    return res.data;
  }

  function cleanPayload(obj) {
    var out = {};
    Object.keys(obj).forEach(function (k) {
      if (obj[k] !== undefined) out[k] = obj[k];
    });
    return out;
  }

  var Api = {
    sb: sb,

    /* ---------------------------- autenticação ---------------------------- */
    getSession: function () {
      return sb.auth.getSession().then(function (res) {
        if (res.error) throw res.error;
        return res.data.session;
      });
    },

    onAuthStateChange: function (cb) {
      return sb.auth.onAuthStateChange(function (event, session) {
        cb(event, session);
      });
    },

    signIn: function (email, password) {
      return sb.auth.signInWithPassword({ email: email, password: password }).then(unwrap);
    },

    signUp: function (email, password) {
      return sb.auth
        .signUp({
          email: email,
          password: password,
          options: { emailRedirectTo: window.location.href.split('#')[0] }
        })
        .then(unwrap);
    },

    signOut: function () {
      return sb.auth.signOut().then(function (res) {
        if (res.error) throw res.error;
        return true;
      });
    },

    isAdmin: function () {
      return sb.rpc('is_admin').then(function (res) {
        if (res.error) throw res.error;
        return !!res.data;
      });
    },

    claimAdmin: function () {
      return sb.rpc('claim_admin').then(function (res) {
        if (res.error) throw res.error;
        return !!res.data;
      });
    },

    /* -------------------------------- apps -------------------------------- */
    loadApps: function () {
      return sb.from('apps').select('*').order('sort_order', { ascending: true }).then(unwrap);
    },

    saveApp: function (app, originalName) {
      var payload = cleanPayload({
        name: String(app.name || '').trim(),
        code_pattern: String(app.code_pattern || '').trim(),
        code_hint: String(app.code_hint || '').trim(),
        normalize_upper: !!app.normalize_upper,
        active: app.active !== false,
        sort_order: Number(app.sort_order || 100)
      });

      if (originalName) {
        return sb
          .from('apps')
          .update(payload)
          .eq('name', originalName)
          .select()
          .single()
          .then(unwrap);
      }
      return sb.from('apps').insert(payload).select().single().then(unwrap);
    },

    deleteApp: function (name) {
      return sb.from('apps').delete().eq('name', name).then(function (res) {
        if (res.error) throw res.error;
        return true;
      });
    },

    /* ------------------------------ aparelhos ----------------------------- */
    loadDevices: function () {
      return sb.from('devices').select('*').order('created_at', { ascending: false }).then(unwrap);
    },

    saveDevice: function (device) {
      var payload = cleanPayload({
        app_name: device.app_name,
        device_id: device.device_id,
        mac: device.mac || null,
        status: device.status || 'pending',
        list_data: device.list_data || null,
        playlist_id: device.playlist_id || null,
        client_name: device.client_name || null,
        expires_at: device.expires_at || null,
        notes: device.notes || null,
        block_reason: device.block_reason || null
      });

      if (device.id) {
        return sb.from('devices').update(payload).eq('id', device.id).select().single().then(unwrap);
      }
      return sb.from('devices').insert(payload).select().single().then(unwrap);
    },

    setDeviceStatus: function (id, status, reason) {
      return sb
        .from('devices')
        .update({ status: status, block_reason: status === 'blocked' ? reason || null : null })
        .eq('id', id)
        .select()
        .single()
        .then(unwrap);
    },

    // Exclusão só pelo RPC: exige o código exato digitado de novo.
    deleteDevice: function (id, code) {
      return sb.rpc('admin_delete_device', { p_id: id, p_code: code }).then(function (res) {
        if (res.error) throw res.error;
        return !!res.data;
      });
    },

    /* -------------------------------- listas ------------------------------ */
    loadPlaylists: function () {
      return sb.from('playlists').select('*').order('name', { ascending: true }).then(unwrap);
    },

    savePlaylist: function (playlist) {
      var payload = cleanPayload({
        app_name: playlist.app_name,
        name: playlist.name,
        type: playlist.type,
        url: playlist.url || null,
        server_url: playlist.server_url || null,
        username: playlist.username || null,
        password: playlist.password || null,
        notes: playlist.notes || null
      });

      if (playlist.id) {
        return sb.from('playlists').update(payload).eq('id', playlist.id).select().single().then(unwrap);
      }
      return sb.from('playlists').insert(payload).select().single().then(unwrap);
    },

    deletePlaylist: function (id) {
      return sb.from('playlists').delete().eq('id', id).then(function (res) {
        if (res.error) throw res.error;
        return true;
      });
    },

    /* ------------------------------- clientes ----------------------------- */
    loadClients: function () {
      return sb.from('clients').select('*').order('expires_at', { ascending: true }).then(unwrap);
    },

    saveClient: function (client) {
      var payload = cleanPayload({
        name: client.name,
        phone: client.phone,
        app_name: client.app_name || null,
        device_id: client.device_id || null,
        expires_at: client.expires_at || null,
        notes: client.notes || null
      });

      if (client.id) {
        return sb.from('clients').update(payload).eq('id', client.id).select().single().then(unwrap);
      }
      return sb.from('clients').insert(payload).select().single().then(unwrap);
    },

    deleteClient: function (id) {
      return sb.from('clients').delete().eq('id', id).then(function (res) {
        if (res.error) throw res.error;
        return true;
      });
    },

    /* ------------------------------ auditoria ----------------------------- */
    loadAudit: function (limit) {
      return sb
        .from('audit_logs')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(limit || cfg.auditPageSize)
        .then(unwrap);
    },

    loadAdmins: function () {
      return sb.from('admins').select('*').order('created_at', { ascending: true }).then(unwrap);
    },

    /* ------------------------------- backup ------------------------------- */
    exportAll: function () {
      return Promise.all([
        this.loadApps(),
        this.loadDevices(),
        this.loadPlaylists(),
        this.loadClients(),
        this.loadAudit(5000),
        this.loadAdmins()
      ]).then(function (rows) {
        return {
          backup_at: new Date().toISOString(),
          source: cfg.supabaseUrl,
          tables: {
            apps: rows[0],
            devices: rows[1],
            playlists: rows[2],
            clients: rows[3],
            audit_logs: rows[4],
            admins: rows[5]
          }
        };
      });
    },

    /* ------------------------------- realtime ----------------------------- */
    subscribe: function (onChange) {
      var channel = sb
        .channel('dashboard-changes')
        .on('postgres_changes', { event: '*', schema: 'public', table: 'devices' }, onChange)
        .on('postgres_changes', { event: '*', schema: 'public', table: 'playlists' }, onChange)
        .on('postgres_changes', { event: '*', schema: 'public', table: 'clients' }, onChange)
        .on('postgres_changes', { event: '*', schema: 'public', table: 'apps' }, onChange)
        .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'audit_logs' }, onChange)
        .subscribe(function (status) {
          if (window.Dashboard && window.Dashboard.onRealtimeStatus) {
            window.Dashboard.onRealtimeStatus(status);
          }
        });

      return function () {
        sb.removeChannel(channel);
      };
    }
  };

  window.Api = Api;
})();

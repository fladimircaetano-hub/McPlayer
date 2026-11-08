/* Conversor M3U -> Xtream Codes.
 * Tudo é processado no navegador: nada é enviado ao Supabase ou a outro servidor.
 */
(function () {
  'use strict';

  document.addEventListener('DOMContentLoaded', init);

  function init() {
    var input = document.getElementById('m3uUrl');
    var btnConvert = document.getElementById('btnConvertM3u');
    if (!input || !btnConvert) return;

    var btnClear = document.getElementById('btnClearM3u');
    var btnCopyAll = document.getElementById('btnCopyAllM3u');
    var msg = document.getElementById('m3uMsg');
    var result = document.getElementById('m3uResult');

    btnConvert.addEventListener('click', function () {
      convert(input, msg, result);
    });

    if (btnClear) {
      btnClear.addEventListener('click', function () {
        input.value = '';
        clearFields();
        hideMessage(msg);
        if (result) result.classList.add('hidden');
        input.focus();
      });
    }

    if (btnCopyAll) {
      btnCopyAll.addEventListener('click', function () {
        if (!result || result.classList.contains('hidden')) return;
        var host = fieldValue('m3uHost');
        if (!host) return;
        copyText(
          'Servidor / Host: ' + host +
          '\nUsuário: ' + fieldValue('m3uUser') +
          '\nSenha: ' + fieldValue('m3uPass')
        );
      });
    }

    Array.prototype.forEach.call(document.querySelectorAll('[data-copy-m3u]'), function (btn) {
      btn.addEventListener('click', function () {
        copyText(fieldValue(btn.dataset.copyM3u));
      });
    });

    input.addEventListener('keydown', function (e) {
      if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') convert(input, msg, result);
    });

    input.addEventListener('input', function () {
      hideMessage(msg);
      if (result) result.classList.add('hidden');
    });
  }

  function convert(input, msg, result) {
    hideMessage(msg);
    if (result) result.classList.add('hidden');
    clearFields();

    var raw = input.value.trim();
    if (!raw) return showMessage(msg, 'Cole o link M3U antes de converter.');

    var url = parseUrl(raw);
    if (!url) {
      return showMessage(msg, 'Link inválido. Cole a URL completa, começando com http:// ou https://.');
    }

    var creds = extract(url);
    if (!creds.username || !creds.password) {
      return showMessage(msg, 'Esta lista M3U não possui credenciais do Xtream Codes integradas.');
    }

    setFieldValue('m3uHost', creds.host);
    setFieldValue('m3uUser', creds.username);
    setFieldValue('m3uPass', creds.password);
    if (result) result.classList.remove('hidden');
  }

  function parseUrl(raw) {
    if (/\s/.test(raw)) return null;

    var url = null;
    try {
      url = new URL(raw);
    } catch (_e) {
      url = null;
    }
    if (!url) {
      try {
        url = new URL('http://' + raw);
      } catch (_e2) {
        return null;
      }
    }
    if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
    return url;
  }

  function extract(url) {
    return {
      host: buildHost(url),
      username: readParam(url, ['username', 'user']),
      password: readParam(url, ['password', 'pass'])
    };
  }

  function buildHost(url) {
    var path = url.pathname || '';
    var match = path.match(/\/(?:get\.php|panel_api\.php|player_api\.php|live|movie)(?:\/|$)/i);
    var prefix = match ? path.slice(0, match.index) : '';
    return url.protocol + '//' + url.host + prefix;
  }

  function readParam(url, names) {
    var i;
    for (i = 0; i < names.length; i++) {
      var direct = url.searchParams.get(names[i]);
      if (direct) return direct.trim();
    }

    var pairs = (url.search || '').replace(/^\?/, '').split('&');
    for (i = 0; i < pairs.length; i++) {
      var eq = pairs[i].indexOf('=');
      if (eq < 0) continue;
      var key = safeDecode(pairs[i].slice(0, eq)).toLowerCase();
      if (names.indexOf(key) < 0) continue;
      return safeDecode(pairs[i].slice(eq + 1).replace(/\+/g, ' ')).trim();
    }
    return '';
  }

  function safeDecode(value) {
    try {
      return decodeURIComponent(value);
    } catch (_e) {
      return value;
    }
  }

  function fieldValue(id) {
    var el = document.getElementById(id);
    return el ? el.value : '';
  }

  function setFieldValue(id, value) {
    var el = document.getElementById(id);
    if (el) el.value = value;
  }

  function clearFields() {
    setFieldValue('m3uHost', '');
    setFieldValue('m3uUser', '');
    setFieldValue('m3uPass', '');
  }

  function showMessage(msg, text) {
    if (!msg) return;
    msg.textContent = text;
    msg.className = 'auth-msg';
  }

  function hideMessage(msg) {
    if (!msg) return;
    msg.textContent = '';
    msg.className = 'auth-msg hidden';
  }

  function copyText(text) {
    if (!text) return;
    var done = function () { toast('Copiado com sucesso!', 'ok', 2200); };
    var fail = function () { toast('Não foi possível copiar. Selecione o texto e use Ctrl+C.', 'err', 5000); };

    if (window.UI && window.UI.copyText) {
      window.UI.copyText(text).then(done, fail);
      return;
    }

    var ta = document.createElement('textarea');
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    try {
      document.execCommand('copy');
      done();
    } catch (_e) {
      fail();
    }
    ta.remove();
  }

  function toast(message, type, ms) {
    if (window.UI && window.UI.toast) window.UI.toast(message, type, ms);
  }
})();

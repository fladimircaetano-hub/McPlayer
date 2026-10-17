import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/xtream_account.dart';
import '../activation/activation_config.dart';

class StorageService {
  static const String _keyFavorites = 'iptv_favorites';
  static const String _keyLastM3uUrl = 'iptv_last_m3u_url';
  static const String _keyLastM3uPath = 'iptv_last_m3u_path';
  static const String _keyXtreamAccount = 'iptv_xtream_account';
  static const String _keyXtreamAccounts = 'iptv_xtream_accounts';
  static const String _keyRecentUrls = 'iptv_recent_urls';
  static const String _keyDeviceId = 'device_id';
  static const String _keyDeviceMac = 'device_mac_virtual';
  static const String _keyStreamFormat = 'pref_stream_format';
  static const String _keyPin = 'pref_pin';
  static const String _keyHiddenSections = 'pref_hidden_sections';
  static const String _keyShowCounts = 'pref_show_counts';
  static const String _keyTmdb = 'pref_tmdb';
  static const String _keyKeepScreenOn = 'pref_keep_screen_on';
  static const String _keyLanguage = 'pref_language';

  final SharedPreferences _prefs;
  
  // Lock para operações atômicas em chaves críticas
  final Map<String, Completer<void>> _writeLocks = {};

  /// Idioma atual ('pt'/'en'). Notifica ouvintes para troca imediata
  /// sem reiniciar o app.
  final ValueNotifier<String> languageNotifier = ValueNotifier('pt');

  StorageService(this._prefs) {
    languageNotifier.value = getLanguage();
  }

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  /// Garante que escritas concorrentes na mesma chave não corrompam dados
  Future<T> _atomicWrite<T>(String key, Future<T> Function() write) async {
    // Espera qualquer escrita anterior na mesma chave terminar
    while (_writeLocks[key] != null) {
      await _writeLocks[key]!.future;
    }
    final completer = Completer<void>();
    _writeLocks[key] = completer;
    try {
      return await write();
    } finally {
      _writeLocks.remove(key);
      completer.complete();
    }
  }

  // --- Favoritos ---
  Set<String> getFavorites() {
    final list = _prefs.getStringList(_keyFavorites) ?? [];
    return list.toSet();
  }

  Future<void> toggleFavorite(String streamId) async {
    await _atomicWrite(_keyFavorites, () async {
      final current = getFavorites();
      if (current.contains(streamId)) {
        current.remove(streamId);
      } else {
        current.add(streamId);
      }
      await _prefs.setStringList(_keyFavorites, current.toList());
    });
  }

  bool isFavorite(String streamId) {
    final current = getFavorites();
    return current.contains(streamId);
  }

  // --- M3U URL / Arquivo ---
  String? getLastM3uUrl() => _prefs.getString(_keyLastM3uUrl);

  Future<void> saveLastM3uUrl(String url) async {
    await _atomicWrite(_keyLastM3uUrl, () async {
      await _prefs.setString(_keyLastM3uUrl, url);
      await addRecentUrl(url);
    });
  }

  String? getLastM3uPath() => _prefs.getString(_keyLastM3uPath);

  Future<void> saveLastM3uPath(String path) async {
    await _prefs.setString(_keyLastM3uPath, path);
  }

  // --- URLs Recentes ---
  List<String> getRecentUrls() {
    return _prefs.getStringList(_keyRecentUrls) ?? [];
  }

  Future<void> addRecentUrl(String url) async {
    await _atomicWrite(_keyRecentUrls, () async {
      final recents = getRecentUrls();
      recents.remove(url);
      recents.insert(0, url);
      if (recents.length > 5) {
        recents.removeRange(5, recents.length);
      }
      await _prefs.setStringList(_keyRecentUrls, recents);
    });
  }

  Future<void> removeRecentUrl(String url) async {
    await _atomicWrite(_keyRecentUrls, () async {
      final recents = getRecentUrls();
      recents.remove(url);
      await _prefs.setStringList(_keyRecentUrls, recents);
    });
  }

  // --- Xtream Codes Account ---
  XtreamAccount? getXtreamAccount() {
    final raw = _prefs.getString(_keyXtreamAccount);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return XtreamAccount.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveXtreamAccount(XtreamAccount account) async {
    await _atomicWrite(_keyXtreamAccount, () async {
      final raw = jsonEncode(account.toJson());
      await _prefs.setString(_keyXtreamAccount, raw);
      // Multi-listas: mantém a conta na lista de salvas (sem duplicar).
      final saved = getXtreamAccounts().toList();
      saved.removeWhere((a) =>
          a.serverUrl == account.serverUrl &&
          a.username == account.username);
      saved.insert(0, account);
      await _prefs.setStringList(
        _keyXtreamAccounts,
        saved.map((a) => jsonEncode(a.toJson())).toList(),
      );
    });
  }

  /// Todas as contas Xtream já usadas (p/ trocar de lista sem redigitar).
  /// Migra a conta única antiga para a lista automaticamente.
  List<XtreamAccount> getXtreamAccounts() {
    final list = _prefs.getStringList(_keyXtreamAccounts) ?? [];
    final out = <XtreamAccount>[];
    for (final raw in list) {
      try {
        out.add(XtreamAccount.fromJson(
            jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // Ignora entrada corrompida.
      }
    }
    if (out.isEmpty) {
      final single = getXtreamAccount();
      if (single != null) out.add(single);
    }
    return out;
  }

  Future<void> removeXtreamAccount(XtreamAccount account) async {
    await _atomicWrite(_keyXtreamAccounts, () async {
      final saved = getXtreamAccounts().toList()
        ..removeWhere((a) =>
            a.serverUrl == account.serverUrl &&
            a.username == account.username);
      await _prefs.setStringList(
        _keyXtreamAccounts,
        saved.map((a) => jsonEncode(a.toJson())).toList(),
      );
      // Se removeu a conta ativa, limpa o atalho de sessão também.
      final current = getXtreamAccount();
      if (current != null &&
          current.serverUrl == account.serverUrl &&
          current.username == account.username) {
        await _prefs.remove(_keyXtreamAccount);
      }
    });
  }

  Future<void> clearAll() async {
    await _prefs.clear();
  }

  /// Limpa apenas a sessão ativa (URL M3U / conta Xtream).
  /// Mantém favoritos, URLs recentes e identificação do aparelho.
  Future<void> clearSession() async {
    await _prefs.remove(_keyLastM3uUrl);
    await _prefs.remove(_keyLastM3uPath);
    await _prefs.remove(_keyXtreamAccount);
  }

  // --- Identificação do aparelho (para ativação no provedor) ---
  // A `device_id` é a CHAVE PRIMÁRIA da tabela `devices` do Dashboard, então
  // McPlayer e NexPlay dividem um único espaço de nomes. Por isso os formatos
  // são propositalmente disjuntos (nunca colidem nem se misturam):
  //   - McPlayer: 6 dígitos             -> [0-9]{6}          (ex.: 123456)
  //   - NexPlay : 1 letra + 5 alfanum.  -> [A-Z][A-Z0-9]{5}  (ex.: K7F2Q9)
  // A 1ª posição ser letra garante que um ID NexPlay NUNCA seja só dígitos,
  // então não há como colidir com um ID do McPlayer.
  // MAC virtual persistente (gerado 1x, nunca no logout).
  static final _idRegexMcPlayer = RegExp(r'^\d{6}$');
  static final _idRegexNexPlay = RegExp(r'^[A-Z][A-Z0-9]{5}$');

  static const String _idLetters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _idAlnum = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  String _generateDeviceId() {
    final rnd = Random.secure();
    if (ActivationConfig.idIsAlphanumeric) {
      // NexPlay: 1ª posição sempre letra (não casa com o formato numérico).
      return _idLetters[rnd.nextInt(_idLetters.length)] +
          List.generate(5, (_) => _idAlnum[rnd.nextInt(_idAlnum.length)]).join();
    }
    // McPlayer: apenas numérico (6 dígitos).
    return List.generate(6, (_) => rnd.nextInt(10).toString()).join();
  }

  String getDeviceId() {
    final id = _prefs.getString(_keyDeviceId);
    final regex = ActivationConfig.idIsAlphanumeric
        ? _idRegexNexPlay
        : _idRegexMcPlayer;
    if (id != null && regex.hasMatch(id)) return id;
    return _storeNewDeviceId();
  }

  /// Gera e persiste uma chave NOVA, substituindo a anterior.
  /// Usada pelo check-in quando o Dashboard recusa por colisão de `device_id`
  /// (`409 duplicate key`).
  String newDeviceId() => _storeNewDeviceId();

  String _storeNewDeviceId() {
    final id = _generateDeviceId();
    unawaited(_prefs.setString(_keyDeviceId, id));
    return id;
  }

  String getDeviceMac() {
    var mac = _prefs.getString(_keyDeviceMac);
    if (mac == null || mac.isEmpty) {
      final rnd = Random.secure();
      // 02:xx:xx:xx:xx:xx = unicast administrado localmente (padrão p/ MAC virtual).
      final bytes = [0x02, for (var i = 0; i < 5; i++) rnd.nextInt(256)];
      mac = bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
      unawaited(_prefs.setString(_keyDeviceMac, mac));
    }
    return mac;
  }

  // --- Preferências (Settings) ---

  /// Formato de stream Xtream ao vivo: 'm3u8' ou 'mpegts'.
  String getStreamFormat() =>
      _prefs.getString(_keyStreamFormat) ?? 'm3u8';

  Future<void> setStreamFormat(String v) async {
    await _prefs.setString(
        _keyStreamFormat, v == 'mpegts' ? 'mpegts' : 'm3u8');
  }

  String? getPin() => _prefs.getString(_keyPin);

  Future<void> setPin(String pin) async {
    await _prefs.setString(_keyPin, pin);
  }

  /// Seções ocultas no menu ('live', 'movie', 'series').
  Set<String> getHiddenSections() {
    return (_prefs.getStringList(_keyHiddenSections) ?? []).toSet();
  }

  Future<void> setSectionHidden(String key, bool hidden) async {
    final s = getHiddenSections();
    if (hidden) {
      s.add(key);
    } else {
      s.remove(key);
    }
    await _prefs.setStringList(_keyHiddenSections, s.toList());
  }

  bool getShowCounts() => _prefs.getBool(_keyShowCounts) ?? true;

  Future<void> setShowCounts(bool v) async {
    await _prefs.setBool(_keyShowCounts, v);
  }

  bool getTmdbEnabled() => _prefs.getBool(_keyTmdb) ?? false;

  Future<void> setTmdbEnabled(bool v) async {
    await _prefs.setBool(_keyTmdb, v);
  }

  bool getKeepScreenOn() => _prefs.getBool(_keyKeepScreenOn) ?? true;

  Future<void> setKeepScreenOn(bool v) async {
    await _prefs.setBool(_keyKeepScreenOn, v);
  }

  String getLanguage() => _prefs.getString(_keyLanguage) ?? 'pt';

  Future<void> setLanguage(String v) async {
    final lang = v == 'en' ? 'en' : 'pt';
    await _prefs.setString(_keyLanguage, lang);
    languageNotifier.value = lang;
  }

  Future<void> clearFavorites() async {
    await _prefs.remove(_keyFavorites);
  }
}

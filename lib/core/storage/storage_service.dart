import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/xtream_account.dart';

class StorageService {
  static const String _keyFavorites = 'iptv_favorites';
  static const String _keyLastM3uUrl = 'iptv_last_m3u_url';
  static const String _keyLastM3uPath = 'iptv_last_m3u_path';
  static const String _keyXtreamAccount = 'iptv_xtream_account';
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

  // --- Favoritos ---
  Set<String> getFavorites() {
    final list = _prefs.getStringList(_keyFavorites) ?? [];
    return list.toSet();
  }

  Future<void> toggleFavorite(String streamId) async {
    final current = getFavorites();
    if (current.contains(streamId)) {
      current.remove(streamId);
    } else {
      current.add(streamId);
    }
    await _prefs.setStringList(_keyFavorites, current.toList());
  }

  bool isFavorite(String streamId) {
    final current = getFavorites();
    return current.contains(streamId);
  }

  // --- M3U URL / Arquivo ---
  String? getLastM3uUrl() => _prefs.getString(_keyLastM3uUrl);

  Future<void> saveLastM3uUrl(String url) async {
    await _prefs.setString(_keyLastM3uUrl, url);
    await addRecentUrl(url);
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
    final recents = getRecentUrls();
    recents.remove(url);
    recents.insert(0, url);
    if (recents.length > 5) {
      recents.removeRange(5, recents.length);
    }
    await _prefs.setStringList(_keyRecentUrls, recents);
  }

  Future<void> removeRecentUrl(String url) async {
    final recents = getRecentUrls();
    recents.remove(url);
    await _prefs.setStringList(_keyRecentUrls, recents);
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
    final raw = jsonEncode(account.toJson());
    await _prefs.setString(_keyXtreamAccount, raw);
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
  // ID numérico de 6 dígitos + MAC virtual persistentes (gerados 1x, nunca no logout).
  static final _idRegex = RegExp(r'^\d{6}$');

  String getDeviceId() {
    var id = _prefs.getString(_keyDeviceId);
    if (id == null || !_idRegex.hasMatch(id)) {
      final rnd = Random.secure();
      id = List.generate(6, (_) => rnd.nextInt(10).toString()).join();
      unawaited(_prefs.setString(_keyDeviceId, id));
    }
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

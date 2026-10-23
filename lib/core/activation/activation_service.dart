import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'activation_config.dart';
import 'activation_models.dart';

/// Fala com a tabela `devices` do Supabase (mesma do Dashboard).
///
/// - [checkIn]: registra a chave como `pending` (nunca sobrescreve aprovação).
/// - [fetchStatus]: retorna o estado atual para polling.
/// Sem configuração ([ActivationConfig.isEnabled] == false), tudo vira
/// [ActivationStatus.disabled] e nenhum tráfego de rede acontece.
class ActivationService {
  final Dio _dio;

  /// Quando true, desliga a ativação remota (usado em widget tests para
  /// evitar tráfego de rede e timers periódicos pendentes).
  @visibleForTesting
  static bool testBypass = false;

  /// Habilita logs verbosos para debug de conexão
  @visibleForTesting
  static bool debugLog = false;

  /// Tentativas de criação de chave em caso de colisão de `device_id` (409).
  static const int _maxCreateAttempts = 3;

  ActivationService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 15),
              responseType: ResponseType.json,
              validateStatus: (s) => s != null && s < 500,
            ),
          );

  bool get isEnabled => !testBypass && ActivationConfig.isEnabled;

  /// Public getters for admin screen
  Dio get dio => _dio;
  String get baseUrl => _base;
  Map<String, String> get headers => _headers;

  Map<String, String> get _headers => {
    'apikey': ActivationConfig.supabaseAnonKey,
    'Authorization': 'Bearer ${ActivationConfig.supabaseAnonKey}',
    'Content-Type': 'application/json',
  };

  String get _base =>
      ActivationConfig.supabaseUrl.replaceAll(RegExp(r'/$'), '');

  void _log(String msg) {
    if (debugLog) debugPrint('[ActivationService] $msg');
  }

  /// Registra este aparelho como pendente e devolve o estado atual.
  /// Usa o RPC `device_checkin`, que valida código/MAC no banco e é o único
  /// caminho liberado para a chave anon (a tabela devices tem RLS).
  ///
  /// [regenerateDeviceId] é chamado quando o `device_id` colide com outro
  /// aparelho já cadastrado. Como os formatos de chave são disjuntos
  /// (McPlayer numérico x NexPlay com letra), isso não deveria acontecer —
  /// é só uma rede de segurança. Tenta no máximo [_maxCreateAttempts] chaves.
  Future<ActivationResult> checkIn({
    required String deviceId,
    required String mac,
    String Function()? regenerateDeviceId,
  }) async {
    if (!isEnabled) return const ActivationResult.disabled();
    _log(
      'checkIn: deviceId=$deviceId, mac=$mac, appName=${ActivationConfig.appName}',
    );
    _log('base URL: $_base');
    var id = deviceId;
    try {
      for (var attempt = 1; attempt <= _maxCreateAttempts; attempt++) {
        final res = await _rpc('device_checkin', {
          'p_app': ActivationConfig.appName,
          'p_code': id,
          'p_mac': mac,
        });
        if (res == null) {
          _log('checkIn: RPC indisponível (rode o 001_schema.sql no Supabase)');
          return const ActivationResult(status: ActivationStatus.notFound);
        }
        if (res['ok'] != true) {
          if (res['error'] == 'conflict' &&
              regenerateDeviceId != null &&
              attempt < _maxCreateAttempts) {
            id = regenerateDeviceId();
            _log(
              'checkIn: deviceId collision, retrying with $id (attempt ${attempt + 1})',
            );
            continue;
          }
          _log('checkIn: rpc error=${res['error']}');
          return const ActivationResult(status: ActivationStatus.notFound);
        }
        return _resultFromRpc(res);
      }
      return const ActivationResult(status: ActivationStatus.notFound);
    } catch (e) {
      _log('checkIn: error=$e');
      return const ActivationResult(status: ActivationStatus.notFound);
    }
  }

  /// Chama um RPC do Supabase e devolve o objeto JSON (ou null em erro).
  Future<Map<String, dynamic>?> _rpc(
    String name,
    Map<String, dynamic> body,
  ) async {
    final res = await _dio.post(
      '$_base/rest/v1/rpc/$name',
      options: Options(headers: _headers),
      data: body,
    );
    _log('rpc $name: status=${res.statusCode}, data=${res.data}');
    if ((res.statusCode ?? 500) >= 400) return null;
    if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
    return null;
  }

  /// Converte a resposta JSON dos RPCs (`device_checkin`/`device_status`).
  ActivationResult _resultFromRpc(Map<String, dynamic> row) {
    final status = (row['status'] as String? ?? 'pending').toLowerCase();
    final appName = row['app_name'] as String? ?? '';
    if (status == 'approved') {
      final rawList = row['list_data'];
      _log('rpc: list_data=$rawList');
      return ActivationResult(
        status: ActivationStatus.approved,
        listData: rawList is Map
            ? ActivationListData.fromJson(Map<String, dynamic>.from(rawList))
            : null,
        approvedAt: row['approved_at'] as String?,
        appName: appName,
      );
    }
    if (status == 'blocked') {
      _log('rpc: blocked');
      return ActivationResult(
        status: ActivationStatus.blocked,
        appName: appName,
      );
    }
    if (status == 'rejected') {
      _log('rpc: rejected');
      return ActivationResult(
        status: ActivationStatus.rejected,
        appName: appName,
      );
    }
    if (status == 'not_found') {
      _log('rpc: not_found');
      return const ActivationResult(status: ActivationStatus.notFound);
    }
    _log('rpc: pending');
    return ActivationResult(status: ActivationStatus.pending, appName: appName);
  }

  /// Busca o estado atual da chave para polling (RPC `device_status`).
  Future<ActivationResult> fetchStatus(String deviceId) async {
    if (!isEnabled) return const ActivationResult.disabled();
    _log('fetchStatus: deviceId=$deviceId');
    try {
      final res = await _rpc('device_status', {
        'p_app': ActivationConfig.appName,
        'p_code': deviceId,
      });
      if (res == null || res['ok'] != true) {
        _log('fetchStatus: rpc indisponível ou erro');
        return const ActivationResult(
          status: ActivationStatus.notFound,
          appName: '',
        );
      }
      return _resultFromRpc(res);
    } catch (e) {
      _log('fetchStatus: error=$e');
      return const ActivationResult(
        status: ActivationStatus.notFound,
        appName: '',
      );
    }
  }

  /// Busca todos os dispositivos (para admin).
  /// Retorna lista de mapas com todos os campos da tabela.
  Future<List<Map<String, dynamic>>> fetchAllDevices() async {
    if (!isEnabled) return [];
    _log('fetchAllDevices:');
    try {
      final res = await _dio.get(
        '$_base/rest/v1/devices',
        options: Options(headers: _headers),
        queryParameters: {
          'select':
              'device_id,mac,app_name,status,list_data,approved_at,created_at',
          'order': 'created_at.desc',
          'limit': '100',
        },
      );
      _log(
        'fetchAllDevices: GET status=${res.statusCode}, count=${res.data is List ? res.data.length : 0}',
      );
      if (res.data is List) {
        return (res.data as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } catch (e) {
      _log('fetchAllDevices: error=$e');
      return [];
    }
  }

  /// Atualiza status e lista de um dispositivo (para admin aprovar).
  Future<bool> updateDevice({
    required String deviceId,
    required String status,
    required Map<String, dynamic> listData,
  }) async {
    if (!isEnabled) return false;
    _log('updateDevice: deviceId=$deviceId, status=$status');
    try {
      final res = await _dio.patch(
        '$_base/rest/v1/devices',
        options: Options(headers: _headers),
        queryParameters: {'device_id': 'eq.$deviceId'},
        data: {
          'status': status,
          'list_data': listData,
          'approved_at': DateTime.now().toIso8601String(),
        },
      );
      _log('updateDevice: PATCH status=${res.statusCode}');
      return res.statusCode != null && res.statusCode! < 400;
    } catch (e) {
      _log('updateDevice: error=$e');
      return false;
    }
  }

  /// Cria um novo dispositivo com status e lista opcional (para admin adicionar cliente).
  Future<bool> createDevice({
    required String deviceId,
    required String mac,
    required String status,
    Map<String, dynamic>? listData,
  }) async {
    if (!isEnabled) return false;
    _log('createDevice: deviceId=$deviceId, mac=$mac, status=$status');
    try {
      final Map<String, dynamic> data = {
        'device_id': deviceId,
        'mac': mac,
        'app_name': ActivationConfig.appName,
        'status': status,
      };
      if (listData != null) {
        data['list_data'] = listData;
        data['approved_at'] = DateTime.now().toIso8601String();
      }
      final res = await _dio.post(
        '$_base/rest/v1/devices',
        options: Options(headers: _headers),
        data: data,
      );
      _log('createDevice: POST status=${res.statusCode}, data=${res.data}');
      return res.statusCode != null && res.statusCode! < 400;
    } catch (e) {
      _log('createDevice: error=$e');
      return false;
    }
  }

  /// Exclui um dispositivo (para admin remover aparelhos fora de uso).
  /// Retorna true se o DELETE afetou ao menos 1 linha.
  Future<bool> deleteDevice({required String deviceId}) async {
    if (!isEnabled) return false;
    _log('deleteDevice: deviceId=$deviceId');
    try {
      final res = await _dio.delete(
        '$_base/rest/v1/devices',
        options: Options(
          headers: {..._headers, 'Prefer': 'return=representation'},
        ),
        queryParameters: {'device_id': 'eq.$deviceId'},
      );
      _log('deleteDevice: DELETE status=${res.statusCode}, data=${res.data}');
      if (res.data is List) return (res.data as List).isNotEmpty;
      return res.statusCode != null && res.statusCode! < 400;
    } catch (e) {
      _log('deleteDevice: error=$e');
      return false;
    }
  }

  /// Apaga apenas a lista vinculada (mantém o aparelho cadastrado).
  /// Permite limpar a lista atual para inserir outra em seguida.
  Future<bool> clearDeviceList({required String deviceId}) async {
    if (!isEnabled) return false;
    _log('clearDeviceList: deviceId=$deviceId');
    try {
      final res = await _dio.patch(
        '$_base/rest/v1/devices',
        options: Options(headers: _headers),
        queryParameters: {'device_id': 'eq.$deviceId'},
        data: {'list_data': null},
      );
      _log('clearDeviceList: PATCH status=${res.statusCode}');
      return res.statusCode != null && res.statusCode! < 400;
    } catch (e) {
      _log('clearDeviceList: error=$e');
      return false;
    }
  }

  /// Busca playlists cadastradas no dashboard (tabela playlists).
  Future<List<Map<String, dynamic>>> fetchPlaylists() async {
    if (!isEnabled) return [];
    _log('fetchPlaylists:');
    try {
      final res = await _dio.get(
        '$_base/rest/v1/playlists',
        options: Options(headers: _headers),
        queryParameters: {
          'select': 'id,name,type,url,server_url,username,password',
          'order': 'name.asc',
        },
      );
      _log(
        'fetchPlaylists: GET status=${res.statusCode}, count=${res.data is List ? res.data.length : 0}',
      );
      if (res.data is List) {
        return (res.data as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } catch (e) {
      _log('fetchPlaylists: error=$e');
      return [];
    }
  }
}

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

    ActivationService({ Dio? dio })
        : _dio = dio ??
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

    String get _base => ActivationConfig.supabaseUrl.replaceAll(RegExp(r'/$'), '');

    void _log(String msg) {
      if (debugLog) debugPrint('[ActivationService] $msg');
    }

  /// Registra este aparelho como pendente. Idempotente e seguro:
  /// se a chave já existe (inclusive aprovada), não altera nada.
  /// Se existe com outro app_name, atualiza o app_name mantendo o status.
  ///
  /// [regenerateDeviceId] é chamado quando o `device_id` colide com outro
  /// aparelho já cadastrado (`409 duplicate key`). Como os formatos de chave
  /// são disjuntos (McPlayer numérico x NexPlay com letra), isso não deveria
  /// acontecer — é só uma rede de segurança. Tenta no máximo
  /// [_maxCreateAttempts] chaves.
  Future<ActivationResult> checkIn({
    required String deviceId,
    required String mac,
    String Function()? regenerateDeviceId,
  }) async {
    if (!isEnabled) return const ActivationResult.disabled();
    _log('checkIn: deviceId=$deviceId, mac=$mac, appName=${ActivationConfig.appName}');
    _log('base URL: $_base');
    _log('headers: ${_headers.keys.join(', ')}');
    var id = deviceId;
    try {
      for (var attempt = 1; attempt <= _maxCreateAttempts; attempt++) {
        final current = await fetchStatus(id);
        _log('checkIn: current status=${current.status}, appName=${current.appName}');

        // Se dispositivo não existe, cria novo
        if (current.status == ActivationStatus.notFound) {
          final statusCode = await _createDevice(id, mac);
          if (statusCode != null && statusCode < 400) {
            return const ActivationResult(status: ActivationStatus.pending);
          }
          // Colisão de chave (409): sorteia outra chave e tenta de novo.
          if (statusCode == 409 &&
              regenerateDeviceId != null &&
              attempt < _maxCreateAttempts) {
            id = regenerateDeviceId();
            _log('checkIn: deviceId collision, retrying with $id (attempt ${attempt + 1})');
            continue;
          }
          return const ActivationResult(status: ActivationStatus.notFound);
        }

        // Se dispositivo existe mas com outro app_name, atualiza
        if (current.appName != ActivationConfig.appName) {
          _log('checkIn: appName mismatch (existing=${current.appName}, current=${ActivationConfig.appName}), updating...');
          return await _updateAppName(id, mac);
        }

        // Mesmo app_name: retorna status atual (não sobrescreve aprovação)
        return current;
      }
      return const ActivationResult(status: ActivationStatus.notFound);
    } catch (e) {
      _log('checkIn: error=$e');
      return const ActivationResult(status: ActivationStatus.notFound);
    }
  }

  /// Cria o aparelho como `pending`.
  /// Retorna o HTTP status (ex.: 201 criado, 409 chave já usada por outro
  /// aparelho) ou `null` em caso de erro de rede.
  Future<int?> _createDevice(String deviceId, String mac) async {
    final res = await _dio.post(
      '$_base/rest/v1/devices',
      options: Options(headers: _headers),
      data: {
        'device_id': deviceId,
        'mac': mac,
        'app_name': ActivationConfig.appName,
        'status': 'pending',
      },
    );
    _log('checkIn: POST status=${res.statusCode}, data=${res.data}');
    return res.statusCode;
  }

  Future<ActivationResult> _updateAppName(String deviceId, String mac) async {
    final res = await _dio.patch(
      '$_base/rest/v1/devices',
      options: Options(headers: _headers),
      queryParameters: {'device_id': 'eq.$deviceId'},
      data: {
        'app_name': ActivationConfig.appName,
        'mac': mac,
      },
    );
    _log('checkIn: PATCH app_name status=${res.statusCode}');
    if ((res.statusCode ?? 500) >= 400) {
      _log('checkIn: PATCH HTTP error ${res.statusCode}');
      return const ActivationResult(status: ActivationStatus.notFound);
    }
    // Re-fetch para pegar status atualizado
    return await fetchStatus(deviceId);
  }

  /// Busca o estado atual da chave para polling.
  Future<ActivationResult> fetchStatus(String deviceId) async {
    if (!isEnabled) return const ActivationResult.disabled();
    _log('fetchStatus: deviceId=$deviceId');
    try {
      final res = await _dio.get(
        '$_base/rest/v1/devices',
        options: Options(headers: _headers),
        queryParameters: {
          'device_id': 'eq.$deviceId',
          'select': 'status,list_data,approved_at,app_name',
        },
      );
      _log('fetchStatus: GET status=${res.statusCode}, data=${res.data}');
      final data = res.data;
      if (data is! List || data.isEmpty) {
        _log('fetchStatus: no data found');
        return const ActivationResult(status: ActivationStatus.notFound, appName: '');
      }
      final row = Map<String, dynamic>.from(data.first as Map);
      final status = (row['status'] as String? ?? 'pending').toLowerCase();
      final appName = row['app_name'] as String? ?? '';
      _log('fetchStatus: row status=$status, appName=$appName, approved_at=${row['approved_at']}');
      if (status == 'approved') {
        final rawList = row['list_data'];
        _log('fetchStatus: list_data=$rawList');
        return ActivationResult(
          status: ActivationStatus.approved,
          listData: rawList is Map
              ? ActivationListData.fromJson(
                  Map<String, dynamic>.from(rawList))
              : null,
          approvedAt: row['approved_at'] as String?,
          appName: appName,
        );
      }
      if (status == 'rejected') {
        _log('fetchStatus: rejected');
        return ActivationResult(status: ActivationStatus.rejected, appName: appName);
      }
      _log('fetchStatus: pending');
      return ActivationResult(status: ActivationStatus.pending, appName: appName);
    } catch (e) {
      _log('fetchStatus: error=$e');
      return const ActivationResult(status: ActivationStatus.notFound, appName: '');
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
          'select': 'device_id,mac,app_name,status,list_data,approved_at,created_at',
          'order': 'created_at.desc',
          'limit': '100',
        },
      );
      _log('fetchAllDevices: GET status=${res.statusCode}, count=${res.data is List ? res.data.length : 0}');
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
        options: Options(headers: {
          ..._headers,
          'Prefer': 'return=representation',
        }),
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
      _log('fetchPlaylists: GET status=${res.statusCode}, count=${res.data is List ? res.data.length : 0}');
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

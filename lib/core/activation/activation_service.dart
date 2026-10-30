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

  /// Último erro de comunicação (HTTP ou rede). A tela de ativação usa isso
  /// para mostrar no próprio aparelho por que o check-in não chegou ao painel
  /// — inclusive o código HTTP (ex.: 404 quando a URL/projeto está errado).
  String? _lastError;
  int? _lastHttpStatus;

  String? get lastError => _lastError;
  int? get lastHttpStatus => _lastHttpStatus;

  void _setError(String? message, [int? status]) {
    _lastError = message;
    _lastHttpStatus = status;
  }

  void _clearError() => _setError(null, null);

  /// Mensagem curta para exibir na TV (sem stack trace do Dio).
  String _describeNetworkError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return 'Tempo de conexao esgotado com o painel';
      case DioExceptionType.connectionError:
        return 'Sem conexao com o painel (verifique a internet/TV)';
      case DioExceptionType.badResponse:
        return 'Painel respondeu HTTP ${e.response?.statusCode}';
      case DioExceptionType.badCertificate:
        return 'Certificado do painel invalido (data/hora da TV)';
      case DioExceptionType.cancel:
        return 'Conexao cancelada';
      case DioExceptionType.unknown:
        return 'Falha de rede: ${e.message ?? e.error ?? 'desconhecida'}';
    }
  }

  /// Executa o RPC com novas tentativas apenas quando vale a pena:
  /// sem resposta/5xx (rede instavel, comum na Fire TV logo ao ligar).
  /// Erros 4xx (404 = função/URL errada) são definitivos e não repetem.
  Future<Map<String, dynamic>?> _rpcWithRetry(
    String name,
    Map<String, dynamic> body, {
    int attempts = 3,
  }) async {
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final res = await _rpc(name, body);
        if (res != null) return res;
        final status = _lastHttpStatus;
        if (status != null && status >= 400 && status < 500) return null;
      } on DioException catch (e) {
        _setError(_describeNetworkError(e), e.response?.statusCode);
        if (e.response?.statusCode != null &&
            e.response!.statusCode! >= 400 &&
            e.response!.statusCode! < 500) {
          return null;
        }
      }
      if (attempt < attempts) {
        _log('rpc $name: nova tentativa ${attempt + 1}/$attempts em ${attempt * 2}s');
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
    return null;
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
    _clearError();
    var id = deviceId;
    try {
      for (var attempt = 1; attempt <= _maxCreateAttempts; attempt++) {
        final res = await _rpcWithRetry('device_checkin', {
          'p_app': ActivationConfig.appName,
          'p_code': id,
          'p_mac': mac,
        });
        if (res == null) {
          _log('checkIn: RPC indisponível (rode o 001_schema.sql no Supabase)');
          return ActivationResult(
            status: ActivationStatus.notFound,
            message: _lastError,
          );
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
          final hint = res['hint']?.toString();
          _setError(
            'check-in recusado: ${res['error'] ?? 'erro desconhecido'}'
            '${hint != null && hint.isNotEmpty ? ' ($hint)' : ''}',
          );
          _log('checkIn: rpc error=${res['error']}');
          return ActivationResult(
            status: ActivationStatus.notFound,
            message: _lastError,
          );
        }
        _clearError();
        return _resultFromRpc(res);
      }
      return ActivationResult(
        status: ActivationStatus.notFound,
        message: _lastError ?? 'Nao foi possivel registrar a chave $id',
      );
    } catch (e) {
      _log('checkIn: error=$e');
      _setError(e is DioException ? _describeNetworkError(e) : e.toString());
      return ActivationResult(
        status: ActivationStatus.notFound,
        message: _lastError,
      );
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
    if ((res.statusCode ?? 500) >= 400) {
      String? detail;
      final data = res.data;
      if (data is Map) {
        detail =
            (data['message'] ?? data['hint'] ?? data['error_description'])
                ?.toString();
      }
      _setError(
        'HTTP ${res.statusCode}${detail != null ? ': $detail' : ''}',
        res.statusCode,
      );
      return null;
    }
    _clearError();
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
        return ActivationResult(
          status: ActivationStatus.notFound,
          appName: '',
          message: _lastError,
        );
      }
      _clearError();
      return _resultFromRpc(res);
    } catch (e) {
      _log('fetchStatus: error=$e');
      _setError(e is DioException ? _describeNetworkError(e) : e.toString());
      return ActivationResult(
        status: ActivationStatus.notFound,
        appName: '',
        message: _lastError,
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

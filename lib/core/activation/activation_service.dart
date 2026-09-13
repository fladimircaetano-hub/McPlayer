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

  Map<String, String> get _headers => {
        'apikey': ActivationConfig.supabaseAnonKey,
        'Authorization': 'Bearer ${ActivationConfig.supabaseAnonKey}',
        'Content-Type': 'application/json',
      };

  String get _base => ActivationConfig.supabaseUrl.replaceAll(RegExp(r'/$'), '');

  /// Registra este aparelho como pendente. Idempotente e seguro:
  /// se a chave já existe (inclusive aprovada), não altera nada.
  Future<ActivationResult> checkIn({
    required String deviceId,
    required String mac,
  }) async {
    if (!isEnabled) return const ActivationResult.disabled();
    try {
      final current = await fetchStatus(deviceId);
      if (current.status != ActivationStatus.notFound) return current;

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
      if ((res.statusCode ?? 500) >= 400) {
        return const ActivationResult(status: ActivationStatus.notFound);
      }
      return const ActivationResult(status: ActivationStatus.pending);
    } catch (_) {
      // Sem rede / backend fora: o app segue no modo manual.
      return const ActivationResult(status: ActivationStatus.notFound);
    }
  }

  /// Busca o estado atual da chave para polling.
  Future<ActivationResult> fetchStatus(String deviceId) async {
    if (!isEnabled) return const ActivationResult.disabled();
    try {
      final res = await _dio.get(
        '$_base/rest/v1/devices',
        options: Options(headers: _headers),
        queryParameters: {
          'device_id': 'eq.$deviceId',
          'select': 'status,list_data,approved_at',
        },
      );
      final data = res.data;
      if (data is! List || data.isEmpty) {
        return const ActivationResult(status: ActivationStatus.notFound);
      }
      final row = Map<String, dynamic>.from(data.first as Map);
      final status = (row['status'] as String? ?? 'pending').toLowerCase();
      if (status == 'approved') {
        final rawList = row['list_data'];
        return ActivationResult(
          status: ActivationStatus.approved,
          listData: rawList is Map
              ? ActivationListData.fromJson(
                  Map<String, dynamic>.from(rawList))
              : null,
          approvedAt: row['approved_at'] as String?,
        );
      }
      if (status == 'rejected') {
        return const ActivationResult(status: ActivationStatus.rejected);
      }
      return const ActivationResult(status: ActivationStatus.pending);
    } catch (_) {
      return const ActivationResult(status: ActivationStatus.notFound);
    }
  }
}

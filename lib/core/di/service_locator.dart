import 'package:dio/dio.dart';
import 'package:meta/meta.dart';
import '../activation/activation_config.dart';
import '../activation/activation_service.dart';
import '../network/api_client.dart';
import '../storage/storage_service.dart';
import '../../data/datasources/xtream_api.dart';

/// Service Locator simples para instâncias singleton compartilhadas.
///
/// Evita criar múltiplas instâncias de Dio/ActivationService que
/// gastam recursos e não compartilham connection pools.
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  Dio? _sharedDio;
  ActivationService? _activationService;
  ApiClient? _apiClient;
  XtreamApi? _xtreamApi;
  Dio get sharedDio {
    _sharedDio ??= Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 30),
        headers: {
          'User-Agent': 'IPTVSmarters/1.0.0 (Linux; Android 12; Mobile)',
          'Accept': '*/*',
        },
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    return _sharedDio!;
  }

  /// ApiClient singleton usando o Dio compartilhado
  ApiClient get apiClient {
    _apiClient ??= ApiClient(sharedDio);
    return _apiClient!;
  }

  /// XtreamApi singleton usando o Dio compartilhado
  XtreamApi get xtreamApi {
    _xtreamApi ??= XtreamApi(sharedDio);
    return _xtreamApi!;
  }

  /// ActivationService singleton - só cria se ativação estiver habilitada
  ActivationService? get activationService {
    if (!ActivationConfig.isEnabled) return null;
    _activationService ??= ActivationService(dio: sharedDio);
    return _activationService;
  }

  /// StorageService - deve ser inicializado via init() antes do uso
  StorageService? _storage;
  StorageService get storage {
    if (_storage == null) {
      throw StateError('StorageService não inicializado. Chame ServiceLocator.initStorage() primeiro.');
    }
    return _storage!;
  }

  /// Inicializa o StorageService (deve ser chamado no main antes de runApp)
  Future<void> initStorage() async {
    _storage ??= await StorageService.init();
  }

  /// Reset para testes
  @visibleForTesting
  void reset() {
    _sharedDio?.close();
    _sharedDio = null;
    _activationService = null;
    _apiClient = null;
    _xtreamApi = null;
    _storage = null;
  }
}

/// Instância global conveniente
final sl = ServiceLocator();
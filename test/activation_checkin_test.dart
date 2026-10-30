import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcplayer/core/activation/activation_models.dart';
import 'package:mcplayer/core/activation/activation_service.dart';

/// Adapter falso: devolve respostas pré-programadas sem tocar na rede.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responses);

  final List<({int status, Object body})> responses;
  int calls = 0;
  final List<Map<String, dynamic>> requestBodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.data is Map) {
      requestBodies.add(Map<String, dynamic>.from(options.data as Map));
    }
    final r = responses[calls.clamp(0, responses.length - 1)];
    calls++;
    return ResponseBody.fromString(
      jsonEncode(r.body),
      r.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ActivationService _service(_FakeAdapter adapter) {
  final dio = Dio(
    BaseOptions(validateStatus: (s) => s != null && s < 500),
  )..httpClientAdapter = adapter;
  return ActivationService(dio: dio);
}

void main() {
  test('404 no device_checkin vira erro visível e não repete (4xx)', () async {
    final adapter = _FakeAdapter([
      (
        status: 404,
        body: {
          'code': 'PGRST202',
          'message':
              'Could not find the function public.device_checkin(p_app, p_code, p_mac) in the schema cache',
        },
      ),
    ]);
    final service = _service(adapter);

    final result = await service.checkIn(
      deviceId: '689220',
      mac: '02:00:00:00:00:01',
    );

    expect(result.status, ActivationStatus.notFound);
    expect(service.lastHttpStatus, 404);
    expect(result.message, contains('404'));
    expect(result.message, contains('device_checkin'));
    expect(adapter.calls, 1, reason: '4xx é definitivo: não deve repetir');
    expect(adapter.requestBodies.single['p_code'], '689220');
    expect(adapter.requestBodies.single['p_app'], 'McPlayer');
  });

  test('check-in aprovado devolve a lista Xtream vinculada', () async {
    final adapter = _FakeAdapter([
      (
        status: 200,
        body: {
          'ok': true,
          'status': 'approved',
          'app_name': 'McPlayer',
          'device_id': '689220',
          'list_data': {
            'type': 'xtream',
            'server_url': 'http://servidor.example',
            'username': 'usuario',
            'password': 'senha',
          },
        },
      ),
    ]);
    final service = _service(adapter);

    final result = await service.checkIn(
      deviceId: '689220',
      mac: '02:00:00:00:00:01',
    );

    expect(result.status, ActivationStatus.approved);
    expect(result.listData, isNotNull);
    expect(result.listData!.isXtream, isTrue);
    expect(result.listData!.serverUrl, 'http://servidor.example');
    expect(service.lastError, isNull);
  });

  test('device_status not_found não gera erro falso no banner', () async {
    final adapter = _FakeAdapter([
      (
        status: 200,
        body: {'ok': true, 'status': 'not_found', 'app_name': 'McPlayer'},
      ),
    ]);
    final service = _service(adapter);

    final result = await service.fetchStatus('689220');

    expect(result.status, ActivationStatus.notFound);
    expect(result.message, isNull);
    expect(service.lastError, isNull);
  });
}

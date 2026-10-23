import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mcplayer/core/activation/activation_config.dart';
import 'package:mcplayer/core/storage/storage_service.dart';

/// Invariantes da chave do aparelho (`device_id`).
///
/// No schema novo a chave é única DENTRO do app (`app_name, device_id`), mas
/// os formatos gerados continuam disjuntos: McPlayer só dígitos, NexPlay sempre
/// com uma letra. Isso evita que o mesmo aparelho seja confundido ao trocar de
/// app e mantém a rede de segurança contra colisão.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('McPlayer gera chave de 6 dígitos e mantém entre chamadas', () async {
    final storage = await StorageService.init();
    // Build padrão = McPlayer (só dígitos).
    expect(ActivationConfig.idIsAlphanumeric, isFalse);

    final id = storage.getDeviceId();
    expect(RegExp(r'^\d{6}$').hasMatch(id), isTrue, reason: 'id="$id"');
    expect(storage.getDeviceId(), id, reason: 'deve persistir a mesma chave');
  });

  test('newDeviceId troca a chave e persiste a nova', () async {
    final storage = await StorageService.init();
    final first = storage.getDeviceId();
    final second = storage.newDeviceId();

    expect(second, isNot(first));
    expect(storage.getDeviceId(), second);
  });

  test('MAC virtual no padrão 02:xx:xx:xx:xx:xx e estável', () async {
    final storage = await StorageService.init();
    final mac = storage.getDeviceMac();

    expect(RegExp(r'^02(:[0-9A-F]{2}){5}$').hasMatch(mac), isTrue,
        reason: 'mac="$mac"');
    expect(storage.getDeviceMac(), mac);
  });

  test('formatos McPlayer (numérico) e NexPlay (com letra) são disjuntos', () {
    final mcPlayer = RegExp(r'^\d{6}$');
    final nexPlay = RegExp(r'^[A-Z][A-Z0-9]{5}$');

    // Nenhuma chave pode casar com os DOIS formatos ao mesmo tempo.
    const samples = ['123456', '000000', '999999', 'A1B2C3', 'K7F2Q9', '1ABCDE', 'ABCDEF'];
    for (final s in samples) {
      expect(mcPlayer.hasMatch(s) && nexPlay.hasMatch(s), isFalse,
          reason: '"$s" casou com os dois formatos');
    }

    expect(mcPlayer.hasMatch('123456'), isTrue);
    expect(nexPlay.hasMatch('K7F2Q9'), isTrue);
    // O NexPlay nunca pode ser só dígitos (senão colidiria com o McPlayer).
    expect(nexPlay.hasMatch('123456'), isFalse);
  });
}

# mcplayer

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Build e publicação (leia antes de gerar APK)

A ativação remota (dashboard Supabase) já vem **ligada por padrão**: a URL e a
anon key ficam em `lib/core/activation/activation_config.dart` (as mesmas de
`dashboard/js/config.js`). Ou seja, `flutter build apk` sem nenhum
`--dart-define` já gera um APK que aparece no dashboard.

Para gerar e **verificar** os dois APKs (arm64/arm32):

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_release.ps1
```

O script usa a URL/chave do dashboard, compila, e reprova o APK se:

- o ZIP estiver corrompido/truncado (upload pela metade);
- `SUPABASE_URL`/`SUPABASE_ANON_KEY` não estiverem embutidas no `libapp.so`
  (era a causa do aviso "Ativação remota DESLIGADA" na TV);
- a assinatura ou o `zipalign` estiverem inválidos.

Para conferir um APK já publicado (baixado): `-ApkDir <pasta>` com os nomes
`app-arm64-v8a-release.apk` / `app-armeabi-v7a-release.apk`.

APKs assinados com a chave de **debug** servem para sideload, não para Play Store.


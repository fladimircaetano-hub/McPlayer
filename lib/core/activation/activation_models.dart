// Modelos da ativação remota. Espelham `DeviceListData` do Dashboard
// (`Dashboard Mc Player/src/types/iptv.ts`).

enum ActivationStatus {
  pending,
  approved,
  rejected,
  blocked,
  notFound,
  disabled,
}

class ActivationListData {
  final String type; // 'm3u' | 'm3u8' | 'xtream'
  final String? url;
  final String? serverUrl;
  final String? username;
  final String? password;

  const ActivationListData({
    required this.type,
    this.url,
    this.serverUrl,
    this.username,
    this.password,
  });

  bool get isM3u => type == 'm3u' || type == 'm3u8';
  bool get isXtream => type == 'xtream';

  factory ActivationListData.fromJson(Map<String, dynamic> json) {
    return ActivationListData(
      type: (json['type'] as String? ?? 'm3u').toLowerCase(),
      url: json['url'] as String?,
      serverUrl: (json['serverUrl'] ?? json['server_url']) as String?,
      username: (json['username'] ?? json['user']) as String?,
      password: (json['password'] ?? json['pass']) as String?,
    );
  }
}

class ActivationResult {
  final ActivationStatus status;
  final ActivationListData? listData;
  final String? approvedAt;
  final String appName;

  /// Motivo da falha quando [status] é [ActivationStatus.notFound]
  /// (ex.: "HTTP 404: Could not find the function public.device_checkin").
  /// Serve para mostrar no aparelho por que o check-in não chegou ao painel.
  final String? message;

  const ActivationResult({
    required this.status,
    this.listData,
    this.approvedAt,
    this.appName = '',
    this.message,
  });

  const ActivationResult.disabled()
      : status = ActivationStatus.disabled,
        listData = null,
        approvedAt = null,
        appName = '',
        message = null;
}

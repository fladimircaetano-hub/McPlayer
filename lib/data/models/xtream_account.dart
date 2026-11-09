class XtreamAccount {
  final String serverUrl;
  final String username;
  final String password;
  final String? status;
  final String? expDate;
  final String? message;

  XtreamAccount({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.status,
    this.expDate,
    this.message,
  });

  /// Vencimento em ISO-8601 para gravar no painel (o Xtream devolve os
  /// segundos em texto). O RPC `xtream_login_register` espera timestamptz.
  String? get expDateIso {
    final seconds = int.tryParse(expDate ?? '');
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    ).toIso8601String();
  }

  Map<String, dynamic> toJson() {
    return {
      'serverUrl': serverUrl,
      'username': username,
      'password': password,
      'status': status,
      'expDate': expDate,
      'message': message,
    };
  }

  factory XtreamAccount.fromJson(Map<String, dynamic> json) {
    return XtreamAccount(
      serverUrl: json['serverUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      status: json['status'] as String?,
      expDate: json['expDate'] as String?,
      message: json['message'] as String?,
    );
  }
}

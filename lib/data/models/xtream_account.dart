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

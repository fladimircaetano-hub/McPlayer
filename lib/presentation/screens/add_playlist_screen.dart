import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../controllers/iptv_controller.dart';
import '../widgets/tv_focusable.dart';
import 'home_screen.dart';

/// Tela "Add playlist" (só Xtream Codes): Code/Username/Password,
/// Cancel/Ok, ajuda do site + QR do WhatsApp, rodapé do aparelho.
/// Listas M3U entram via Dashboard (ativação remota silenciosa).
class AddPlaylistScreen extends StatefulWidget {
  final IptvController controller;

  const AddPlaylistScreen({super.key, required this.controller});

  @override
  State<AddPlaylistScreen> createState() => _AddPlaylistScreenState();
}

class _AddPlaylistScreenState extends State<AddPlaylistScreen> {
  final _codeCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _sending = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.redAccent.shade700 : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _submit() async {
    // Guarda contra duplo toque / Enter repetido no D-pad: loginXtream
    // concorrente duplica EPG em background e navegação.
    if (_sending) return;
    final code = _codeCtrl.text.trim();
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (code.isEmpty || user.isEmpty || pass.isEmpty) {
      _snack('Preencha Code, Username e Password');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    final ok = await widget.controller.loginXtream(
      serverUrl: code,
      username: user,
      password: pass,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => HomeScreen(controller: widget.controller)),
        (r) => false,
      );
    } else if (widget.controller.errorMessage != null) {
      _snack(widget.controller.errorMessage!, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = widget.controller.storageService;
    final deviceId = storage.getDeviceId();
    final mac = storage.getDeviceMac();
    final isTv = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: isTv ? 120 : 24, vertical: 24),
          child: Column(
            children: [
              const Text('Add playlist',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 30)),
              const SizedBox(height: 28),
              _field(_codeCtrl, 'Code', light: true),
              const SizedBox(height: 12),
              _field(_userCtrl, 'Username'),
              const SizedBox(height: 12),
              _field(_passCtrl, 'Password',
                  obscure: _obscure,
                  onToggleObscure: () =>
                      setState(() => _obscure = !_obscure)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _pillButton('Cancel', () => Navigator.of(context).pop()),
                  const SizedBox(width: 16),
                  _pillButton('Ok', _submit,
                      primary: true, loading: _sending),
                ],
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'To add playlist from our website visit:',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                        Text('https://mcplayer.app',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        Text('or Scan the QR code in the right',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.white,
                    child: QrImageView(
                      data: 'MAC:$mac|KEY:$deviceId',
                      size: 120,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text('Web Page: https://mcplayer.app',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                  Text('Device key: $deviceId',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text('Mac Address: $mac',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String hint, {
    bool light = false,
    bool obscure = false,
    VoidCallback? onToggleObscure,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: TextStyle(color: light ? Colors.black54 : Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: light ? Colors.black45 : Colors.white70),
        filled: true,
        fillColor: light ? Colors.white : AppColors.surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        suffixIcon: onToggleObscure == null
            ? null
            : IconButton(
                icon: Icon(
                    obscure ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white70),
                onPressed: onToggleObscure,
              ),
      ),
    );
  }

  Widget _pillButton(String label, VoidCallback onTap,
      {bool loading = false, bool primary = false}) {
    return TvFocusable(
      borderRadius: BorderRadius.circular(20),
      onPressed: loading ? () {} : onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 36, vertical: 10),
        decoration: BoxDecoration(
          color: primary ? AppColors.primary : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: primary ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w600)),
      ),
    );
  }
}

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../controllers/iptv_controller.dart';
import '../widgets/tv_focusable.dart';
import 'home_screen.dart';

/// Tela "Add playlist": 2 modos (Xtream Codes | Lista M3U),
/// ajuda do site + QR, rodapé do aparelho.
class AddPlaylistScreen extends StatefulWidget {
  final IptvController controller;

  const AddPlaylistScreen({super.key, required this.controller});

  @override
  State<AddPlaylistScreen> createState() => _AddPlaylistScreenState();
}

class _AddPlaylistScreenState extends State<AddPlaylistScreen> {
  bool _isXtream = true;

  // Xtream
  final _codeCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  // M3U
  final _urlCtrl = TextEditingController();

  bool _sending = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => HomeScreen(controller: widget.controller)),
      (r) => false,
    );
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

  Future<void> _submitXtream() async {
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
      _goHome();
    } else if (widget.controller.errorMessage != null) {
      _snack(widget.controller.errorMessage!, error: true);
    }
  }

  Future<void> _submitM3uUrl() async {
    if (_sending) return;
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _snack('Informe a URL da lista .m3u ou .m3u8');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        !uri.host.contains('.')) {
      _snack('URL inválida. Use http(s)://seu-servidor/playlist.m3u8');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    final ok = await widget.controller.loadFromM3uUrl(url);
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      _goHome();
    } else if (widget.controller.errorMessage != null) {
      _snack(widget.controller.errorMessage!, error: true);
    }
  }

  Future<void> _pickM3uFile() async {
    if (_sending) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m3u', 'm3u8', 'txt'],
      );
      final path = result?.files.single.path;
      if (path == null) return;
      setState(() => _sending = true);
      final ok = await widget.controller.loadFromLocalFile(path);
      if (!mounted) return;
      setState(() => _sending = false);
      if (ok) {
        _goHome();
      } else if (widget.controller.errorMessage != null) {
        _snack(widget.controller.errorMessage!, error: true);
      }
    } catch (e) {
      _snack('Erro ao selecionar arquivo: ${e.toString()}', error: true);
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
              const SizedBox(height: 16),
              _modeToggle(),
              const SizedBox(height: 16),
              if (_isXtream) ...[
                _field(_codeCtrl, 'Code', light: true),
                const SizedBox(height: 12),
                _field(_userCtrl, 'Username'),
                const SizedBox(height: 12),
                _field(_passCtrl, 'Password',
                    obscure: _obscure,
                    onToggleObscure: () =>
                        setState(() => _obscure = !_obscure)),
              ] else ...[
                _field(_urlCtrl, 'http://servidor.com/playlist.m3u8'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _pillButton('Carregar URL', _submitM3uUrl,
                          primary: true, loading: _sending),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _pillButton(
                          'Arquivo Local', _pickM3uFile,
                          loading: _sending),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _pillButton('Cancel', () => Navigator.of(context).pop()),
                  const SizedBox(width: 16),
                  if (_isXtream)
                    _pillButton('Ok', _submitXtream,
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

  /// Alternador Xtream | M3U (segmentado simples, focável na TV).
  Widget _modeToggle() {
    Widget seg(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        child: TvFocusable(
          borderRadius: BorderRadius.circular(10),
          onPressed: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: selected ? Colors.black : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          seg('Xtream Codes', _isXtream,
              () => setState(() => _isXtream = true)),
          seg('Lista M3U', !_isXtream,
              () => setState(() => _isXtream = false)),
        ],
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

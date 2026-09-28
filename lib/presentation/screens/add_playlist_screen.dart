import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../controllers/iptv_controller.dart';
import '../widgets/tv_focusable.dart';
import 'home_screen.dart';

/// WhatsApp do suporte (só dígitos, país+DDD). O QR abre a conversa
/// com chave e MAC do aparelho já preenchidos na mensagem.
const _supportWhatsApp = '554391190684';

/// Tela "Add playlist": M3U URL ou Xtream Codes (Code/Username/Password),
/// Cancel/Ok, ajuda do site + QR do WhatsApp, rodapé do aparelho.
class AddPlaylistScreen extends StatefulWidget {
  final IptvController controller;

  const AddPlaylistScreen({super.key, required this.controller});

  @override
  State<AddPlaylistScreen> createState() => _AddPlaylistScreenState();
}

class _AddPlaylistScreenState extends State<AddPlaylistScreen> {
  final _typeCtrl = TextEditingController(text: 'xtream');
  final _codeCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _m3uUrlCtrl = TextEditingController();
  // Nós dedicados: sem eles o D-pad do Fire TV não alcança os campos
  // (TextField puro sem focusNode + sem borda de foco = "não clicável").
  final _codeNode = FocusNode();
  final _userNode = FocusNode();
  final _passNode = FocusNode();
  final _m3uNode = FocusNode();
  bool _obscure = true;
  bool _sending = false;

  @override
  void dispose() {
    _typeCtrl.dispose();
    _codeCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _m3uUrlCtrl.dispose();
    _codeNode.dispose();
    _userNode.dispose();
    _passNode.dispose();
    _m3uNode.dispose();
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

  /// Na TV (Fire Stick) TextField direto não recebe foco do D-pad.
  /// Abre diálogo com campo + teclado; no celular segue TextField direto.
  Future<void> _openTvEditor({
    required String title,
    required TextEditingController target,
    bool obscure = false,
    TextInputType keyboard = TextInputType.text,
  }) async {
    final tmp = TextEditingController(text: target.text);
    var tmpObscure = obscure;
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: TextField(
            controller: tmp,
            autofocus: true,
            obscureText: tmpObscure,
            keyboardType: keyboard,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.primary, width: 2),
              ),
              suffixIcon: obscure
                  ? IconButton(
                      icon: Icon(
                          tmpObscure
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.white70),
                      onPressed: () =>
                          setDlg(() => tmpObscure = !tmpObscure),
                    )
                  : null,
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(tmp.text),
              child: const Text('Salvar',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    tmp.dispose();
    if (saved != null && mounted) {
      setState(() => target.text = saved);
    }
  }

  Future<void> _submit() async {
    if (_sending) return;
    final type = _typeCtrl.text;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);

    bool ok = false;
    if (type == 'm3u') {
      final url = _m3uUrlCtrl.text.trim();
      if (url.isEmpty) {
        _snack('Preencha a URL M3U');
        setState(() => _sending = false);
        return;
      }
      ok = await widget.controller.loadFromM3uUrl(url);
    } else {
      final code = _codeCtrl.text.trim();
      final user = _userCtrl.text.trim();
      final pass = _passCtrl.text.trim();
      if (code.isEmpty || user.isEmpty || pass.isEmpty) {
        _snack('Preencha Code, Username e Password');
        setState(() => _sending = false);
        return;
      }
      ok = await widget.controller.loginXtream(
        serverUrl: code,
        username: user,
        password: pass,
      );
    }

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
    // Layout compacto na TV (Fire Stick 960x540): antes o QR cortava
    // e o rodapé de credenciais ficava fora da tela.
    final hPad = isTv ? 64.0 : 24.0;
    final titleSize = isTv ? 22.0 : 30.0;
    final gap = isTv ? 8.0 : 12.0;
    final qrSize = isTv ? 72.0 : 120.0;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom -
                  48,
            ),
            child: Column(
              children: [
                Text('Add playlist',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: titleSize)),
                SizedBox(height: gap + 4),
                _dropdownField(
                  label: 'Tipo',
                  value: _typeCtrl.text,
                  items: const ['xtream', 'm3u'],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _typeCtrl.text = v);
                    // Leva o foco p/ o 1º campo do tipo novo (Fire TV).
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      if (v == 'xtream') {
                        _codeNode.requestFocus();
                      } else {
                        _m3uNode.requestFocus();
                      }
                    });
                  },
                ),
                SizedBox(height: gap),
                if (_typeCtrl.text == 'xtream') ...[
                  if (isTv) ...[
                      _tvRow(
                          label: 'Code',
                          value: _codeCtrl.text,
                          hint: 'Toque OK p/ digitar o servidor',
                          onTap: () => _openTvEditor(
                                title: 'Code (servidor)',
                                target: _codeCtrl,
                                keyboard: TextInputType.url,
                              )),
                      SizedBox(height: gap),
                      _tvRow(
                          label: 'Username',
                          value: _userCtrl.text,
                          hint: 'Toque OK p/ digitar o usuário',
                          onTap: () => _openTvEditor(
                                title: 'Username',
                                target: _userCtrl,
                                keyboard: TextInputType.text,
                              )),
                      SizedBox(height: gap),
                      _tvRow(
                          label: 'Password',
                          value: _obscure
                              ? '•' * _passCtrl.text.length
                              : _passCtrl.text,
                          hint: 'Toque OK p/ digitar a senha',
                          onTap: () => _openTvEditor(
                                title: 'Password',
                                target: _passCtrl,
                                obscure: true,
                                keyboard: TextInputType.visiblePassword,
                              )),
                    ] else ...[
                    _field(
                      _codeCtrl,
                      'Code (http://servidor:porta)',
                      focusNode: _codeNode,
                      autofocus: true,
                      light: true,
                      keyboardType: TextInputType.url,
                      action: TextInputAction.next,
                      onSubmitted: (_) => _userNode.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                    _field(
                      _userCtrl,
                      'Username',
                      focusNode: _userNode,
                      keyboardType: TextInputType.text,
                      action: TextInputAction.next,
                      onSubmitted: (_) => _passNode.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                    _field(
                        _passCtrl,
                        'Password',
                        focusNode: _passNode,
                        obscure: _obscure,
                        keyboardType: TextInputType.visiblePassword,
                        action: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        onToggleObscure: () =>
                            setState(() => _obscure = !_obscure)),
                  ],
                ] else ...[
                    if (isTv)
                      _tvRow(
                          label: 'URL M3U',
                          value: _m3uUrlCtrl.text,
                          hint: 'Toque OK p/ digitar a URL',
                          onTap: () => _openTvEditor(
                                title: 'URL M3U',
                                target: _m3uUrlCtrl,
                                keyboard: TextInputType.url,
                              ))
                    else
                    _field(
                      _m3uUrlCtrl,
                      'URL M3U (http://.../playlist.m3u)',
                      focusNode: _m3uNode,
                      autofocus: true,
                      keyboardType: TextInputType.url,
                      action: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                    ),
                  ],
                  SizedBox(height: gap + 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _pillButton(
                          'Cancel', () => Navigator.of(context).pop()),
                      const SizedBox(width: 16),
                      _pillButton('Ok', _submit,
                          primary: true, loading: _sending),
                    ],
                  ),
                  SizedBox(height: gap + 4),
              if (isTv)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Ajuda: mcplayer.app',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12)),
                          const SizedBox(height: 2),
                          Text('Chave: $deviceId',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12)),
                          Text('MAC: $mac',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      color: Colors.white,
                      child: QrImageView(
                        data:
                            'https://wa.me/$_supportWhatsApp?text=${Uri.encodeComponent('Olá! Preciso ativar meu McPlayer. Chave: $deviceId | MAC: $mac')}',
                        size: qrSize,
                      ),
                    ),
                  ],
                )
              else
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
                      data:
                          'https://wa.me/$_supportWhatsApp?text=${Uri.encodeComponent('Olá! Preciso ativar meu McPlayer. Chave: $deviceId | MAC: $mac')}',
                      size: 120,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'McPlayer is only a media player. It does not provide lists, channels or content and is not responsible for misuse of the app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 10),
              ),
              const SizedBox(height: 6),
              if (!isTv)
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
              if (!isTv)
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
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String hint, {
    required FocusNode focusNode,
    bool autofocus = false,
    bool light = false,
    bool obscure = false,
    TextInputType? keyboardType,
    TextInputAction? action,
    ValueChanged<String>? onSubmitted,
    VoidCallback? onToggleObscure,
  }) {
    // Borda de foco visível: no Fire TV o foco andava mas era invisível,
    // parecendo "não clicável". O AnimatedBuilder ouve o FocusNode.
    return AnimatedBuilder(
      animation: focusNode,
      builder: (context, _) {
        final hasFocus = focusNode.hasFocus;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasFocus ? AppColors.primary : Colors.transparent,
              width: hasFocus ? 2.5 : 0,
            ),
            boxShadow: hasFocus
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: TextField(
            controller: ctrl,
            focusNode: focusNode,
            autofocus: autofocus,
            obscureText: obscure,
            keyboardType: keyboardType,
            textInputAction: action,
            onSubmitted: onSubmitted,
            autocorrect: false,
            enableSuggestions: false,
            onTapOutside: (_) => focusNode.unfocus(),
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
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 2),
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
          ),
        );
      },
    );
  }

  Widget _tvRow({
    required String label,
    required String value,
    required String hint,
    required VoidCallback onTap,
  }) {
    // Linha 100% navegável no D-pad (mesmo mecanismo dos botões que
    // já funcionam). OK abre o diálogo de edição com teclado.
    return TvFocusable(
      borderRadius: BorderRadius.circular(10),
      onPressed: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(
                    value.isEmpty ? hint : value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: value.isEmpty ? Colors.white38 : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_rounded,
                color: AppColors.primary, size: 22),
          ],
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

  Widget _dropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      dropdownColor: AppColors.surface,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: AppColors.surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(color: Colors.white)))).toList(),
      onChanged: onChanged,
    );
  }
}

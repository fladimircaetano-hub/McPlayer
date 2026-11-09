import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/xtream_server_directory.dart';
import '../controllers/iptv_controller.dart';
import '../widgets/tv_focusable.dart';
import 'home_screen.dart';

/// Entrada do cliente só com usuário e senha.
///
/// O endereço do servidor vem do painel (ou da lista embutida) e é testado
/// automaticamente até um deles aceitar a conta. O acesso é liberado pelo
/// próprio servidor Xtream; o painel recebe apenas o registro da conta,
/// sem a senha.
class AccountLoginScreen extends StatefulWidget {
  final IptvController controller;

  const AccountLoginScreen({super.key, required this.controller});

  @override
  State<AccountLoginScreen> createState() => _AccountLoginScreenState();
}

class _AccountLoginScreenState extends State<AccountLoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _userNode = FocusNode();
  final _passNode = FocusNode();
  bool _obscure = true;
  bool _sending = false;
  String _status = '';

  IptvController get controller => widget.controller;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _userNode.dispose();
    _passNode.dispose();
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
                        color: Colors.white70,
                      ),
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
              child: const Text(
                'Salvar',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
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

    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (user.isEmpty || pass.isEmpty) {
      _snack('Preencha usuário e senha.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _status = 'Procurando o servidor...';
    });

    final servers = await XtreamServerDirectory().load();
    final storage = controller.storageService;
    var credentialsAccepted = false;

    for (final server in servers) {
      if (!mounted) return;
      setState(() => _status = 'Testando ${server.name}...');

      try {
        final account = await controller.xtreamApi.authenticate(
          serverUrl: server.url,
          username: user,
          password: pass,
        );
        credentialsAccepted = true;

        await storage.setCredentialLogin(true);
        await storage.saveXtreamAccount(account);

        final activation = sl.activationService;
        if (activation != null) {
          unawaited(
            activation.registerXtreamLogin(
              serverUrl: account.serverUrl,
              username: account.username,
              deviceId: storage.getDeviceId(),
              mac: storage.getDeviceMac(),
              status: account.status,
              expDate: account.expDateIso,
            ),
          );
        }

        if (!mounted) return;
        setState(() => _status = 'Carregando canais...');

        final ok = await controller.loginXtream(
          serverUrl: server.url,
          username: user,
          password: pass,
          allowCache: true,
        );
        if (!mounted) return;

        if (ok) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => HomeScreen(controller: controller),
            ),
            (r) => false,
          );
          return;
        }

        setState(() {
          _sending = false;
          _status = '';
        });
        _snack(
          controller.errorMessage ??
              'Conta aceita, mas não foi possível carregar o catálogo.',
          error: true,
        );
        return;
      } catch (e) {
        debugPrint('[AccountLogin] ${server.name}: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _sending = false;
      _status = '';
    });
    _snack(
      credentialsAccepted
          ? 'Conta encontrada, mas não foi possível carregar o catálogo.'
          : 'Usuário ou senha inválidos, ou conta sem servidor disponível.',
      error: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTv = MediaQuery.of(context).size.width >= 900;
    final hPad = isTv ? 64.0 : 24.0;
    final titleSize = isTv ? 22.0 : 30.0;
    final gap = isTv ? 8.0 : 12.0;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TvFocusable(
                    borderRadius: BorderRadius.circular(10),
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Entrar com usuário e senha',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: titleSize,
                    ),
                  ),
                ],
              ),
              SizedBox(height: gap + 4),
              const Text(
                'Digite os dados que você recebeu. O servidor é encontrado automaticamente.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              SizedBox(height: gap + 8),
              if (isTv) ...[
                _tvRow(
                  label: 'Usuário',
                  value: _userCtrl.text,
                  hint: 'Toque OK p/ digitar o usuário',
                  onTap: () => _openTvEditor(
                    title: 'Usuário',
                    target: _userCtrl,
                  ),
                ),
                SizedBox(height: gap),
                _tvRow(
                  label: 'Senha',
                  value: _obscure
                      ? '•' * _passCtrl.text.length
                      : _passCtrl.text,
                  hint: 'Toque OK p/ digitar a senha',
                  onTap: () => _openTvEditor(
                    title: 'Senha',
                    target: _passCtrl,
                    obscure: true,
                    keyboard: TextInputType.visiblePassword,
                  ),
                ),
              ] else ...[
                _field(
                  _userCtrl,
                  'Usuário',
                  focusNode: _userNode,
                  autofocus: true,
                  keyboardType: TextInputType.text,
                  action: TextInputAction.next,
                  onSubmitted: (_) => _passNode.requestFocus(),
                ),
                const SizedBox(height: 12),
                _field(
                  _passCtrl,
                  'Senha',
                  focusNode: _passNode,
                  obscure: _obscure,
                  keyboardType: TextInputType.visiblePassword,
                  action: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  onToggleObscure: () =>
                      setState(() => _obscure = !_obscure),
                ),
              ],
              SizedBox(height: gap + 8),
              Center(
                child: _pillButton(
                  'Entrar',
                  _submit,
                  loading: _sending,
                  primary: true,
                ),
              ),
              if (_sending) ...[
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    _status.isEmpty ? 'Entrando...' : _status,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
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
    bool obscure = false,
    TextInputType? keyboardType,
    TextInputAction? action,
    ValueChanged<String>? onSubmitted,
    VoidCallback? onToggleObscure,
  }) {
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
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 14,
              ),
              suffixIcon: onToggleObscure == null
                  ? null
                  : IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white70,
                      ),
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
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value.isEmpty ? hint : value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: value.isEmpty ? Colors.white38 : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.edit_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillButton(
    String label,
    VoidCallback onTap, {
    bool loading = false,
    bool primary = false,
  }) {
    return TvFocusable(
      borderRadius: BorderRadius.circular(20),
      onPressed: loading ? () {} : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 10),
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
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
            : Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: primary ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

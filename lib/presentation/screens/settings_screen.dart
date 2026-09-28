import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/activation/activation_config.dart';
import '../../core/di/service_locator.dart';
import '../../core/activation/activation_models.dart';
import '../../core/activation/admin_config.dart';
import '../../core/storage/storage_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/back_navigation_mixin.dart';
import '../controllers/iptv_controller.dart';
import '../widgets/tv_focusable.dart';
import 'lists_screen.dart';
import 'admin_screen.dart';

/// Textos da tela em PT/EN. O idioma vem de [StorageService.languageNotifier]
/// e a troca aplica na hora (listener no [initState]), sem reiniciar o app.
const Map<String, Map<String, String>> _strings = {
  'pt': {
    'settings': 'Settings',
    'm_info': 'Informacoes gerais',
    'm_lang': 'Trocar idioma',
    'm_format': 'Formato do stream',
    'm_pin': 'Codigo PIN',
    'm_cats': 'Gerenciar categorias',
    'm_clear': 'Limpar dados',
    'm_time': 'Data e hora',
    'm_high': 'Destaques da home',
    'm_tmdb': 'Usar TMDB API',
    'm_player': 'Configuracoes do player',
    'm_test': 'Testar Conexao',
    'm_admin': 'Admin (Dispositivos)',
    'p_info': 'Info do aparelho',
    'mac': 'Endereco MAC',
    'appver': 'Versao do app',
    'devkey': 'Chave do aparelho',
    'xtream_user': 'Usuario Xtream',
    'lista': 'Lista',
    'p_lang': 'Trocar idioma',
    'snack_pt': 'Idioma: Portugues',
    'snack_en': 'Idioma: ingles',
    'p_format': 'Formato do stream',
    'snack_ts': 'Formato: mpegts -- vale para os canais Xtream',
    'snack_hls': 'Formato: m3u8 -- vale para os canais Xtream',
    'p_pin': 'Trocar PIN',
    'pin_set': 'PIN definido',
    'pin_no': 'Sem PIN',
    'pin_hint': 'Novo PIN (4 digitos)',
    'pin_save': 'Salvar',
    'pin_need4': 'Digite 4 digitos',
    'pin_saved': 'PIN salvo',
    'p_cats': 'Gerenciar categorias',
    'cat_live': 'TV ao vivo',
    'cat_movies': 'Filmes',
    'cat_series': 'Series',
    'p_clear': 'Limpar dados',
    'clear_fav': 'Limpar favoritos',
    'fav_cleared': 'Favoritos apagados',
    'logout_keep': 'Sair da lista (manter favoritos)',
    'wipe': 'Apagar tudo',
    'p_time': 'Data e hora',
    'dev_time': 'Horario do aparelho',
    'tz': 'Fuso',
    'p_high': 'Destaques da home',
    'show_counts': 'Mostrar contadores no menu',
    'p_tmdb': 'Usar TMDB API',
    'tmdb_desc': 'Buscar posteres e sinopses (TMDB)',
    'p_player': 'Configuracoes do player',
    'keep_on': 'Manter tela ligada no player',
    'p_test': 'Testar Conexao Dashboard',
    'test_ok': 'Conexao OK',
    'test_fail': 'Falha na conexao',
    'test_pending': 'Testando...',
    'test_unconfigured': 'Ativacao remota desligada (configure no activation_config.dart)',
    'test_details': 'Detalhes:',
    'disclaimer':
        'McPlayer e apenas um reprodutor de midia. Nao fornece listas, canais ou conteudos e nao se responsabiliza pelo uso indevido do aplicativo.',
  },
  'en': {
    'settings': 'Settings',
    'm_info': 'General Info',
    'm_lang': 'Change Language',
    'm_format': 'Change Stream Format',
    'm_pin': 'Change Pin Code',
    'm_cats': 'Manage Categories',
    'm_clear': 'Clear Storage',
    'm_time': 'Time Settings',
    'm_high': 'Home Highlights',
    'm_tmdb': 'Use TMDB API',
    'm_player': 'Player Settings',
    'm_test': 'Test Connection',
    'm_admin': 'Admin (Devices)',
    'p_info': 'Device Info',
    'mac': 'Mac Address',
    'appver': 'App version',
    'devkey': 'Device key',
    'xtream_user': 'Xtream user',
    'lista': 'Playlist',
    'p_lang': 'Change Language',
    'snack_pt': 'Language: Portuguese',
    'snack_en': 'Language: English',
    'p_format': 'Change Stream Format',
    'snack_ts': 'Format: mpegts -- applies to Xtream channels',
    'snack_hls': 'Format: m3u8 -- applies to Xtream channels',
    'p_pin': 'Change Pin Code',
    'pin_set': 'PIN set',
    'pin_no': 'No PIN',
    'pin_hint': 'New PIN (4 digits)',
    'pin_save': 'Save',
    'pin_need4': 'Enter 4 digits',
    'pin_saved': 'PIN saved',
    'p_cats': 'Manage Categories',
    'cat_live': 'Live TV',
    'cat_movies': 'Movies',
    'cat_series': 'Series',
    'p_clear': 'Clear Storage',
    'clear_fav': 'Clear favorites',
    'fav_cleared': 'Favorites deleted',
    'logout_keep': 'Sign out of playlist (keep favorites)',
    'wipe': 'Erase everything',
    'p_time': 'Time Settings',
    'dev_time': 'Device time',
    'tz': 'Time zone',
    'p_high': 'Home Highlights',
    'show_counts': 'Show counters in menu',
    'p_tmdb': 'Use TMDB API',
    'tmdb_desc': 'Fetch posters and synopses (TMDB)',
    'p_player': 'Player Settings',
    'keep_on': 'Keep screen on in player',
    'p_test': 'Test Dashboard Connection',
    'test_ok': 'Connection OK',
    'test_fail': 'Connection failed',
    'test_pending': 'Testing...',
    'test_unconfigured': 'Remote activation disabled (configure in activation_config.dart)',
    'test_details': 'Details:',
    'disclaimer':
        'McPlayer is only a media player. It does not provide lists, channels or content and is not responsible for misuse of the app.',
  },
};

/// Tela "Settings" conforme modelo: menu a esquerda, painel a direita.
///
/// - General Info: Device Info (MAC, versoes, chave)
/// - Demais itens abrem paineis com a opcao correspondente.
class SettingsScreen extends StatefulWidget {
  final IptvController controller;

  const SettingsScreen({super.key, required this.controller});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with BackNavigationMixin {
  int _selected = 0;
  final TextEditingController _pinCtrl = TextEditingController();
  String _appVersion = '';
  String _testResult = '';
  bool _testing = false;

  StorageService get _storage => widget.controller.storageService;
  bool get _isTv => MediaQuery.of(context).size.width >= 900;

  String tr(String key) {
    final lang = _storage.languageNotifier.value;
    return _strings[lang]?[key] ?? _strings['pt']![key] ?? key;
  }

  List<String> get _menu => [
        tr('m_info'),
        tr('m_lang'),
        tr('m_format'),
        tr('m_pin'),
        tr('m_cats'),
        tr('m_clear'),
        tr('m_time'),
        tr('m_high'),
        tr('m_tmdb'),
        tr('m_player'),
        tr('m_test'),
        if (AdminConfig.isEnabled) tr('m_admin'),
      ];

  @override
  void initState() {
    super.initState();
    _storage.languageNotifier.addListener(_onLangChanged);
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _appVersion = '${info.version}+${info.buildNumber}');
    });
  }

  void _onLangChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _storage.languageNotifier.removeListener(_onLangChanged);
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await widget.controller.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => ListsScreen(controller: widget.controller)),
        (r) => false,
      );
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  /// Rebuild apos escrita async em prefs. Escritas sao rapidas, mas o
  /// usuario pode ter voltado da tela no meio do await -- sem o guard,
  /// setState em widget desmontado lanca excecao.
  void _refresh() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _testConnection() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _testResult = tr('test_pending');
    });

    try {
      if (!ActivationConfig.isEnabled) {
        setState(() {
          _testResult = tr('test_unconfigured');
          _testing = false;
        });
        return;
      }

      final deviceId = _storage.getDeviceId();
      final mac = _storage.getDeviceMac();

      final service = sl.activationService;
      if (service == null) {
        setState(() {
          _testing = false;
          _testResult = tr('test_unconfigured');
        });
        return;
      }
      final result = await service.checkIn(deviceId: deviceId, mac: mac);

      if (!mounted) return;

      setState(() {
        _testing = false;
        switch (result.status) {
          case ActivationStatus.approved:
            _testResult = '${tr('test_ok')} (${result.status.name})';
            break;
          case ActivationStatus.pending:
            _testResult = 'Pendente aprovacao no dashboard';
            break;
          case ActivationStatus.rejected:
            _testResult = 'Rejeitado pelo dashboard';
            break;
          case ActivationStatus.notFound:
            _testResult = 'Dispositivo nao registrado (check-in enviado)';
            break;
          case ActivationStatus.disabled:
            _testResult = tr('test_unconfigured');
            break;
        }
        _testResult += '\n${tr('test_details')} ${result.status.name}';
        if (result.listData != null) {
          _testResult += '\nLista vinculada: ${result.listData!.type}';
        }
        if (result.approvedAt != null) {
          _testResult += '\nAprovado em: ${result.approvedAt}';
        }
      });

      _snack(_testResult);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testResult = '${tr('test_fail')}: $e';
      });
      _snack(_testResult);
    }
  }

@override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return buildWithBackGuard(
          child: FocusScope(
            autofocus: true,
            child: Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 16),
                      Expanded(child: _buildContent()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        TvFocusable(
          borderRadius: BorderRadius.circular(10),
          onPressed: handleBackButton,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 26),
          ),
        ),
        const SizedBox(width: 8),
        Text(tr('settings'),
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 34)),
      ],
    );
  }

  Widget _buildContent() {
    if (_isTv) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 380, child: _buildMenu()),
          const SizedBox(width: 32),
          Expanded(child: _buildPanel()),
        ],
      );
    } else {
      return ListView(
        children: [
          _buildMenu(),
          const SizedBox(height: 16),
          _buildPanel(),
        ],
      );
    }
  }

  Widget _buildMenu() {
    final menu = _menu;
    return ListView.builder(
      shrinkWrap: true,
      physics: _isTv
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: menu.length,
      itemBuilder: (context, i) {
        final selected = i == _selected;
        final isTmdb = i == 8;
        final isAdmin = AdminConfig.isEnabled && i == menu.length - 1;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TvFocusable(
            borderRadius: BorderRadius.circular(10),
            onPressed: () => _onMenuTap(i),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: selected ? Colors.white : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: selected
                        ? Colors.white
                        : AppColors.cardBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      menu[i],
                      style: TextStyle(
                          color:
                              selected ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16),
                    ),
                  ),
                  if (isTmdb)
                    Switch(
                      value: _storage.getTmdbEnabled(),
                      onChanged: (v) async {
                        await _storage.setTmdbEnabled(v);
                        _refresh();
                      },
                    ),
                  if (isAdmin)
                    const Icon(Icons.admin_panel_settings, color: AppColors.accentGreen, size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _onMenuTap(int i) {
    if (i == 8) {
      // TMDB alterna direto.
      _storage
          .setTmdbEnabled(!_storage.getTmdbEnabled())
          .then((_) => setState(() {}));
      return;
    }
    setState(() => _selected = i);
  }

  Widget _buildPanel() {
    switch (_selected) {
      case 0:
        return _deviceInfoPanel();
      case 1:
        return _languagePanel();
      case 2:
        return _streamFormatPanel();
      case 3:
        return _pinPanel();
      case 4:
        return _categoriesPanel();
      case 5:
        return _clearStoragePanel();
      case 6:
        return _timePanel();
      case 7:
        return _highlightsPanel();
      case 8:
        return _tmdbPanel();
      case 9:
        return _playerPanel();
      case 10:
        return _testConnectionPanel();
      case 11:
        return _adminPanel();
      default:
        return _playerPanel();
    }
  }

  Widget _panelTitle(String title, {String? value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20)),
          ),
          if (value != null)
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
        ],
      ),
    );
  }

  Widget _optionRow({
    required String label,
    String? value,
    bool checked = false,
    bool showCheck = true,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TvFocusable(
        borderRadius: BorderRadius.circular(10),
        onPressed: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 15)),
              ),
              if (value != null)
                Text(value,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 14)),
              if (showCheck && checked)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.check_rounded,
                      color: AppColors.accentGreen),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TvFocusable(
        borderRadius: BorderRadius.circular(10),
        onPressed: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 15)),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- paineis ----------

  Widget _deviceInfoPanel() {
    final mac = _storage.getDeviceMac();
    final deviceId = _storage.getDeviceId();
    final account = widget.controller.currentAccount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle(tr('p_info')),
        _panelTitle(tr('mac'), value: mac.toLowerCase()),
        _panelTitle(tr('appver'),
            value: _appVersion.isEmpty ? '...' : _appVersion),
        _panelTitle(tr('devkey'), value: deviceId),
        if (account != null)
          _panelTitle(tr('xtream_user'), value: account.username),
        if (widget.controller.loadedListName != null)
          _panelTitle(tr('lista'), value: widget.controller.loadedListName!),
        const SizedBox(height: 16),
        Text(
          tr('disclaimer'),
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _languagePanel() {
    final lang = _storage.getLanguage();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle(tr('p_lang')),
        _optionRow(
          label: 'Portugues',
          checked: lang == 'pt',
          onTap: () async {
            await _storage.setLanguage('pt');
            _snack(tr('snack_pt'));
          },
        ),
        _optionRow(
          label: 'English',
          checked: lang == 'en',
          onTap: () async {
            await _storage.setLanguage('en');
            _snack(tr('snack_en'));
          },
        ),
      ],
    );
  }

  Widget _streamFormatPanel() {
    final fmt = _storage.getStreamFormat();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle(tr('p_format')),
        _optionRow(
          label: 'mpegts (TS)',
          checked: fmt == 'mpegts',
          onTap: () async {
            await _storage.setStreamFormat('mpegts');
            _refresh();
            _snack(tr('snack_ts'));
          },
        ),
        _optionRow(
          label: 'm3u8 (HLS)',
          checked: fmt == 'm3u8',
          onTap: () async {
            await _storage.setStreamFormat('m3u8');
            _refresh();
            _snack(tr('snack_hls'));
          },
        ),
      ],
    );
  }

  Widget _pinPanel() {
    final hasPin = (_storage.getPin() ?? '').isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle(tr('p_pin'),
            value: hasPin ? tr('pin_set') : tr('pin_no')),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _pinCtrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: tr('pin_hint'),
              counterText: '',
            ),
          ),
        ),
        TvFocusable(
          borderRadius: BorderRadius.circular(10),
          onPressed: () async {
            final pin = _pinCtrl.text.trim();
            if (pin.length != 4) {
              _snack(tr('pin_need4'));
              return;
            }
            await _storage.setPin(pin);
            _pinCtrl.clear();
            _refresh();
            _snack(tr('pin_saved'));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 32, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(tr('pin_save'),
                style: const TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _categoriesPanel() {
    final hidden = _storage.getHiddenSections();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle(tr('p_cats')),
        _switchRow(
          label: tr('cat_live'),
          value: !hidden.contains('live'),
          onChanged: (v) async {
            await _storage.setSectionHidden('live', !v);
            _refresh();
          },
        ),
        _switchRow(
          label: tr('cat_movies'),
          value: !hidden.contains('movie'),
          onChanged: (v) async {
            await _storage.setSectionHidden('movie', !v);
            _refresh();
          },
        ),
        _switchRow(
          label: tr('cat_series'),
          value: !hidden.contains('series'),
          onChanged: (v) async {
            await _storage.setSectionHidden('series', !v);
            _refresh();
          },
        ),
      ],
    );
  }

  Widget _clearStoragePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle(tr('p_clear')),
        _optionRow(
          label: tr('clear_fav'),
          showCheck: false,
          onTap: () async {
            await _storage.clearFavorites();
            await widget.controller.reload();
            _snack(tr('fav_cleared'));
          },
        ),
        _optionRow(
          label: tr('logout_keep'),
          showCheck: false,
          onTap: _logout,
        ),
        _optionRow(
          label: tr('wipe'),
          showCheck: false,
          onTap: () async {
            await _storage.clearAll();
            await _logout();
          },
        ),
      ],
    );
  }

  Widget _timePanel() {
    final now = DateTime.now();
    final label =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle(tr('p_time')),
        _panelTitle(tr('dev_time'), value: label),
        _panelTitle(tr('tz'), value: now.timeZoneName),
      ],
    );
  }

  Widget _highlightsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle(tr('p_high')),
        _switchRow(
          label: tr('show_counts'),
          value: _storage.getShowCounts(),
          onChanged: (v) async {
            await _storage.setShowCounts(v);
            _refresh();
          },
        ),
      ],
    );
  }

  Widget _tmdbPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle(tr('p_tmdb')),
        _switchRow(
          label: tr('tmdb_desc'),
          value: _storage.getTmdbEnabled(),
          onChanged: (v) async {
            await _storage.setTmdbEnabled(v);
            _refresh();
          },
        ),
      ],
    );
  }

  Widget _playerPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle(tr('p_player')),
        _switchRow(
          label: tr('keep_on'),
          value: _storage.getKeepScreenOn(),
          onChanged: (v) async {
            await _storage.setKeepScreenOn(v);
            _refresh();
          },
        ),
      ],
    );
  }

  Widget _testConnectionPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle(tr('p_test')),
        const SizedBox(height: 8),
        _optionRow(
          label: tr('test_pending'),
          showCheck: false,
          onTap: _testConnection,
        ),
        const SizedBox(height: 16),
        if (_testResult.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: SelectableText(
              _testResult,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
          ),
        const SizedBox(height: 16),
        _panelTitle('Configuracao atual'),
        _panelTitle(
          'Supabase URL',
          value: ActivationConfig.supabaseUrl.isEmpty
              ? '(nao configurado)'
              : ActivationConfig.supabaseUrl,
        ),
        _panelTitle(
          'App Name',
          value: ActivationConfig.appName,
        ),
        _panelTitle(
          'Poll Interval',
          value: '${ActivationConfig.pollInterval.inSeconds}s',
        ),
        const SizedBox(height: 16),
        _panelTitle('Dispositivo'),
        _panelTitle('Device ID', value: _storage.getDeviceId()),
        _panelTitle('MAC', value: _storage.getDeviceMac().toLowerCase()),
      ],
    );
  }

  Widget _adminPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle(tr('m_admin')),
        const SizedBox(height: 8),
        _optionRow(
          label: 'Abrir Admin (aprovar dispositivos)',
          showCheck: false,
          onTap: () {
            final service = sl.activationService;
            if (service == null) {
              _snack('Ativação remota não configurada');
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AdminScreen(),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        _panelTitle('Como usar'),
        const Text(
          '1. Configure ADMIN_PIN via --dart-define no build\n'
          '2. Abre tela admin protegida por PIN seguro\n'
          '3. Lista dispositivos pendentes do Supabase\n'
          '4. Aprova + insere lista (M3U ou Xtream) em 1 clique\n'
          '5. Funciona junto com o dashboard web\n',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }
}
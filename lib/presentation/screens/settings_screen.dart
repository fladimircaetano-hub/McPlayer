import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/storage/storage_service.dart';
import '../../core/theme/app_theme.dart';
import '../controllers/iptv_controller.dart';
import '../widgets/tv_focusable.dart';
import 'entry_screen.dart';

/// Tela "Settings" conforme modelo: menu à esquerda, painel à direita.
///
/// - General Info: Device Info (MAC, versões, chave)
/// - Demais itens abrem painéis com a opção correspondente.
class SettingsScreen extends StatefulWidget {
  final IptvController controller;

  const SettingsScreen({super.key, required this.controller});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _menu = [
    'General Info',
    'Change Language',
    'Change Stream Format',
    'Change Pin Code',
    'Manage Categories',
    'Clear Storage',
    'Time Settings',
    'Home Highlights',
    'Use TMDB API',
    'Player Settings',
  ];

  int _selected = 0;
  final TextEditingController _pinCtrl = TextEditingController();

  StorageService get _storage => widget.controller.storageService;
  bool get _isTv => MediaQuery.of(context).size.width >= 900;

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await widget.controller.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => EntryScreen(controller: widget.controller)),
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

  /// Rebuild após escrita async em prefs. Escritas são rápidas, mas o
  /// usuário pode ter voltado da tela no meio do await — sem o guard,
  /// setState em widget desmontado lança exceção.
  void _refresh() {
    if (!mounted) return;
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.goBack):
                _onBack,
          },
          child: FocusScope(
            autofocus: true,
            child: Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          TvFocusable(
                            borderRadius:
                                BorderRadius.circular(10),
                            onPressed: _onBack,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(
                                  Icons.arrow_back_rounded,
                                  color: Colors.white,
                                  size: 26),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('Settings',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 34)),
                        ],
                      ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _isTv
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 380, child: _buildMenu()),
                              const SizedBox(width: 32),
                              Expanded(child: _buildPanel()),
                            ],
                          )
                        : ListView(
                            children: [
                              _buildMenu(),
                              const SizedBox(height: 16),
                              _buildPanel(),
                            ],
                          ),
                  ),
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

  void _onBack() {
    Navigator.of(context).maybePop();
  }

  Widget _buildMenu() {
    return ListView.builder(
      shrinkWrap: true,
      physics: _isTv
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: _menu.length,
      itemBuilder: (context, i) {
        final selected = i == _selected;
        final isTmdb = i == 8;
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
                      _menu[i],
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

  // ---------- painéis ----------

  Widget _deviceInfoPanel() {
    final mac = _storage.getDeviceMac();
    final deviceId = _storage.getDeviceId();
    final account = widget.controller.currentAccount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle('Device Info'),
        _panelTitle('Mac Address', value: mac.toLowerCase()),
        _panelTitle('App version', value: '1.0.0'),
        _panelTitle('Product Version', value: '1.0.0+1'),
        _panelTitle('Device key', value: deviceId),
        if (account != null)
          _panelTitle('Xtream user', value: account.username),
        if (widget.controller.loadedListName != null)
          _panelTitle('Lista', value: widget.controller.loadedListName!),
      ],
    );
  }

  Widget _languagePanel() {
    final lang = _storage.getLanguage();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle('Change Language'),
        _optionRow(
          label: 'Português',
          checked: lang == 'pt',
          onTap: () async {
            await _storage.setLanguage('pt');
            _refresh();
            _snack('Idioma: Português');
          },
        ),
        _optionRow(
          label: 'English',
          checked: lang == 'en',
          onTap: () async {
            await _storage.setLanguage('en');
            _refresh();
            _snack('Language: English');
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
        _panelTitle('Change Stream Format'),
        _optionRow(
          label: 'mpegts (TS)',
          checked: fmt == 'mpegts',
          onTap: () async {
            await _storage.setStreamFormat('mpegts');
            _refresh();
            _snack('Formato: mpegts — vale para os canais Xtream');
          },
        ),
        _optionRow(
          label: 'm3u8 (HLS)',
          checked: fmt == 'm3u8',
          onTap: () async {
            await _storage.setStreamFormat('m3u8');
            _refresh();
            _snack('Formato: m3u8 — vale para os canais Xtream');
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
        _panelTitle('Change Pin Code',
            value: hasPin ? 'PIN definido' : 'Sem PIN'),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _pinCtrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              hintText: 'Novo PIN (4 dígitos)',
              counterText: '',
            ),
          ),
        ),
        TvFocusable(
          borderRadius: BorderRadius.circular(10),
          onPressed: () async {
            final pin = _pinCtrl.text.trim();
            if (pin.length != 4) {
              _snack('Digite 4 dígitos');
              return;
            }
            await _storage.setPin(pin);
            _pinCtrl.clear();
            _refresh();
            _snack('PIN salvo');
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 32, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('Salvar',
                style: TextStyle(
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
        _panelTitle('Manage Categories'),
        _switchRow(
          label: 'TV ao vivo',
          value: !hidden.contains('live'),
          onChanged: (v) async {
            await _storage.setSectionHidden('live', !v);
            _refresh();
          },
        ),
        _switchRow(
          label: 'Filmes',
          value: !hidden.contains('movie'),
          onChanged: (v) async {
            await _storage.setSectionHidden('movie', !v);
            _refresh();
          },
        ),
        _switchRow(
          label: 'Séries',
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
        _panelTitle('Clear Storage'),
        _optionRow(
          label: 'Limpar favoritos',
          showCheck: false,
          onTap: () async {
            await _storage.clearFavorites();
            await widget.controller.reload();
            _snack('Favoritos apagados');
          },
        ),
        _optionRow(
          label: 'Sair da lista (manter favoritos)',
          showCheck: false,
          onTap: _logout,
        ),
        _optionRow(
          label: 'Apagar tudo',
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
        _panelTitle('Time Settings'),
        _panelTitle('Horário do aparelho', value: label),
        _panelTitle('Fuso', value: now.timeZoneName),
      ],
    );
  }

  Widget _highlightsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle('Home Highlights'),
        _switchRow(
          label: 'Mostrar contadores no menu',
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
        _panelTitle('Use TMDB API'),
        _switchRow(
          label: 'Buscar pôsteres e sinopses (TMDB)',
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
        _panelTitle('Player Settings'),
        _switchRow(
          label: 'Manter tela ligada no player',
          value: _storage.getKeepScreenOn(),
          onChanged: (v) async {
            await _storage.setKeepScreenOn(v);
            _refresh();
          },
        ),
      ],
    );
  }
}

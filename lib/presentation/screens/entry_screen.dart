import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/theme/app_theme.dart';
import '../controllers/iptv_controller.dart';
import '../widgets/app_logo.dart';
import '../widgets/device_id_card.dart';
import '../widgets/tv_focusable.dart';
import 'home_screen.dart';

class EntryScreen extends StatefulWidget {
  final IptvController controller;

  const EntryScreen({super.key, required this.controller});

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Form M3U
  final TextEditingController _urlCtrl = TextEditingController();

  // Form Xtream
  final TextEditingController _serverCtrl = TextEditingController();
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  bool _obscurePassword = true;

  late final String _deviceId;
  late final String _deviceMac;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Identificação do aparelho (gerada 1x e persistida)
    _deviceId = widget.controller.storageService.getDeviceId();
    _deviceMac = widget.controller.storageService.getDeviceMac();

    // Carregar última URL ou credenciais salvas
    final lastUrl = widget.controller.storageService.getLastM3uUrl();
    if (lastUrl != null && lastUrl.isNotEmpty) {
      _urlCtrl.text = lastUrl;
    }

    final savedAccount = widget.controller.storageService.getXtreamAccount();
    if (savedAccount != null) {
      _serverCtrl.text = savedAccount.serverUrl;
      _userCtrl.text = savedAccount.username;
      _passCtrl.text = savedAccount.password;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _urlCtrl.dispose();
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleM3uSubmit() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _showSnackBar('Por favor, informe a URL da lista .m3u ou .m3u8');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        !uri.host.contains('.')) {
      _showSnackBar('URL inválida. Use http(s)://seu-servidor/playlist.m3u8');
      return;
    }
    FocusScope.of(context).unfocus();

    final success = await widget.controller.loadFromM3uUrl(url);
    if (success && mounted) {
      _goToHome();
    }
  }

  Future<void> _handlePickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m3u', 'm3u8', 'txt'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final success = await widget.controller.loadFromLocalFile(path);
        if (success && mounted) {
          _goToHome();
        }
      }
    } catch (e) {
      _showSnackBar('Erro ao selecionar arquivo: ${e.toString()}');
    }
  }

  Future<void> _handleXtreamSubmit() async {
    final server = _serverCtrl.text.trim();
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (server.isEmpty || user.isEmpty || pass.isEmpty) {
      _showSnackBar('Preencha todos os campos do Xtream Codes');
      return;
    }
    FocusScope.of(context).unfocus();

    final success = await widget.controller.loginXtream(
      serverUrl: server,
      username: user,
      password: pass,
    );

    if (success && mounted) {
      _goToHome();
    }
  }

  /// Carrega uma lista de canais abertos e públicos para testes imediatos
  Future<void> _loadDemoStreams() async {
    const demoUrl = 'https://iptv-org.github.io/iptv/countries/br.m3u';
    _urlCtrl.text = demoUrl;
    final success = await widget.controller.loadFromM3uUrl(demoUrl);
    if (success && mounted) {
      _goToHome();
    }
  }

  void _goToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeScreen(controller: widget.controller),
      ),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTv = size.width >= 800;

    return Scaffold(
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          return Stack(
            children: [
              // Fundo com gradiente sutil
              Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.6),
                    radius: 1.2,
                    colors: [
                      Color(0xFF162032),
                      AppColors.background,
                    ],
                  ),
                ),
              ),

              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: isTv ? 650 : 480),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Header Logo & Título
                          _buildHeader(),
                          const SizedBox(height: 28),

                          // Seletor de Método de Login (Tabs)
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              indicator: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              labelColor: Colors.black,
                              unselectedLabelColor: AppColors.textSecondary,
                              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              tabs: const [
                                Tab(
                                  icon: Icon(Icons.link_rounded, size: 18),
                                  text: 'Lista M3U / Arquivo',
                                ),
                                Tab(
                                  icon: Icon(Icons.dns_rounded, size: 18),
                                  text: 'Xtream Codes API',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Conteúdo das Abas
                          SizedBox(
                            height: 330,
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                _buildM3uTab(),
                                _buildXtreamTab(),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),
                          // Botão de Teste Demo
                          TvFocusable(
                            borderRadius: BorderRadius.circular(10),
                            onPressed: _loadDemoStreams,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.bolt_rounded, color: AppColors.primary, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Carregar Lista de Teste Pública (Canais Abertos BR)',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Identificação do aparelho p/ ativação
                          DeviceIdCard(deviceId: _deviceId, mac: _deviceMac),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Modal de Carregamento em Tela Cheia
              if (widget.controller.isLoading) _buildLoadingOverlay(),

              // Mensagem de Erro
              if (widget.controller.errorMessage != null)
                Positioned(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 500),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF381414),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.redAccent),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.controller.errorMessage!,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return const Column(
      children: [
        AppLogo(iconSize: 64, titleSize: 30),
        SizedBox(height: 8),
        Text(
          'Player profissional de streaming para Mobile & Android TV',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  // Aba 1: M3U URL ou Arquivo Local
  Widget _buildM3uTab() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Insira o link da sua lista IPTV (.m3u / .m3u8):',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _urlCtrl,
              decoration: InputDecoration(
                hintText: 'http://servidor.com/playlist.m3u8',
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: _urlCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _urlCtrl.clear(),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TvFocusable(
                    onPressed: _handleM3uSubmit,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.cloud_download_rounded, size: 20),
                      label: const Text('Carregar URL'),
                      onPressed: _handleM3uSubmit,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TvFocusable(
                    onPressed: _handlePickFile,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.folder_open_rounded, size: 20),
                      label: const Text('Arquivo Local'),
                      onPressed: _handlePickFile,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Text(
              'Suporta fluxos HLS (.m3u8), canais ao vivo, filmes VOD e séries com categorização automática.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // Aba 2: Xtream Codes API
  Widget _buildXtreamTab() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _serverCtrl,
              decoration: const InputDecoration(
                hintText: 'URL do Servidor (ex: http://iptv.exemplo.com:8080)',
                prefixIcon: Icon(Icons.dns_rounded),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Usuário',
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _passCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      hintText: 'Senha',
                      prefixIcon: const Icon(Icons.lock_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          size: 18,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TvFocusable(
              onPressed: _handleXtreamSubmit,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.login_rounded, size: 20),
                label: const Text('Conectar via Xtream Codes'),
                onPressed: _handleXtreamSubmit,
              ),
            ),
            const Spacer(),
            const Text(
              'Conexão direta com servidores Xtream Codes, carregando categorias de TV Ao Vivo, VOD e Séries.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.controller.loadingStatus,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Por favor, aguarde...',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/activation/activation_config.dart';
import '../../core/activation/admin_config.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_theme.dart';

/// Tela Admin oculta: aprova dispositivos + insere lista direto no Supabase.
/// Acesso: Settings → segurar "Testar Conexão" por 2s ou digitar PIN.
class AdminScreen extends StatefulWidget {
  const AdminScreen({
    super.key,
  });

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<_DeviceRow> _devices = [];
  List<Map<String, dynamic>> _playlists = [];
  bool _loading = true;
  String _error = '';
  Timer? _pollTimer;
  final TextEditingController _pinController = TextEditingController();
  bool _showPinDialog = true;

  @override
  void initState() {
    super.initState();
    if (!ActivationConfig.isEnabled) {
      _error = 'Ativação remota desligada (configure activation_config.dart)';
      _loading = false;
    } else if (!AdminConfig.isEnabled) {
      _error = 'Admin desabilitado (configure ADMIN_PIN via --dart-define)';
      _loading = false;
    } else {
      _loadDevices();
      _loadPlaylists();
      _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadDevices());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    if (!mounted) {
      return;
    }
    setState(() => _loading = true);
    try {
      final service = sl.activationService;
      if (service == null) {
        setState(() {
          _loading = false;
          _error = 'ActivationService não disponível';
        });
        return;
      }
      final data = await service.fetchAllDevices();
      if (mounted) {
        setState(() {
          _devices = data.map((e) => _DeviceRow.fromJson(e)).toList();
          _loading = false;
          _error = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Erro ao carregar: $e';
        });
      }
    }
  }

  Future<void> _loadPlaylists() async {
    if (!mounted) {
      return;
    }
    try {
      final service = sl.activationService;
      if (service == null) {
        setState(() {
          _playlists = [];
        });
        return;
      }
      final data = await service.fetchPlaylists();
      if (mounted) {
        setState(() {
          _playlists = data;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _playlists = [];
        });
      }
    }
  }

  Future<void> _approveDevice(_DeviceRow device, {String status = 'approved', String? m3uUrl, String? xtreamUrl, String? xtreamUser, String? xtreamPass}) async {
    try {
      Map<String, dynamic>? listData;
      if (xtreamUrl != null && xtreamUrl.isNotEmpty &&
          xtreamUser != null && xtreamUser.isNotEmpty &&
          xtreamPass != null && xtreamPass.isNotEmpty) {
        listData = {
          'type': 'xtream',
          'serverUrl': xtreamUrl,
          'username': xtreamUser,
          'password': xtreamPass,
        };
      } else if (m3uUrl != null && m3uUrl.isNotEmpty) {
        listData = {
          'type': 'm3u',
          'url': m3uUrl,
        };
      }
      if (listData == null) return;

      final service = sl.activationService!;
      final ok = await service.updateDevice(
        deviceId: device.deviceId,
        status: status,
        listData: listData,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? '${device.deviceId} ${status == 'approved' ? 'aprovado' : 'atualizado'}!' : 'Falha ao ${status == 'approved' ? 'aprovar' : 'atualizar'}'),
            backgroundColor: ok ? AppColors.accentGreen : Colors.redAccent,
          ),
        );
        if (ok) _loadDevices();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showApproveDialog(_DeviceRow device) {
    final isApproved = device.status == 'approved';
    String initialType = 'm3u';
    if (device.listData != null) {
      initialType = device.listData!['type']?.toString().toLowerCase() ?? 'm3u';
    }
    final typeController = TextEditingController(text: initialType);
    final urlController = TextEditingController(text: device.listData?['url']?.toString() ?? '');
    final serverController = TextEditingController(text: device.listData?['serverUrl']?.toString() ?? '');
    final userController = TextEditingController(text: device.listData?['username']?.toString() ?? '');
    final passController = TextEditingController(text: device.listData?['password']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(isApproved ? 'Editar lista de ${device.deviceId}' : 'Aprovar ${device.deviceId}', style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dropdownField(
                  label: 'Tipo',
                  value: typeController.text,
                  items: ['m3u', 'xtream'],
                  onChanged: (v) {
                    setDlgState(() => typeController.text = v!);
                  },
                ),
                const SizedBox(height: 12),
                if (typeController.text == 'm3u')
                  _textField('URL M3U', urlController, hint: 'http://.../playlist.m3u'),
                if (typeController.text == 'xtream') ...[
                  _textField('URL Painel', serverController, hint: 'http://painel.com:8080'),
                  _textField('Usuário', userController),
                  _textField('Senha', passController, obscure: true),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () {
                final m3u = urlController.text.trim();
                final srv = serverController.text.trim();
                final usr = userController.text.trim();
                final pwd = passController.text.trim();
                final valid = typeController.text == 'm3u'
                    ? m3u.isNotEmpty
                    : (srv.isNotEmpty && usr.isNotEmpty && pwd.isNotEmpty);
                if (!valid) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Informe a playlist (URL M3U ou Xtream completo).'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx);
                if (typeController.text == 'm3u') {
                  _approveDevice(device, m3uUrl: m3u);
                } else {
                  _approveDevice(device,
                    xtreamUrl: srv,
                    xtreamUser: usr,
                    xtreamPass: pwd,
                  );
                }
              },
              child: Text(isApproved ? 'Salvar' : 'Aprovar', style: const TextStyle(color: AppColors.accentGreen)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddClientDialog() {
    final deviceIdController = TextEditingController();
    final macController = TextEditingController();
    final typeController = TextEditingController(text: 'm3u');
    final urlController = TextEditingController();
    final serverController = TextEditingController();
    final userController = TextEditingController();
    final passController = TextEditingController();
    String? selectedPlaylistId;
    Map<String, dynamic>? selectedPlaylistData;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Adicionar Cliente', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _textField('Device ID', deviceIdController, hint: 'Opcional - auto gerado se vazio'),
                const SizedBox(height: 12),
                _textField('MAC Address', macController, hint: 'Opcional - auto gerado se vazio'),
                const SizedBox(height: 16),
                const Text('Playlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                if (_playlists.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    initialValue: selectedPlaylistId,
                    dropdownColor: AppColors.surface,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Selecionar playlist existente',
                      labelStyle: const TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.cardBorder)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
                    ),
                    hint: const Text('Escolher playlist...', style: TextStyle(color: Colors.white54)),
                    items: _playlists.map((p) => DropdownMenuItem(
                      value: p['id']?.toString(),
                      child: Text(p['name']?.toString() ?? 'Sem nome', style: const TextStyle(color: Colors.white)),
                    )).toList(),
                    onChanged: (v) {
                      setDlgState(() {
                        selectedPlaylistId = v;
                        if (v != null) {
                          selectedPlaylistData = _playlists.firstWhere((p) => p['id']?.toString() == v);
                          typeController.text = selectedPlaylistData!['type']?.toString().toLowerCase() ?? 'm3u';
                          urlController.text = selectedPlaylistData!['url']?.toString() ?? '';
                          serverController.text = selectedPlaylistData!['server_url']?.toString() ?? '';
                          userController.text = selectedPlaylistData!['username']?.toString() ?? '';
                          passController.text = selectedPlaylistData!['password']?.toString() ?? '';
                        } else {
                          selectedPlaylistData = null;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                _dropdownField(
                  label: 'Tipo',
                  value: typeController.text,
                  items: ['m3u', 'xtream'],
                  onChanged: (v) {
                    setDlgState(() => typeController.text = v!);
                    selectedPlaylistId = null;
                    selectedPlaylistData = null;
                  },
                ),
                const SizedBox(height: 12),
                if (typeController.text == 'm3u')
                  _textField('URL M3U', urlController, hint: 'http://.../playlist.m3u'),
                if (typeController.text == 'xtream') ...[
                  _textField('URL Painel', serverController, hint: 'http://painel.com:8080'),
                  _textField('Usuário', userController),
                  _textField('Senha', passController, obscure: true),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () async {
                final deviceId = deviceIdController.text.trim().isEmpty
                    ? 'dev_${DateTime.now().millisecondsSinceEpoch}'
                    : deviceIdController.text.trim();
                final mac = macController.text.trim().isEmpty
                    ? '00:00:00:00:00:00'
                    : macController.text.trim();

                Map<String, dynamic>? listData;
                if (typeController.text == 'm3u' && urlController.text.trim().isNotEmpty) {
                  listData = {'type': 'm3u', 'url': urlController.text.trim()};
                } else if (typeController.text == 'xtream' &&
                    serverController.text.trim().isNotEmpty &&
                    userController.text.trim().isNotEmpty &&
                    passController.text.trim().isNotEmpty) {
                  listData = {
                    'type': 'xtream',
                    'serverUrl': serverController.text.trim(),
                    'username': userController.text.trim(),
                    'password': passController.text.trim(),
                  };
                }

                Navigator.pop(ctx);
                final service = sl.activationService!;
                final ok = await service.createDevice(
                  deviceId: deviceId,
                  mac: mac,
                  status: listData != null ? 'approved' : 'pending',
                  listData: listData,
                );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok ? 'Cliente $deviceId criado!' : 'Falha ao criar cliente'),
                      backgroundColor: ok ? AppColors.accentGreen : Colors.redAccent,
                    ),
                  );
                  if (ok) _loadDevices();
                }
              },
              child: const Text('Criar', style: TextStyle(color: AppColors.accentGreen)),
            ),
          ],
        ),
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
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.cardBorder)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
      ),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(color: Colors.white)))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _textField(String label, TextEditingController ctrl, {bool obscure = false, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: Colors.white70),
          hintStyle: const TextStyle(color: Colors.white30),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.cardBorder)),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
        ),
      ),
    );
  }

  void _verifyPin() {
    if (_pinController.text == AdminConfig.adminPin) {
      setState(() {
        _showPinDialog = false;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN incorreto'), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showPinDialog) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.admin_panel_settings, color: AppColors.primary, size: 64),
                const SizedBox(height: 24),
                const Text('Área Admin', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Digite o PIN para acessar', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 24),
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
                  maxLength: 4,
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                  ),
                  onSubmitted: (_) => _verifyPin(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _verifyPin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Entrar', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Admin - Dispositivos', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.surface,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add, color: Colors.white),
            onPressed: _showAddClientDialog,
            tooltip: 'Adicionar Cliente',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadDevices,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error.isNotEmpty
              ? Center(child: Text(_error, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center))
              : _devices.isEmpty
                  ? const Center(child: Text('Nenhum dispositivo', style: TextStyle(color: Colors.white54)))
                  : RefreshIndicator(
                      onRefresh: _loadDevices,
                      color: AppColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _devices.length,
                        itemBuilder: (_, i) {
                          final d = _devices[i];
                          final isPending = d.status == 'pending';
                          final isApproved = d.status == 'approved';
                          return Card(
                            color: AppColors.surface,
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isApproved ? AppColors.accentGreen : (isPending ? Colors.orange : Colors.redAccent),
                                child: Text(d.deviceId, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                              title: Text(d.deviceId, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('MAC: ${d.mac}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  Text('Status: ${d.status}', style: TextStyle(
                                    color: isApproved ? AppColors.accentGreen : (isPending ? Colors.orange : Colors.redAccent),
                                    fontWeight: FontWeight.bold,
                                  )),
                                  if (d.listData != null)
                                    Text('Lista: ${d.listData!['type']}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                ],
                              ),
                              trailing: isPending
                                  ? IconButton(
                                      icon: const Icon(Icons.check_circle, color: AppColors.accentGreen, size: 28),
                                      onPressed: () => _showApproveDialog(d),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.edit, color: AppColors.primary, size: 28),
                                      onPressed: () => _showApproveDialog(d),
                                    ),
                              onTap: () => _showApproveDialog(d),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _DeviceRow {
  final String deviceId;
  final String mac;
  final String appName;
  final String status;
  final Map<String, dynamic>? listData;
  final String? approvedAt;
  final String? createdAt;

  _DeviceRow({
    required this.deviceId,
    required this.mac,
    required this.appName,
    required this.status,
    this.listData,
    this.approvedAt,
    this.createdAt,
  });

  factory _DeviceRow.fromJson(Map<String, dynamic> json) {
    final rawList = json['list_data'];
    return _DeviceRow(
      deviceId: json['device_id'] as String? ?? '',
      mac: json['mac'] as String? ?? '',
      appName: json['app_name'] as String? ?? 'McPlayer',
      status: json['status'] as String? ?? 'pending',
      listData: rawList is Map ? Map<String, dynamic>.from(rawList) : null,
      approvedAt: json['approved_at'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}
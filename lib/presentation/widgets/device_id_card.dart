import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

/// Card com ID do aparelho + MAC virtual, para ativação no provedor.
/// Valores gerados uma única vez e persistidos (sobrevivem ao logout).
class DeviceIdCard extends StatelessWidget {
  final String deviceId;
  final String mac;

  const DeviceIdCard({
    super.key,
    required this.deviceId,
    required this.mac,
  });

  void _copy(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copiado: $value'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.devices_rounded, color: AppColors.primary, size: 16),
              SizedBox(width: 8),
              Text(
                'IDENTIFICAÇÃO DO APARELHO',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _row(context, 'MAC', mac),
          const SizedBox(height: 6),
          _row(context, 'ID', deviceId),
          const SizedBox(height: 6),
          const Text(
            'Informe ao seu provedor para ativar a assinatura.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 30,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _copy(context, label, value),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.copy_rounded, color: AppColors.primary, size: 18),
          ),
        ),
      ],
    );
  }
}

/// Diálogo reutilizável com a identificação (usado na Home).
void showDeviceIdDialog(BuildContext context, String deviceId, String mac) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Meu aparelho', style: TextStyle(color: Colors.white)),
      content: DeviceIdCard(deviceId: deviceId, mac: mac),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar', style: TextStyle(color: AppColors.primary)),
        ),
      ],
    ),
  );
}

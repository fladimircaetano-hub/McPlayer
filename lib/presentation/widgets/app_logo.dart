import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Logo McPlayer em texto (sem asset): marca em gradiente + nome.
/// Se você tiver um PNG da sua logo, me envie que eu plugo em assets/.
class AppLogo extends StatelessWidget {
  final double iconSize;
  final double titleSize;
  final bool showSubtitle;

  const AppLogo({
    super.key,
    this.iconSize = 56,
    this.titleSize = 34,
    this.showSubtitle = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: iconSize,
          height: iconSize,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(iconSize * 0.32),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.black,
            size: iconSize * 0.6,
          ),
        ),
        SizedBox(width: iconSize * 0.28),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'MCPLAYER',
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: Colors.white,
              ),
            ),
            if (showSubtitle)
              Text(
                'S T R E A M I N G',
                style: TextStyle(
                  fontSize: titleSize * 0.32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

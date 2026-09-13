import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../controllers/iptv_controller.dart';
import '../widgets/app_logo.dart';
import 'home_screen.dart';
import 'lists_screen.dart';

class SplashScreen extends StatefulWidget {
  final IptvController controller;

  const SplashScreen({super.key, required this.controller});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );

    _animController.forward();
    _checkSavedSession();
  }

  Future<void> _checkSavedSession() async {
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;

    final savedAccount = widget.controller.storageService.getXtreamAccount();
    if (savedAccount != null) {
      final success = await widget.controller.loginXtream(
        serverUrl: savedAccount.serverUrl,
        username: savedAccount.username,
        password: savedAccount.password,
      );
      if (success && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomeScreen(controller: widget.controller)),
        );
        return;
      }
    }

    final lastUrl = widget.controller.storageService.getLastM3uUrl();
    if (lastUrl != null && lastUrl.isNotEmpty) {
      final success = await widget.controller.loadFromM3uUrl(lastUrl);
      if (success && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomeScreen(controller: widget.controller)),
        );
        return;
      }
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ListsScreen(controller: widget.controller)),
      );
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(iconSize: 84, titleSize: 36),
                const SizedBox(height: 36),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

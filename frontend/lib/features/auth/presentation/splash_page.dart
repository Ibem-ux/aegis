import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/secure_storage/secure_storage.dart';
import '../../../app/theme.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final SecureStorage _storage = SecureStorage();

  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    // Artificial delay to show premium branding splash
    await Future<void>.delayed(const Duration(seconds: 2));

    final token = await _storage.getAccessToken();
    if (mounted) {
      if (token != null) {
        context.go('/home');
      } else {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AegisTheme.backgroundGradient,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Premium logo styling
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AegisTheme.cardColor.withOpacity(0.4),
                  shape: BoxShape.circle,
                  border: Border.all(color: AegisTheme.accentBlue.withOpacity(0.3), width: 1.5),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  size: 80,
                  color: AegisTheme.accentCyan,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'AEGIS',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  letterSpacing: 8.0,
                  color: AegisTheme.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'SECURE COMMUNICATION NODE',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  letterSpacing: 2.0,
                  color: AegisTheme.accentBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 64),
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3.0,
                  valueColor: AlwaysStoppedAnimation<Color>(AegisTheme.accentCyan),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

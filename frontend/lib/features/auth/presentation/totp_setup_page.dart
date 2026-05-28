import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'auth_providers.dart';
import '../../../app/theme.dart';

class TotpSetupPage extends ConsumerStatefulWidget {
  const TotpSetupPage({super.key});

  @override
  ConsumerState<TotpSetupPage> createState() => _TotpSetupPageState();
}

class _TotpSetupPageState extends ConsumerState<TotpSetupPage> {
  final _codeController = TextEditingController();
  String? _secret;
  String? _qrCodeBase64;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchQrDetails();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _fetchQrDetails() async {
    setState(() => _isLoading = true);
    try {
      final response = await ref.read(apiClientProvider).dio.post<Map<String, dynamic>>('/auth/2fa/setup');
      
      final data = response.data as Map<String, dynamic>;
      setState(() {
        _secret = data['secret'] as String;
        _qrCodeBase64 = data['qrCode'] as String; // Expecting data URL
      });
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load 2FA details from server');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _verifySetup() async {
    if (_codeController.text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final repository = ref.read(authRepositoryProvider);
      await repository.verify2FA(code: _codeController.text.trim());
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('2FA enabled successfully!')),
        );
        context.go('/home');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Verification failed. Double check your code.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup 2FA'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Secure Your Account',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Scan this QR code with Google Authenticator or any TOTP client to configure 2-factor authentication.',
              style: TextStyle(color: AegisTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_qrCodeBase64 != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Image.network(
                    _qrCodeBase64!, // In production this is the data URL
                    width: 200,
                    height: 200,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.qr_code, size: 200, color: Colors.black);
                    },
                  ),
                ),
              ),
            if (_secret != null) ...[
              const SizedBox(height: 24),
              SelectableText(
                'Secret Key: $_secret',
                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 32),
            TextFormField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: 'Enter 6-Digit Code',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _verifySetup,
              child: const Text('Enable 2FA'),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: AegisTheme.errorRed),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

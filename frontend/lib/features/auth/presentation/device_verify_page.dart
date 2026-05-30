import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme.dart';

class DeviceVerifyPage extends StatelessWidget {
  final String deviceId;

  const DeviceVerifyPage({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AegisTheme.backgroundGradient,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.phonelink_lock_outlined,
                    size: 64,
                    color: AegisTheme.accentCyan,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Device Verification',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This device is untrusted. An existing trusted device or administrator must approve this connection request.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AegisTheme.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AegisTheme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AegisTheme.accentBlue.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'YOUR DEVICE ID',
                          style: TextStyle(fontSize: 12, color: AegisTheme.textSecondary, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          deviceId,
                          style: const TextStyle(fontSize: 15, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: AegisTheme.textPrimary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: deviceId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Device ID copied to clipboard')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy ID'),
                          style: TextButton.styleFrom(foregroundColor: AegisTheme.accentCyan),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  ElevatedButton(
                    onPressed: () {
                      // Navigate back to login, prompting a retry which checks trust
                      context.go('/login');
                    },
                    child: const Text('Check Trust & Retry'),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Cancel', style: TextStyle(color: AegisTheme.textSecondary)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

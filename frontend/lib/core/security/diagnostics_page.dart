import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'capture_guard.dart';
import 'device_integrity.dart';
import '../../features/messages/widgets/watermark_overlay.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  bool _isSecureMode = false;
  bool _isCompromised = false;
  
  @override
  void initState() {
    super.initState();
    _loadState();
  }
  
  Future<void> _loadState() async {
    final secureMode = await CaptureGuard.instance.isSecureModeEnabled();
    final compromised = await DeviceIntegrity.instance.isCompromised();
    if (mounted) {
      setState(() {
        _isSecureMode = secureMode;
        _isCompromised = compromised;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('Debug only')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Anti-Capture Diagnostics')),
      body: WatermarkOverlay(
        label: 'TEST-USER-123',
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              title: const Text('FLAG_SECURE State'),
              subtitle: Text(_isSecureMode ? 'Applied' : 'Not Applied'),
              trailing: ElevatedButton(
                onPressed: () async {
                  if (_isSecureMode) {
                    await CaptureGuard.instance.disableSecureMode();
                  } else {
                    await CaptureGuard.instance.enableSecureMode();
                  }
                  await _loadState();
                },
                child: const Text('Toggle'),
              ),
            ),
            ListTile(
              title: const Text('Device Integrity (Root/Jailbreak)'),
              subtitle: Text(_isCompromised ? 'Compromised (Rooted/Jailbroken)' : 'Clean (Not Compromised)'),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadState,
              ),
            ),
            const ListTile(
              title: Text('Watermark Overlay'),
              subtitle: Text('Enabled. Current text: "TEST-USER-123" (visible in background)'),
            ),
            const ListTile(
              title: Text('Secure Media Loader Mode'),
              subtitle: Text('In-memory only. No disk persistence.'),
            ),
          ],
        ),
      ),
    );
  }
}

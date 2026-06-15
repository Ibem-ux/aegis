import 'dart:ui';
import 'package:flutter/material.dart';
import '../../features/messages/widgets/watermark_overlay.dart';
import 'capture_guard.dart';

class SecureScreen extends StatefulWidget {
  final Widget child;
  final String watermarkLabel;

  const SecureScreen({
    super.key,
    required this.child,
    required this.watermarkLabel,
  });

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> with WidgetsBindingObserver {
  bool _isBackgrounded = false;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CaptureGuard.instance.enableSecureMode();
    
    CaptureGuard.instance.events.listen((event) {
      if (!mounted) return;
      if (event == 'screenshot') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Screenshot detected. This action is logged.')),
        );
      } else if (event == 'recording_started') {
        setState(() => _isRecording = true);
      } else if (event == 'recording_stopped') {
        setState(() => _isRecording = false);
      }
    });

    _checkInitialCapture();
  }

  Future<void> _checkInitialCapture() async {
    final captured = await CaptureGuard.instance.isBeingCaptured();
    if (mounted && captured != _isRecording) {
      setState(() => _isRecording = captured);
    }
  }

  @override
  void dispose() {
    CaptureGuard.instance.disableSecureMode();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _isBackgrounded = state == AppLifecycleState.paused || 
                        state == AppLifecycleState.inactive || 
                        state == AppLifecycleState.hidden;
    });
  }

  @override
  Widget build(BuildContext context) {
    final obscure = _isBackgrounded || _isRecording;

    return WatermarkOverlay(
      label: widget.watermarkLabel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (obscure)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  alignment: Alignment.center,
                  child: const Icon(Icons.security, size: 64, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

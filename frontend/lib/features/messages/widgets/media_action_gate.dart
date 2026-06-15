import 'package:flutter/material.dart';

class AegisCapabilities {
  final bool isOwner;
  final bool isAdmin;
  final bool isSuperUser;

  const AegisCapabilities({
    this.isOwner = false,
    this.isAdmin = false,
    this.isSuperUser = false,
  });

  bool get canExportMedia => isOwner || isSuperUser;

  static const user = AegisCapabilities();
}

abstract class CapabilityProvider {
  AegisCapabilities getCapabilities();
}

class StubUserCapabilityProvider implements CapabilityProvider {
  @override
  AegisCapabilities getCapabilities() => AegisCapabilities.user;
}

class MediaActionGate extends StatelessWidget {
  final AegisCapabilities capabilities;
  final Widget allowed;
  final Widget? denied;

  const MediaActionGate({
    super.key,
    required this.capabilities,
    required this.allowed,
    this.denied,
  });

  @override
  Widget build(BuildContext context) {
    if (capabilities.canExportMedia) {
      return allowed;
    }
    return denied ?? const SizedBox.shrink();
  }
}

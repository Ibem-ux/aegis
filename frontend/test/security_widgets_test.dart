import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_chat/features/messages/widgets/watermark_overlay.dart';
import 'package:aegis_chat/features/messages/widgets/media_action_gate.dart';

void main() {
  group('WatermarkOverlay Tests', () {
    testWidgets('renders child widget and watermark overlay', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WatermarkOverlay(
              label: 'TEST-WATERMARK',
              child: Text('Protected Content'),
            ),
          ),
        ),
      );

      // Verify child is rendered
      expect(find.text('Protected Content'), findsOneWidget);

      // Verify the CustomPaint that draws the watermark is present
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('MediaActionGate Tests', () {
    testWidgets('shows allowed widget when user can export media', (WidgetTester tester) async {
      const capabilities = AegisCapabilities(isOwner: true);
      
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaActionGate(
              capabilities: capabilities,
              allowed: Text('Allowed Action'),
              denied: Text('Denied Action'),
            ),
          ),
        ),
      );

      expect(find.text('Allowed Action'), findsOneWidget);
      expect(find.text('Denied Action'), findsNothing);
    });

    testWidgets('shows denied widget when user cannot export media', (WidgetTester tester) async {
      const capabilities = AegisCapabilities(isOwner: false, isSuperUser: false);
      
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaActionGate(
              capabilities: capabilities,
              allowed: Text('Allowed Action'),
              denied: Text('Denied Action'),
            ),
          ),
        ),
      );

      expect(find.text('Allowed Action'), findsNothing);
      expect(find.text('Denied Action'), findsOneWidget);
    });
    
    testWidgets('shows SizedBox.shrink when denied widget is null', (WidgetTester tester) async {
      const capabilities = AegisCapabilities(isOwner: false, isSuperUser: false);
      
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaActionGate(
              capabilities: capabilities,
              allowed: Text('Allowed Action'),
            ),
          ),
        ),
      );

      expect(find.text('Allowed Action'), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    });
  });
}

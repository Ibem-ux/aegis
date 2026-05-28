import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Temporarily import placeholders which we will define in features
import '../features/auth/presentation/splash_page.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/register_page.dart';
import '../features/auth/presentation/totp_setup_page.dart';
import '../features/auth/presentation/totp_verify_page.dart';
import '../features/auth/presentation/device_verify_page.dart';
import '../features/chats/presentation/home_page.dart';
import '../features/messages/presentation/chat_room_page.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        return const SplashPage();
      },
    ),
    GoRoute(
      path: '/login',
      builder: (BuildContext context, GoRouterState state) {
        return const LoginPage();
      },
    ),
    GoRoute(
      path: '/register',
      builder: (BuildContext context, GoRouterState state) {
        final code = state.uri.queryParameters['code'] ?? '';
        return RegisterPage(inviteCode: code);
      },
    ),
    GoRoute(
      path: '/totp-setup',
      builder: (BuildContext context, GoRouterState state) {
        return const TotpSetupPage();
      },
    ),
    GoRoute(
      path: '/totp-verify',
      builder: (BuildContext context, GoRouterState state) {
        final tempToken = state.uri.queryParameters['tempToken'] ?? '';
        return TotpVerifyPage(tempToken: tempToken);
      },
    ),
    GoRoute(
      path: '/device-verify',
      builder: (BuildContext context, GoRouterState state) {
        final deviceId = state.uri.queryParameters['deviceId'] ?? '';
        return DeviceVerifyPage(deviceId: deviceId);
      },
    ),
    GoRoute(
      path: '/home',
      builder: (BuildContext context, GoRouterState state) {
        return const HomePage();
      },
    ),
    GoRoute(
      path: '/chat/:chatId',
      builder: (BuildContext context, GoRouterState state) {
        final chatId = state.pathParameters['chatId']!;
        final recipientName = state.uri.queryParameters['name'] ?? 'Chat';
        return ChatRoomPage(chatId: chatId, recipientName: recipientName);
      },
    ),
  ],
);

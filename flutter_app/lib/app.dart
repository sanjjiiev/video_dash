import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'core/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/home/screens/home_screen.dart';
import 'features/player/screens/player_screen.dart';
import 'features/search/screens/search_screen.dart';
import 'features/shorts/screens/shorts_screen.dart';
import 'features/upload/screens/upload_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'shared/screens/splash_screen.dart';
import 'shared/screens/main_shell.dart';
// Phase 4
import 'features/downloads/screens/downloads_screen.dart';
import 'features/analytics/screens/analytics_dashboard.dart';
import 'features/subscriptions/screens/subscriptions_screen.dart';

// ── Router ────────────────────────────────────────────────────────────────────
final _routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final isLoggedIn  = authState.value?.isLoggedIn ?? false;
      final isAuthRoute = state.matchedLocation == '/login' ||
                          state.matchedLocation == '/register';

      if (!isLoggedIn && !isAuthRoute) return '/login';
      if (isLoggedIn  &&  isAuthRoute) return '/';
      return null;
    },
    routes: [
      // ── Auth ───────────────────────────────────────────────────────────
      GoRoute(path: '/login',    builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),

      // ── Main shell (bottom nav stays persistent) ─────────────────────
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/shorts',
            pageBuilder: (context, state) => const NoTransitionPage(child: ShortsScreen()),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (context, state) => NoTransitionPage(
              child: SearchScreen(initialQuery: state.uri.queryParameters['q']),
            ),
          ),
          GoRoute(
            path: '/upload',
            pageBuilder: (context, state) => const NoTransitionPage(child: UploadScreen()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => const NoTransitionPage(child: ProfileScreen()),
          ),
          // ── Phase 4 routes (inside shell) ─────────────────────────────
          GoRoute(
            path: '/downloads',
            pageBuilder: (_, __) => const NoTransitionPage(child: DownloadsScreen()),
          ),
          GoRoute(
            path: '/analytics',
            pageBuilder: (_, __) => const NoTransitionPage(child: AnalyticsDashboard()),
          ),
          GoRoute(
            path: '/subscriptions',
            pageBuilder: (_, __) => const NoTransitionPage(child: SubscriptionsScreen()),
          ),
        ],
      ),

      // ── Video Player (full screen, outside shell) ─────────────────────
      GoRoute(
        path: '/video/:id',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['id']!;
          return CustomTransitionPage(
            transitionDuration: const Duration(milliseconds: 300),
            child: PlayerScreen(videoId: videoId),
            transitionsBuilder: (_, animation, __, child) {
              return SlideTransition(
                position: Tween(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                child: child,
              );
            },
          );
        },
      ),

      // ── Local file player (offline playback) ──────────────────────────
      GoRoute(
        path: '/video/local',
        pageBuilder: (context, state) {
          final extra    = state.extra as Map<String, dynamic>? ?? {};
          final filePath = extra['filePath'] as String? ?? '';
          return CustomTransitionPage(
            transitionDuration: const Duration(milliseconds: 300),
            child: PlayerScreen(videoId: '', localFilePath: filePath),
            transitionsBuilder: (_, animation, __, child) {
              return SlideTransition(
                position: Tween(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                    parent: animation, curve: Curves.easeOutCubic)),
                child: child,
              );
            },
          );
        },
      ),
    ],
  );
});

// ── App Root ──────────────────────────────────────────────────────────────────
class HubApp extends ConsumerWidget {
  const HubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);

    // Lock to portrait initially; player overrides to landscape on fullscreen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    return MaterialApp.router(
      title: 'HUB 2.0',
      debugShowCheckedModeBanner: false,
      theme:      AppTheme.light,
      darkTheme:  AppTheme.dark,
      themeMode:  ThemeMode.dark,   // default to dark; user can toggle in profile
      routerConfig: router,
    );
  }
}

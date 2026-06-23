import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/storage.dart';
import 'providers/auth_provider.dart';
import 'providers/lock_provider.dart';
import 'screens/home_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/pin_setup_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/quiz_done_screen.dart';
import 'screens/quiz_list_screen.dart';
import 'screens/quiz_play_screen.dart';
import 'screens/quiz_prep_screen.dart';
import 'screens/settings_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);
  final locked = ref.watch(lockProvider);
  final storage = ref.watch(storageProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final isAuth = authState.status == AuthStatus.authenticated;
      final isOnboarded = storage.onboardingCompleted;
      final hasPin = storage.hasPin;
      final path = state.matchedLocation;

      if (!isOnboarded && path != '/onboarding') return '/onboarding';

      // /settings доступен и без авторизации — нужен для смены API URL,
      // когда дефолтный недоступен или указан неверно.
      if (!isAuth) {
        if (path == '/login' || path == '/onboarding' || path == '/settings') {
          return null;
        }
        return '/login';
      }

      // Авторизован, но приложение заблокировано (cold start / таймаут в фоне).
      if (locked) {
        if (hasPin) {
          // Быстрый вход по коду; пароль и настройки остаются доступны.
          if (path == '/lock' || path == '/login' || path == '/settings') {
            return null;
          }
          return '/lock';
        }
        // Кода нет — требуется вход по паролю.
        if (path == '/login' || path == '/settings') return null;
        return '/login';
      }

      // Авторизован и разблокирован — нет смысла оставаться на экранах входа.
      if (path == '/login' || path == '/onboarding' || path == '/lock') {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/lock',
        builder: (context, state) => const LockScreen(),
      ),
      GoRoute(
        path: '/pin-setup',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PinSetupScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => ScaffoldWithNav(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/quizzes',
            builder: (context, state) => const QuizListScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/quiz/:id/prep',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => QuizPrepScreen(
          quizId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/quiz/:id/play',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => QuizPlayScreen(
          quizId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/quiz/done',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const QuizDoneScreen(),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/change-password',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ChangePasswordScreen(),
      ),
    ],
  );
});

class ScaffoldWithNav extends StatelessWidget {
  final Widget child;
  const ScaffoldWithNav({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex(context),
        onDestinationSelected: (index) => _onTap(context, index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Главная',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Тесты',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/quizzes')) return 1;
    if (location.startsWith('/profile')) return 2;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/');
      case 1:
        context.go('/quizzes');
      case 2:
        context.go('/profile');
    }
  }
}

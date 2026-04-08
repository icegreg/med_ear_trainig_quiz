import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/storage.dart';
import 'providers/auth_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/quiz_done_screen.dart';
import 'screens/quiz_list_screen.dart';
import 'screens/quiz_play_screen.dart';
import 'screens/quiz_prep_screen.dart';
import 'screens/results_screen.dart';
import 'screens/settings_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);
  final storage = ref.watch(storageProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final isAuth = authState.status == AuthStatus.authenticated;
      final isOnboarded = storage.onboardingCompleted;
      final path = state.matchedLocation;

      if (!isOnboarded && path != '/onboarding') return '/onboarding';
      if (!isAuth && path != '/login' && path != '/onboarding') return '/login';
      if (isAuth && (path == '/login' || path == '/onboarding')) return '/';

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
            path: '/results',
            builder: (context, state) => const ResultsScreen(),
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
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Результаты',
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
    if (location.startsWith('/results')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/');
      case 1:
        context.go('/quizzes');
      case 2:
        context.go('/results');
      case 3:
        context.go('/profile');
    }
  }
}

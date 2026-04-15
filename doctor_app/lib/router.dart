import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/auth_provider.dart';
import 'providers/notifications_provider.dart';
import 'screens/add_patient_screen.dart';
import 'screens/audio_library_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/patient_detail_screen.dart';
import 'screens/patients_list_screen.dart';
import 'screens/quiz_list_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isAuth = auth.status == AuthStatus.authenticated;
      final isLoginRoute = state.matchedLocation == '/login';

      if (!isAuth && !isLoginRoute) return '/login';
      if (isAuth && isLoginRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => _ShellLayout(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/patients', builder: (_, __) => const PatientsListScreen()),
          GoRoute(
            path: '/patients/add',
            builder: (_, __) => const AddPatientScreen(),
          ),
          GoRoute(
            path: '/patients/:id',
            builder: (_, state) => PatientDetailScreen(
              patientId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(path: '/audio-library', builder: (_, __) => const AudioLibraryScreen()),
          GoRoute(path: '/quizzes', builder: (_, __) => const QuizListScreen()),
          GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
        ],
      ),
    ],
  );
});

class _ShellLayout extends ConsumerWidget {
  final Widget child;
  const _ShellLayout({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final unread = ref.watch(notificationsProvider).unreadCount;

    int selectedIndex;
    if (location == '/') {
      selectedIndex = 0;
    } else if (location.startsWith('/patients')) {
      selectedIndex = 1;
    } else if (location == '/audio-library') {
      selectedIndex = 2;
    } else if (location == '/quizzes') {
      selectedIndex = 3;
    } else if (location == '/notifications') {
      selectedIndex = 4;
    } else {
      selectedIndex = 0;
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: MediaQuery.of(context).size.width > 900,
            selectedIndex: selectedIndex,
            onDestinationSelected: (i) {
              const routes = ['/', '/patients', '/audio-library', '/quizzes', '/notifications'];
              context.go(routes[i]);
            },
            leading: Padding(
              padding: const EdgeInsets.all(16),
              child: Icon(
                Icons.hearing,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            destinations: [
              const NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Главная'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.people_outlined),
                selectedIcon: Icon(Icons.people),
                label: Text('Пациенты'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: Text('Аудио'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.quiz_outlined),
                selectedIcon: Icon(Icons.quiz),
                label: Text('Тесты'),
              ),
              NavigationRailDestination(
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Icons.notifications_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Icons.notifications),
                ),
                label: const Text('Уведомления'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

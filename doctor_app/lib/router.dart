import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/app_version_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/notifications_provider.dart';
import 'screens/add_patient_screen.dart';
import 'screens/audio_library_screen.dart';
import 'screens/create_quiz_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/patient_detail_screen.dart';
import 'screens/patients_list_screen.dart';
import 'screens/quiz_list_screen.dart';

/// Page transition duration. Flutter's default page transition is 300ms;
/// this runs it 30% faster (300ms → 210ms) while keeping the platform look.
const _kFastTransition = Duration(milliseconds: 210);

/// Wraps [child] in a page that uses the app's platform transition style but
/// at the faster [_kFastTransition] duration.
CustomTransitionPage<void> _fastPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: _kFastTransition,
    reverseTransitionDuration: _kFastTransition,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final route = ModalRoute.of(context)! as PageRoute<void>;
      return Theme.of(context).pageTransitionsTheme.buildTransitions<void>(
            route,
            context,
            animation,
            secondaryAnimation,
            child,
          );
    },
  );
}

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
      GoRoute(
        path: '/login',
        pageBuilder: (_, state) => _fastPage(state, const LoginScreen()),
      ),
      ShellRoute(
        builder: (context, state, child) => _ShellLayout(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (_, state) => _fastPage(state, const DashboardScreen()),
          ),
          GoRoute(
            path: '/patients',
            pageBuilder: (_, state) =>
                _fastPage(state, const PatientsListScreen()),
          ),
          GoRoute(
            path: '/patients/add',
            pageBuilder: (_, state) =>
                _fastPage(state, const AddPatientScreen()),
          ),
          GoRoute(
            path: '/patients/:id',
            pageBuilder: (_, state) => _fastPage(
              state,
              PatientDetailScreen(
                patientId: int.parse(state.pathParameters['id']!),
              ),
            ),
          ),
          GoRoute(
            path: '/audio-library',
            pageBuilder: (_, state) =>
                _fastPage(state, const AudioLibraryScreen()),
          ),
          GoRoute(
            path: '/quizzes',
            pageBuilder: (_, state) => _fastPage(state, const QuizListScreen()),
          ),
          GoRoute(
            path: '/quizzes/create',
            pageBuilder: (_, state) =>
                _fastPage(state, const CreateQuizScreen()),
          ),
          GoRoute(
            path: '/notifications',
            pageBuilder: (_, state) =>
                _fastPage(state, const NotificationsScreen()),
          ),
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
    } else if (location.startsWith('/quizzes')) {
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
            // Версия приложения — внизу слева, под навигацией.
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Consumer(
                    builder: (context, ref, _) {
                      final version = ref.watch(appVersionProvider);
                      return Text(
                        version.maybeWhen(
                          data: (v) => 'v$v',
                          orElse: () => '',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

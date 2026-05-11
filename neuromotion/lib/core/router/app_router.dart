import 'package:go_router/go_router.dart';

import '../../features/capture/capture_page.dart';
import '../../features/dashboard/dashboard_page.dart';
import '../../features/processing/processing_page.dart';
import '../../features/results/results_page.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const DashboardPage(),
      ),
      GoRoute(
        path: '/capture',
        builder: (context, state) => const CapturePage(),
      ),
      GoRoute(
        path: '/processing',
        builder: (context, state) {
          final payload = state.extra as Map<String, dynamic>? ?? {};
          return ProcessingPage(
            jobId: payload['jobId'] as String? ?? '',
            videoPath: payload['videoPath'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/results',
        builder: (context, state) {
          final payload = state.extra as Map<String, dynamic>? ?? {};
          return ResultsPage(
            jobId: payload['jobId'] as String? ?? '',
            videoPath: payload['videoPath'] as String?,
          );
        },
      ),
    ],
  );
}

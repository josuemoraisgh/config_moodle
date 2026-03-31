import 'package:go_router/go_router.dart';
import 'package:config_moodle/presentation/pages/home_page.dart';
import 'package:config_moodle/presentation/pages/table_editor_page.dart';
import 'package:config_moodle/presentation/pages/sync_preview_page.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/editor/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return TableEditorPage(courseConfigId: id);
        },
      ),
      GoRoute(
        path: '/sync/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return SyncPreviewPage(courseConfigId: id);
        },
      ),
    ],
  );
}

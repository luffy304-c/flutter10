import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'database/app_database.dart';
import 'presentation/home_screen.dart';
import 'repositories/attachment_repository.dart';
import 'repositories/comment_repository.dart';
import 'repositories/project_repository.dart';
import 'repositories/stats_repository.dart';
import 'repositories/task_repository.dart';
import 'repositories/user_repository.dart';
import 'services/attachment_storage.dart';
import 'services/benchmark_service.dart';
import 'services/demo_data.dart';
import 'state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.file('taskflow.sqlite');
  runApp(_Bootstrap(db: db));
}

/// Заставка, пока БД готовится: демо-данные и добивка до 1000/100/10 000.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap({required this.db});
  final AppDatabase db;

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<void> _ready = _init();
  String _stage = 'Открываем базу…';

  Future<void> _init() async {
    await DemoData.seedIfEmpty(widget.db);
    await BenchmarkService(widget.db).ensureTargetScale(onProgress: (s) {
      if (mounted) setState(() => _stage = 'Готовим данные: $s');
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _ready,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.done && !snap.hasError) {
            return TaskFlowApp(db: widget.db);
          }
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: snap.hasError
                    ? Text('Ошибка: ${snap.error}')
                    : Column(mainAxisSize: MainAxisSize.min, children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(_stage),
                        const SizedBox(height: 4),
                        const Text('1000 пользователей · 100 проектов · 10 000 задач'),
                        const Text('(только при первом запуске)'),
                      ]),
              ),
            ),
          );
        },
      );
}

class TaskFlowApp extends StatelessWidget {
  const TaskFlowApp({super.key, required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    final projects = ProjectRepository(db);
    final users = UserRepository(db);
    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        Provider<UserRepository>.value(value: users),
        Provider<ProjectRepository>.value(value: projects),
        Provider<TaskRepository>.value(value: TaskRepository(db)),
        Provider<CommentRepository>.value(value: CommentRepository(db)),
        Provider<AttachmentRepository>.value(value: AttachmentRepository(db)),
        Provider<StatsRepository>.value(value: StatsRepository(db, projects)),
        Provider<AttachmentStorage>.value(value: AttachmentStorage()),
        ChangeNotifierProvider<AppController>(create: (_) => AppController(users)),
      ],
      child: MaterialApp(
        title: 'TaskFlow',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
          cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(vertical: 5)),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

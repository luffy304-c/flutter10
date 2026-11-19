import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/database/app_database.dart';
import 'package:taskflow/main.dart';
import 'package:taskflow/services/demo_data.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<AppDatabase> start(WidgetTester t) async {
    t.view.physicalSize = const Size(1000, 3000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final db = AppDatabase.inMemory();
    await t.runAsync(() => DemoData.seedIfEmpty(db));
    await t.pumpWidget(TaskFlowApp(db: db));
    await settle(t);
    return db;
  }

  Future<void> finish(WidgetTester t, AppDatabase db) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2)); // дать Drift закрыть стримы
  }

  testWidgets('вкладка Проекты показывает демо-проекты с прогрессом', (t) async {
    final db = await start(t);
    expect(find.text('Сайт компании'), findsOneWidget);
    expect(find.text('Мобильное приложение'), findsOneWidget);
    expect(find.textContaining('задач: 4'), findsOneWidget);
    await finish(t, db);
  });

  testWidgets('вкладка Задачи: поиск фильтрует список', (t) async {
    final db = await start(t);
    await t.tap(find.text('Задачи').last);
    await settle(t);
    expect(find.text('Макет главной страницы'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'шапки');
    await settle(t);
    expect(find.text('Вёрстка шапки'), findsOneWidget);
    expect(find.text('Макет главной страницы'), findsNothing);
    await finish(t, db);
  });

  testWidgets('вкладка Статистика показывает счётчики', (t) async {
    final db = await start(t);
    await t.tap(find.text('Статистика').last);
    await settle(t);
    expect(find.text('Всего задач'), findsOneWidget);
    expect(find.text('6'), findsWidgets);
    expect(find.text('Просрочено'), findsOneWidget);
    await finish(t, db);
  });

  testWidgets('создание пользователя через диалог и ошибка дубликата', (t) async {
    final db = await start(t);
    await t.tap(find.text('Люди').last);
    await settle(t);
    Future<void> add(String name, String email) async {
      await t.tap(find.text('Пользователь'));
      await settle(t);
      await t.enterText(find.byType(TextField).at(0), name);
      await t.enterText(find.byType(TextField).at(1), email);
      await t.tap(find.text('Сохранить'));
      await settle(t);
    }

    await add('Пётр Новый', 'petr@test.io');
    expect(find.text('Пётр Новый'), findsOneWidget);
    await add('Другой', 'petr@test.io'); // тот же email
    expect(find.textContaining('уже существует'), findsWidgets);
    await finish(t, db);
  });

  testWidgets('карточка задачи: смена статуса и Undo меняют историю', (t) async {
    final db = await start(t);
    await t.tap(find.text('Задачи').last);
    await settle(t);
    await t.tap(find.text('Вёрстка шапки'));
    await settle(t);
    await t.tap(find.text('Завершена').first);
    await settle(t);
    expect(find.textContaining('К выполнению → Завершена'), findsWidgets);
    await t.tap(find.textContaining('Отменить:'));
    await settle(t);
    expect(find.textContaining('отменено'), findsOneWidget);
    await finish(t, db);
  });
}

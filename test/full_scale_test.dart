import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/database/app_database.dart';
import 'package:taskflow/models/enums.dart';
import 'package:taskflow/models/views.dart';
import 'package:taskflow/repositories/task_repository.dart';
import 'package:taskflow/models/app_exception.dart';
import 'package:taskflow/repositories/project_repository.dart';
import 'package:taskflow/repositories/user_repository.dart';
import 'package:taskflow/services/benchmark_service.dart';
import 'package:taskflow/services/demo_data.dart';

Future<int> _count(AppDatabase db, String table) async =>
    (await db.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle()).read<int>('c');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('полный объём: 1000 пользователей, 100 проектов, 10000 задач + индексы',
      () async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final bench = BenchmarkService(db);
    final sw = Stopwatch()..start();
    await bench.seed(); // по умолчанию 1000 / 100 / 10000
    // ignore: avoid_print
    print('seed: ${sw.elapsedMilliseconds} мс');

    expect(await _count(db, 'users'), 1000);
    expect(await _count(db, 'projects'), 100);
    expect(await _count(db, 'tasks'), 10000);
    // ignore: avoid_print
    print('project_members: ${await _count(db, 'project_members')}');

    final repo = TaskRepository(db);
    // пагинация на большом объёме
    final p1 = await repo.getPage(const TaskFilter(), limit: 50, offset: 0);
    final p2 = await repo.getPage(const TaskFilter(), limit: 50, offset: 50);
    expect(p1.length, 50);
    expect(p2.length, 50);
    expect(p1.first.task.id, isNot(p2.first.task.id));
    expect(await repo.count(const TaskFilter()), 10000);
    // поиск, фильтр, сортировка
    expect((await repo.getPage(const TaskFilter(search: 'отчёт'))).isNotEmpty, isTrue);
    expect(
        (await repo.getPage(TaskFilter(
                status: TaskStatus.done, priority: TaskPriority.high)))
            .every((t) =>
                t.task.status == TaskStatus.done &&
                t.task.priority == TaskPriority.high),
        isTrue);

    final results = await bench.run(repeats: 5);
    for (final r in results) {
      // ignore: avoid_print
      print('${r.name.padRight(52)} без: ${r.withoutIndexMs.toStringAsFixed(2).padLeft(8)} мс | с: ${r.withIndexMs.toStringAsFixed(2).padLeft(8)} мс | ${r.speedup.toStringAsFixed(1)}x');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('при запуске БД добивается ровно до 1000/100/10000 и всё работает',
      () async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    await DemoData.seedIfEmpty(db); // как при первом запуске приложения
    final bench = BenchmarkService(db);
    await bench.ensureTargetScale();
    expect(await _count(db, 'users'), 1000);
    expect(await _count(db, 'projects'), 100);
    expect(await _count(db, 'tasks'), 10000);
    await bench.ensureTargetScale(); // повторный запуск ничего не добавляет
    expect(await _count(db, 'tasks'), 10000);
    expect(await _count(db, 'users'), 1000);
    // у каждой новой задачи есть запись истории
    expect(await _count(db, 'task_history') >= 10000, isTrue);

    final tasks = TaskRepository(db);
    final projects = ProjectRepository(db);
    final users = UserRepository(db);

    // выбираем проект с участниками
    final pid = (await db.customSelect(
            'SELECT project_id AS p FROM project_members GROUP BY project_id HAVING COUNT(*) >= 5 LIMIT 1 OFFSET 10')
        .getSingle())
        .read<int>('p');
    final members = await projects.getMembers(pid);
    expect(members.length, greaterThanOrEqualTo(5));

    // создание и назначение (дедлайн в далёком будущем — лимит не мешает)
    final far = DateTime(2040, 1, 1, 12);
    final t = await tasks.createTask(
        title: 'Новая на большой базе',
        projectId: pid,
        assigneeId: members[0].user.id,
        deadline: far,
        actorId: members[0].user.id);
    await tasks.reassign(t, members[1].user.id, actorId: members[0].user.id);
    expect((await tasks.getById(t))!.assigneeId, members[1].user.id);
    await tasks.changeStatus(t, TaskStatus.inProgress, actorId: members[1].user.id);
    await tasks.undoLastStatusChange(t, actorId: members[1].user.id);
    expect((await tasks.getById(t))!.status, TaskStatus.todo);

    // чужого пользователя назначить нельзя
    final outsider = (await projects.usersNotInProject(pid)).first;
    await expectLater(
        tasks.reassign(t, outsider.id), throwsA(isA<AppException>()));
    // добавить в проект -> теперь можно; удалить из проекта -> нельзя, пока есть задача
    await projects.addMember(pid, outsider.id);
    await tasks.reassign(t, outsider.id);
    await expectLater(projects.removeMember(pid, outsider.id),
        throwsA(isA<AppException>()));
    await expectLater(users.delete(outsider.id), throwsA(isA<AppException>()));
    // завершили задачу -> можно убрать из проекта
    await tasks.changeStatus(t, TaskStatus.done);
    await tasks.reassign(t, members[1].user.id);
    await projects.removeMember(pid, outsider.id);

    // удаление / корзина
    await tasks.softDelete(t);
    expect(await tasks.count(const TaskFilter()), 10000);
    expect(await tasks.count(const TaskFilter(onlyDeleted: true)), 1);
    await tasks.restore(t);
    expect(await tasks.count(const TaskFilter()), 10001);

    // лимит 3 задачи в день на большой базе
    final who = members[2].user.id;
    for (var i = 0; i < 3; i++) {
      await tasks.createTask(
          title: 'L$i', projectId: pid, assigneeId: who,
          deadline: DateTime(2041, 2, 2, 10 + i));
    }
    await expectLater(
        tasks.createTask(title: 'L4', projectId: pid, assigneeId: who,
            deadline: DateTime(2041, 2, 2, 20)),
        throwsA(isA<AppException>()));

    // новый пользователь: создаётся и удаляется
    final nu = await users.create(name: 'Новый', email: 'new@big.io');
    await users.delete(nu);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

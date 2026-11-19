import '../database/app_database.dart';
import '../models/enums.dart';
import '../repositories/project_repository.dart';
import '../repositories/task_repository.dart';
import '../repositories/user_repository.dart';

/// Небольшой набор демонстрационных данных при первом запуске.
class DemoData {
  static Future<void> seedIfEmpty(AppDatabase db) async {
    final users = UserRepository(db);
    if ((await users.getAll()).isNotEmpty) return;
    final projects = ProjectRepository(db);
    final tasks = TaskRepository(db);

    final anna = await users.create(name: 'Анна Смирнова', email: 'anna@taskflow.app');
    final ivan = await users.create(name: 'Иван Петров', email: 'ivan@taskflow.app');
    final olga = await users.create(name: 'Ольга Козлова', email: 'olga@taskflow.app');

    final site = await projects.create(
        name: 'Сайт компании', description: 'Редизайн корпоративного сайта');
    final app = await projects.create(
        name: 'Мобильное приложение', description: 'TaskFlow для iOS');
    await projects.addMember(site, anna, role: MemberRole.owner);
    await projects.addMember(site, ivan, role: MemberRole.admin);
    await projects.addMember(site, olga);
    await projects.addMember(app, ivan, role: MemberRole.owner);
    await projects.addMember(app, olga);

    final today = DateTime.now();
    DateTime day(int d) => DateTime(today.year, today.month, today.day + d, 18);
    Future<int> t(String title, int project, int? who, TaskPriority p, TaskStatus s,
            DateTime? due, String desc) =>
        tasks.createTask(
            title: title,
            description: desc,
            projectId: project,
            assigneeId: who,
            priority: p,
            status: s,
            deadline: due,
            actorId: anna);

    await t('Макет главной страницы', site, anna, TaskPriority.high,
        TaskStatus.inProgress, day(2), 'Подготовить макет в Figma');
    await t('Вёрстка шапки', site, ivan, TaskPriority.medium, TaskStatus.todo,
        day(5), 'Адаптивная шапка сайта');
    final done = await t('Согласовать палитру', site, olga, TaskPriority.low,
        TaskStatus.todo, day(-3), 'Цвета и шрифты');
    await tasks.changeStatus(done, TaskStatus.done, actorId: olga);
    await t('Просроченный отчёт', site, ivan, TaskPriority.critical, TaskStatus.todo,
        day(-2), 'Отчёт по аналитике за квартал');
    await t('Настроить базу Drift', app, ivan, TaskPriority.critical,
        TaskStatus.inProgress, day(1), 'Схема, миграции, репозитории');
    await t('Экран статистики', app, olga, TaskPriority.medium, TaskStatus.todo,
        day(7), 'Dashboard с SQL-агрегатами');
  }
}

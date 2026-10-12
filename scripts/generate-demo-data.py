#!/usr/bin/env python3
"""Генератор демо-данных Trace.

Создаёт в хранилище набор проектов, покрывающий все возможности приложения:
квартальные папки (26Q3/26Q4/27Q1), Completed Projects, все состояния,
просроченные/сегодняшние/предстоящие задачи, задачи без срока, теги,
иерархию эпик→проект→часть и задачу для проверки уведомлений (срок через
5 минут после запуска скрипта).

Использование:
    python3 scripts/generate-demo-data.py            # путь по умолчанию
    python3 scripts/generate-demo-data.py ~/Vault    # явный путь

ВНИМАНИЕ: удаляет всё содержимое папки Projects перед генерацией.
"""

import datetime as dt
import os
import shutil
import sys
import uuid

DEFAULT_VAULT = os.path.expanduser("~/Library/Application Support/Pulseboard/Vault")
# Сборки с App Sandbox (запуск из Xcode) держат хранилище в контейнере —
# если контейнер существует, по умолчанию пишем туда.
CONTAINER_VAULT = os.path.expanduser(
    "~/Library/Containers/app.pulseboard.local/Data/Library/Application Support/Pulseboard/Vault"
)

NOW = dt.datetime.now()
# Задача со сроком через 5 минут — проверка уведомлений сразу после запуска.
NOTIFY_AT = NOW + dt.timedelta(minutes=5)


def iso(date: dt.datetime) -> str:
    return date.strftime("%Y-%m-%dT%H:%M:%SZ")


def task_date(date: dt.datetime) -> str:
    return date.strftime("%Y-%m-%d")


def task_time(date: dt.datetime) -> str:
    return date.strftime("%H:%M")


def days_ago(n: int, hour=12, minute=0) -> dt.datetime:
    return NOW - dt.timedelta(days=n, hours=NOW.hour - hour, minutes=NOW.minute - minute)


def in_days(n: int, hour=12, minute=0) -> dt.datetime:
    return NOW + dt.timedelta(days=n) - dt.timedelta(hours=NOW.hour, minutes=NOW.minute) + dt.timedelta(hours=hour, minutes=minute)


def quarter(date: dt.datetime) -> str:
    return f"{date.year % 100:02d}Q{(date.month - 1) // 3 + 1}"


def encode(title, epic, parent, state, tags, created, updated, archived, description, tasks):
    task_lines = []
    for done, name, due in tasks:
        line = f"- [{'x' if done else ' '}] {name}"
        if due:
            line += f" 📅 {task_date(due)} ⏰ {task_time(due)}"
        task_lines.append(line)
    quoted = ", ".join(f'"{t}"' for t in tags)
    return (
        "---\n"
        "type: project\n"
        f"id: {uuid.uuid4()}\n"
        f'title: "{title}"\n'
        f'epic: "{epic}"\n'
        f'parent_project: "{parent}"\n'
        f"state: {state}\n"
        f"tags: [{quoted}]\n"
        f"created: {iso(created)}\n"
        f"updated: {iso(updated)}\n"
        f"archived: {str(archived).lower()}\n"
        "---\n"
        f"# {title}\n\n"
        "## Описание\n"
        f"{description}\n\n"
        "## Задачи\n"
        + "\n".join(task_lines)
        + "\n"
    )


# (slug, meta, tasks) — задачи: (выполнена, название, срок|None)
PROJECTS = [
    # --- 26Q4: активная работа ---
    dict(
        slug="redizayn-sayta",
        meta=dict(
            title="Редизайн сайта", epic="Продукт", parent="Маркетинг", state="active",
            tags=["дизайн", "срочно"], created=in_days(-9, 10, 0), updated=NOW - dt.timedelta(minutes=7),
            archived=False,
            description="Новый визуальный язык, главная и кабинета. Всё держится на макетах из Figma.",
        ),
        tasks=[
            (False, "Согласовать финальный макет главной", days_ago(5, 16, 0)),
            (False, "Отдать комментарии по второму экрану", days_ago(1, 11, 30)),
            (False, "Позвонить тест уведомлений", NOTIFY_AT),
            (False, "Собрать UI-кит для разработки", in_days(2, 14, 0)),
            (False, "Показать прототип команде", in_days(7, 11, 0)),
            (False, "Задача без срока — про запас", None),
            (True, "Выбрать шрифтовую пару", days_ago(8, 15, 0)),
            (True, "Прототип низкой детализации", days_ago(6, 18, 0)),
        ],
    ),
    dict(
        slug="api-avtorizacii",
        meta=dict(
            title="API авторизации", epic="Продукт", parent="Бэкенд", state="active",
            tags=["бэкенд"], created=in_days(-7, 9, 30), updated=NOW - dt.timedelta(hours=2),
            archived=False,
            description="Токены, refresh, ролевая модель. Всё по OpenAPI-схеме.",
        ),
        tasks=[
            (False, "Починить истечение refresh-токена", in_days(0, 17, 0)),
            (False, "Написать интеграционные тесты", in_days(3, 12, 0)),
            (False, "Задокументировать эндпоинты", in_days(14, 10, 0)),
            (True, "Схема базы для сессий", days_ago(4, 13, 0)),
        ],
    ),
    dict(
        slug="kurs-po-swiftui",
        meta=dict(
            title="Курс по SwiftUI", epic="Учёба", parent="", state="active",
            tags=["обучение", "ios"], created=in_days(-6, 20, 0), updated=NOW - dt.timedelta(hours=4),
            archived=False,
            description="Один модуль в неделю, конспекты — прямо здесь в Markdown.",
        ),
        tasks=[
            (True, "Модуль 1. Основы View", days_ago(6, 21, 0)),
            (True, "Модуль 2. Стеки и сетки", days_ago(5, 21, 0)),
            (True, "Модуль 3. Навигация", days_ago(4, 21, 0)),
            (True, "Модуль 4. Анимации", days_ago(3, 21, 0)),
            (True, "Модуль 5. Данные и Observable", days_ago(2, 21, 0)),
            (True, "Модуль 6. Жесты", days_ago(1, 21, 0)),
            (False, "Модуль 7. Макетирование", None),
            (False, "Финальный проект курса", None),
        ],
    ),
    dict(
        slug="sport-i-zdorove",
        meta=dict(
            title="Спорт и здоровье", epic="Личное", parent="", state="active",
            tags=[], created=in_days(-3, 8, 0), updated=NOW - dt.timedelta(hours=5),
            archived=False,
            description="Регулярность важнее интенсивности.",
        ),
        tasks=[
            (False, "Тренировка с тренером", in_days(1, 8, 30)),
            (False, "Сдать анализы", None),
            (False, "Перечитать конспект по питанию", None),
        ],
    ),
    dict(
        slug="planirovanie-2027",
        meta=dict(
            title="Планирование 2027", epic="Операции", parent="", state="planned",
            tags=["планы"], created=in_days(-1, 11, 0), updated=NOW - dt.timedelta(hours=3),
            archived=False,
            description="Бюджет, найм и цели на первый квартал.",
        ),
        tasks=[
            (False, "Собрать пожелания команды", None),
            (False, "Черновик бюджета", None),
        ],
    ),
    dict(
        slug="issledovanie-rynka",
        meta=dict(
            title="Исследование рынка", epic="Продукт", parent="Маркетинг", state="done",
            tags=[], created=in_days(-8, 14, 0), updated=NOW - dt.timedelta(days=2),
            archived=False,
            description="Конкуренты, сегменты, воронки — всё сложено в выводы.",
        ),
        tasks=[
            (True, "Таблица конкурентов", days_ago(9, 12, 0)),
            (True, "Интервью с пятью пользователями", days_ago(8, 12, 0)),
            (True, "Презентация выводов", days_ago(7, 12, 0)),
        ],
    ),
    # --- 26Q3: история ---
    dict(
        slug="migraciya-bazy",
        meta=dict(
            title="Миграция базы данных", epic="Продукт", parent="Бэкенд", state="blocked",
            tags=["инфраструктура"], created=in_days(-10, 10, 0), updated=NOW - dt.timedelta(days=1),
            archived=False,
            description="Переезд на новый кластер. Стоит из-за ожидания закупки железа.",
        ),
        tasks=[
            (False, "Согласовать окно простоя", days_ago(9, 10, 0)),
            (False, "Прогнать тестовый прогон", days_ago(3, 16, 0)),
            (False, "Обновить дашиборд мониторинга", in_days(5, 12, 0)),
            (True, "Экспорт схемы", in_days(-7, 12, 0)),
            (True, "План отката", in_days(-6, 12, 0)),
        ],
    ),
    dict(
        slug="naym-komandy",
        meta=dict(
            title="Найм команды", epic="Операции", parent="", state="on-hold",
            tags=["hr"], created=dt.datetime(2026, 9, 24, 9, 0), updated=NOW - dt.timedelta(days=2),
            archived=False,
            description="Два разработчика и дизайнер. Пауза до утверждения бюджета.",
        ),
        tasks=[
            (False, "Обновить вакансии", None),
            (True, "Собрать пайплайн собеседований", dt.datetime(2026, 9, 26, 12, 0)),
        ],
    ),
    dict(
        slug="diplom-magistratury",
        meta=dict(
            title="Диплом магистратуры", epic="Учёба", parent="", state="active",
            tags=["учёба", "важно"], created=dt.datetime(2026, 9, 26, 12, 0), updated=NOW - dt.timedelta(hours=1),
            archived=False,
            description="Тема: инструменты командной работы. Главы пишутся прямо в Obsidian.",
        ),
        tasks=[
            (False, "Отправить научруку главу 2", days_ago(1, 10, 0)),
            (False, "Свести таблицу по источникам", in_days(0, 20, 0)),
            (False, "Защита на кафедре", in_days(10, 9, 0)),
            (True, "План диссертации", dt.datetime(2026, 9, 27, 12, 0)),
            (True, "Собрать литературу", dt.datetime(2026, 9, 30, 12, 0)),
            (True, "Глава 1", in_days(-2, 12, 0)),
        ],
    ),
    dict(
        slug="sayt-portfolio",
        meta=dict(
            title="Сайт-портфолио", epic="Личное", parent="", state="done",
            tags=["веб"], created=dt.datetime(2026, 9, 20, 15, 0), updated=dt.datetime(2026, 9, 28, 18, 0),
            archived=False,
            description="Собран и задеплоен.",
        ),
        tasks=[
            (True, "Выбрать домен", dt.datetime(2026, 9, 22, 12, 0)),
            (True, "Сверстать главную", dt.datetime(2026, 9, 24, 12, 0)),
            (True, "Наполнить кейсами", dt.datetime(2026, 9, 26, 12, 0)),
            (True, "Деплой", dt.datetime(2026, 9, 28, 12, 0)),
        ],
    ),
    dict(
        slug="lending-proshloy-versii",
        meta=dict(
            title="Лендинг прошлой версии", epic="Продукт", parent="Маркетинг", state="archived",
            tags=["архив"], created=dt.datetime(2026, 9, 18, 10, 0), updated=dt.datetime(2026, 9, 30, 10, 0),
            archived=True,
            description="Устарел после ребрендинга.",
        ),
        tasks=[
            (False, "Отправить макет на согласование", days_ago(20, 18, 30)),
            (True, "Тексты", dt.datetime(2026, 9, 22, 12, 0)),
        ],
    ),
    # --- 27Q1: будущий квартал ---
    dict(
        slug="zapusk-startupa",
        meta=dict(
            title="Запуск стартапа", epic="Стартап Альфа", parent="", state="planned",
            tags=["мечта"], created=dt.datetime(2027, 1, 5, 9, 0), updated=dt.datetime(2027, 1, 5, 9, 0),
            archived=False,
            description="MVP за первый квартал: трекер привычек с командными челленджами.",
        ),
        tasks=[
            (False, "Валидировать идею интервью", None),
            (False, "Собрать лендинг для листа ожидания", None),
            (False, "Первая демо-версия", dt.datetime(2027, 3, 1, 12, 0)),
        ],
    ),
]


def main() -> None:
    vault = sys.argv[1] if len(sys.argv) > 1 else (
        CONTAINER_VAULT if os.path.isdir(CONTAINER_VAULT) else DEFAULT_VAULT
    )
    projects_dir = os.path.join(vault, "Projects")
    print(f"Vault: {vault}")
    if not os.path.isdir(vault):
        print("Внимание: папки нет, создаю.")
        os.makedirs(vault, exist_ok=True)
    if os.path.isdir(projects_dir):
        shutil.rmtree(projects_dir)
    os.makedirs(projects_dir)

    created = 0
    for project in PROJECTS:
        meta = project["meta"]
        quarter_dir = os.path.join(projects_dir, quarter(meta["created"]))
        folder = quarter_dir
        if meta["archived"] or meta["state"] in ("done", "archived"):
            folder = os.path.join(quarter_dir, "Completed Projects")
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, project["slug"], "Project.md")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(encode(tasks=project["tasks"], **meta))
        created += 1
        print(f"  + {quarter(meta['created'])}/{'Completed Projects/' if folder != quarter_dir else ''}{project['slug']} — {meta['title']} [{meta['state']}]")

    print(f"\nГотово: {created} проектов.")


if __name__ == "__main__":
    main()

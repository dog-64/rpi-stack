# SpecKit — Спецификации для AI агентов

Каталог с документацией для AI агентов (Claude Code, Copilot, Codex).

## Структура

```
.github/spec-kit/
├── README.md          # Этот файл
├── agents.md         # Задачи для выполнения
└── constitution.md   # Best practices
```

## Использование

**Для Claude Code и других AI агентов:**
1. Читайте `agents.md` для списка задач (приоритет сверху вниз)
2. Следуйте `constitution.md` для best practices

**Команды Makefile:**
```bash
make spec-kit-constitution  # Показать best practices
make spec-kit-update        # Обновить spec-kit из GitHub
```

## Обновление

При изменении best practices или добавлении задач обновляйте соответствующие файлы
и коммитьте с описанием изменений.

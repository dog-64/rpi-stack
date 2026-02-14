.PHONY: help ping info update setup list graph shell reboot check clean

# Подавление предупреждений Python
export PYTHONWARNINGS=ignore::DeprecationWarning

# Цвета для вывода
GREEN  := \033[0;32m
YELLOW := \033[1;33m
NC     := \033[0m

help: ## Показать эту справку
	@echo "$(GREEN)Доступные команды:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2}'

ping: ## Проверить подключение ко всем хостам
	ansible active -m ping

info: ## Показать информацию о системе
	ansible-playbook system-info.yml

update: ## Обновить все хосты
	ansible-playbook update-all.yml

setup: ## Базовая настройка кластера
	ansible-playbook setup-cluster.yml

list: ## Список всех хостов
	ansible-inventory --list

graph: ## График групп и хостов
	ansible-inventory --graph

# Группы хостов
ping-pi5: ## Ping только Raspberry Pi 5
	ansible pi5 -m ping

ping-pi4: ## Ping только Raspberry Pi 4
	ansible pi4_8gb -m ping

info-pi5: ## Информация только о Pi 5
	ansible-playbook system-info.yml --limit pi5

info-pi4: ## Информация только о Pi 4
	ansible-playbook system-info.yml --limit pi4_8gb

# Отдельные хосты
ping-leha: ## Ping leha
	ansible leha -m ping

ping-sema: ## Ping sema
	ansible sema -m ping

ping-motya: ## Ping motya
	ansible motya -m ping

ping-osya: ## Ping osya
	ansible osya -m ping

# Системные команды
uptime: ## Показать uptime всех хостов
	@ansible active -a "uptime" | grep -v ">>>" | sed 's/.*| CHANGED.*//'

temp: ## Показать температуру CPU
	@ansible active -a "vcgencmd measure_temp" | grep -v ">>>" | sed 's/.*| CHANGED.*//'

memory: ## Показать использование памяти
	@ansible active -a "free -h" | grep -v ">>>"

disk: ## Показать использование диска
	@ansible active -a "df -h /" | grep -v ">>>"

reboot: ## Перезагрузить все хосты (требует подтверждения)
	@echo "$(YELLOW)⚠️  Внимание! Это перезагрузит ВСЕ хосты кластера!$(NC)"
	@read -p "Продолжить? [y/N]: " confirm && [ "$$confirm" = "y" ] && \
		ansible active -b -a "reboot" || echo "Отменено"

reboot-%: ## Перезагрузить конкретный хост (например: make reboot-leha)
	@echo "$(YELLOW)Перезагрузка $*...$(NC)"
	ansible $* -b -a "reboot"

shutdown: ## Выключить все хосты (требует подтверждения)
	@echo "$(YELLOW)⚠️  Внимание! Это ВЫКЛЮЧИТ ВСЕ хосты кластера!$(NC)"
	@read -p "Продолжить? [y/N]: " confirm && [ "$$confirm" = "y" ] && \
		ansible active -b -a "shutdown -h now" || echo "Отменено"

shutdown-%: ## Выключить конкретный хост (например: make shutdown-leha)
	@echo "$(YELLOW)Выключение $*...$(NC)"
	ansible $* -b -a "shutdown -h now"

shell-%: ## SSH в конкретный хост (например: make shell-leha)
	@ssh $$(ansible-inventory --host $* | grep ansible_host | cut -d'"' -f4)

# Проверки
check: ## Проверить синтаксис всех playbook'ов
	@echo "$(GREEN)Проверка синтаксиса playbook'ов...$(NC)"
	@for pb in *.yml; do \
		[ "$$pb" = "inventory.yml" ] && continue; \
		echo "Проверка $$pb..."; \
		ansible-playbook --syntax-check $$pb; \
	done

# Очистка
clean: ## Очистить временные файлы
	@echo "$(GREEN)Очистка временных файлов...$(NC)"
	@rm -rf *.retry
	@rm -rf /tmp/ansible_facts
	@echo "$(GREEN)Готово!$(NC)"

# Быстрые команды
q: ping ## Быстрая проверка (алиас для ping)

i: info ## Быстрая информация (алиас для info)

# Мониторинг
watch-temp: ## Мониторинг температуры каждые 5 секунд
	@watch -n 5 "ansible active -a 'vcgencmd measure_temp' 2>/dev/null | grep temp"

watch-memory: ## Мониторинг памяти каждые 5 секунд
	@watch -n 5 "ansible active -a 'free -h' 2>/dev/null | grep -E '(leha|sema|motya|osya|Mem:)'"

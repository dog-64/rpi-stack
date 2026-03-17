.PHONY: help ping info update setup list graph shell reboot check clean locale todo k3s-install k3s-server k3s-agents k3s-status k3s-uninstall k3s-verify

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

locale: ## Настроить русскую локаль (ru_RU.UTF-8) на всех хостах
	ansible-playbook fix-locale.yml

todo: ## Открыть файл с задачами
	@cat Todo.md

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
	@ansible active -m shell -a "echo \$$(hostname -I | awk '{print \$$1}') \$$(vcgencmd measure_temp)" | awk '/\| (CHANGED|SUCCESS)/{node=$$1} /^[0-9]/{print node" ("$$1"): temp="$$2}'

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

poweroff: ## Выключить все хосты (требует подтверждения)
	@echo "$(YELLOW)⚠️  Внимание! Это ВЫКЛЮЧИТ ВСЕ хосты кластера!$(NC)"
	@read -p "Продолжить? [y/N]: " confirm && [ "$$confirm" = "y" ] && \
		ansible active -b -a "shutdown -h now" || echo "Отменено"

poweroff-%: ## Выключить конкретный хост (например: make shutdown-leha)
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
	@watch -n 5 "ansible active -a 'vcgencmd measure_temp' 2>/dev/null | awk '/\\| (CHANGED|SUCCESS)/{node=\$1} /^temp=/{print node\": \"\$0}'"

watch-memory: ## Мониторинг памяти каждые 5 секунд
	@watch -n 5 "ansible active -a 'free -h' 2>/dev/null | grep -E '(leha|sema|motya|osya|Mem:)'"

# =====================================
# k3s Kubernetes Cluster
# =====================================

k3s-install: ## Установить k3s на весь кластер
	@echo "$(GREEN)Установка k3s cluster...$(NC)"
	ansible-playbook playbooks/k3s-install.yml --limit k3s_cluster

k3s-server: ## Установить k3s server (control-plane)
	@echo "$(GREEN)Установка k3s server...$(NC)"
	ansible-playbook playbooks/k3s-install.yml --limit k3s_server

k3s-agents: ## Установить k3s agents (workers)
	@echo "$(GREEN)Установка k3s agents...$(NC)"
	ansible-playbook playbooks/k3s-install.yml --limit k3s_agent

k3s-status: ## Статус k3s кластера
	@echo "$(GREEN)Статус k3s cluster...$(NC)"
	@ansible k3s_server -b -a "k3s kubectl get nodes -o wide" 2>/dev/null || echo "k3s не установлен"

k3s-pods: ## Показать все поды в кластере (с нодами)
	@echo "$(GREEN)Поды k3s cluster...$(NC)"
	@ansible k3s_server -b -a "k3s kubectl get pods -A -o wide" 2>/dev/null || echo "k3s не установлен"

k3s-verify: ## Верификация k3s установки
	@echo "$(GREEN)Верификация k3s...$(NC)"
	ansible k3s_cluster -b -m shell -a "k3s --version" 2>/dev/null || echo "k3s не установлен на некоторых хостах"

k3s-uninstall: ## Удалить k3s со всех хостов (требует подтверждения)
	@echo "$(YELLOW)⚠️  Внимание! Это удалит k3s со ВСЕХ хостов кластера!$(NC)"
	@read -p "Продолжить? [y/N]: " confirm && [ "$$confirm" = "y" ] && \
		ansible k3s_cluster -b -m shell -a "/usr/local/bin/k3s-uninstall.sh 2>/dev/null || /usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || echo 'k3s not installed'" || echo "Отменено"

k3s-uninstall-server: ## Удалить k3s server
	@echo "$(YELLOW)Удаление k3s server...$(NC)"
	ansible k3s_server -b -a "/usr/local/bin/k3s-uninstall.sh"

k3s-uninstall-agents: ## Удалить k3s agents
	@echo "$(YELLOW)Удаление k3s agents...$(NC)"
	ansible k3s_agent -b -a "/usr/local/bin/k3s-agent-uninstall.sh"

k3s-token: ## Показать токен для подключения agents
	@echo "$(GREEN)k3s cluster token:$(NC)"
	@ansible k3s_server -b -a "cat /var/lib/rancher/k3s/server/node-token" 2>/dev/null | grep -E '^K10' || echo "k3s server не установлен"

k3s-kubeconfig: ## Показать kubeconfig для удалённого доступа
	@echo "$(GREEN)kubeconfig (замените 127.0.0.1 на IP server):$(NC)"
	@ansible k3s_server -b -a "cat /etc/rancher/k3s/k3s.yaml" 2>/dev/null | grep -v ">>>" | grep -v "CHANGED" || echo "k3s server не установлен"

k3s-shell: ## kubectl shell на server
	@ssh $$(ansible-inventory --host sema | grep ansible_host | cut -d'"' -f4) -t "sudo k3s kubectl get nodes -o wide; exec bash"

# Constitution — Best Practices

## Ansible Best Practices

### Структура проекта
```
project/
├── inventory/
│   ├── group_vars/
│   ├── host_vars/
│   └── hosts.yml
├── roles/
│   └── role_name/
│       ├── tasks/
│       ├── handlers/
│       ├── templates/
│       ├── files/
│       ├── vars/
│       ├── defaults/
│       └── meta/
├── playbooks/
└── ansible.cfg
```

### Основные принципы

**1. Идемпотентность**
- Все задачи должны быть идемпотентными
- Используйте модули вместо shell/command когда возможно
- Проверяйте состояние перед изменением

**2. Роли переиспользования**
- Одна роль = одна ответственность
- Используйте defaults/ для переменных с дефолтными значениями
- Используйте vars/ для обязательных переменных

**3. Безопасность**
- Никогда не храните секреты в репозитории
- Используйте ansible-vault для чувствительных данных
- Минимизируйте использование become: yes

**4. Отладка и тестирование**
```bash
# Проверка синтаксиса
ansible-playbook --syntax-check playbook.yml

# Dry-run
ansible-playbook --check playbook.yml

# Линтинг
ansible-lint playbook.yml
```

### Рекомендации для Raspberry Pi

**ARM архитектура:**
- Учитывайте архитектуру arm64/aarch64
- Проверяйте совместимость пакетов
- Используйте raspberry pi os репозитории

**Ресурсы:**
- Минимизируйте использование памяти
- Избегайте тяжелых контейнеров
- Мониторьте температуру CPU

### Переменные окружения

```yaml
# defaults/main.yml
---
package_state: present  # present/absent/latest
service_state: started  # started/stopped/restarted
config_file: /etc/app/config.yml
```

---

## Kubernetes Best Practices

### Структура манифестов

```yaml
# apiVersion: v1
kind: Deployment
metadata:
  name: app-name
  labels:
    app: app-name
spec:
  replicas: 3
  selector:
    matchLabels:
      app: app-name
  template:
    metadata:
      labels:
        app: app-name
    spec:
      containers:
      - name: app
        image: registry/app:tag
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
```

### Основные принципы

**1. Resources**
- Всегда указывайте requests и limits
- Используйте proper limits для предотвращения OOM
- Учитывайте доступные ресурсы узлов

**2. Health Checks**
- Liveness probe для перезапуска зависших контейнеров
- Readiness probe для traffic routing
- Startup probe для медленно стартующих приложений

**3. Security**
- Используйте non-root用户
- Minimize container capabilities
- Network policies для изоляции

**4. Observability**
- Логи в stdout/stderr
- Метрики для мониторинга
- Distributed tracing

---

## K3s Best Practices

### Особенности K3s

**Легковесный Kubernetes:**
- Оптимизирован для IoT и edge
- Built-in database (SQLite/MySQL/PostgreSQL)
- Минимальные требования к ресурсам

### Рекомендации для Raspberry Pi

**Установка:**
```bash
# Server
curl -sfL https://get.k3s.io | sh -

# Agent
curl -sfL https://get.k3s.io | K3S_URL=https://server_ip:6443 K3S_TOKEN=xxx sh -
```

**Конфигурация:**
```yaml
# /etc/rancher/k3s/config.yaml
write-kubeconfig-mode: 0644
tls-san:
  - k3s.example.com
cluster-dns: 10.43.0.10
disable:
  - traefik  # если не нужен default ingress
```

**Ресурсы:**
- Минимум 1GB RAM для master
- 512MB RAM для worker
- Используйте zram для swap

### Сетевые особенности

**Flannel (default):**
- VXLAN overlay network
- Простая настройка
- Дополнительные overhead

**WireGuard (alternative):**
- Выше производительность
- Kernel space networking
- Требует настройки

### Хранение

**Local Storage:**
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv
spec:
  storageClassName: local-storage
  capacity:
    storage: 10Gi
  accessModes:
  - ReadWriteOnce
  local:
    path: /mnt/data
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - node1
```

---

## Общие принципы

### Именование
- Используйте kebab-case для ресурсов
- Добавляйте суффикс типа ресурса: `-deployment`, `-service`
- Используйте labels для связывания ресурсов

### Версионирование
- Semver для образов контейнеров
- Git tags для релизов
- Changelog для изменений

### Документация
- Комментируйте сложные конфигурации
- Используйте README.md для ролей
- Примеры использования в docs/

### Мониторинг
- Prometheus для метрик
- Loki для логов
- Tempo для tracing
- Grafana для визуализации

# Мониторинг хостов вне k3s кластера

## Сценарий

Хост **не входит** в k3s_cluster, но нужно собирать с него метрики.

## Решение

Установить Node Exporter как **systemd service** на внешний хост → добавить в Prometheus scrape_configs.

---

## Шаг 1: Установка Node Exporter на внешний хост

### Через Ansible (если хост в inventory)

Добавь роль `node-exporter-standalone` для внешних хостов:

```yaml
# roles/node-exporter-standalone/tasks/main.yml
---
- name: Скачать Node Exporter
  ansible.builtin.get_url:
    url: https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-arm64.tar.gz
    dest: /tmp/node_exporter.tar.gz
    mode: '0644'

- name: Распаковать Node Exporter
  ansible.builtin.unarchive:сделай 
    src: /tmp/node_exporter.tar.gz
    dest: /tmp
    remote_src: true

- name: Установить бинарник
  ansible.builtin.copy:
    src: /tmp/node_exporter-1.8.2.linux-arm64/node_exporter
    dest: /usr/local/bin/node_exporter
    mode: '0755'
    remote_src: true

- name: Создать systemd service
  ansible.builtin.copy:
    content: |
      [Unit]
      Description=Node Exporter
      After=network.target

      [Service]
      User=root
      ExecStart=/usr/local/bin/node_exporter
      Restart=always

      [Install]
      WantedBy=multi-user.target
    dest: /etc/systemd/system/node_exporter.service
    mode: '0644'

- name: Запустить Node Exporter
  ansible.builtin.systemd:
    name: node_exporter
    state: started
    enabled: true
    daemon_reload: true
```

### Вручную (на хосте)

```bash
# Raspberry Pi ARM64
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-arm64.tar.gz
tar xvfz node_exporter-1.8.2.linux-arm64.tar.gz
sudo cp node_exporter-1.8.2.linux-arm64/node_exporter /usr/local/bin/

# systemd service
sudo cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
```

---

## Шаг 2: Проверка Node Exporter

```bash
curl http://IP_ХОСТА:9100/metrics | grep node_cpu
```

---

## Шаг 3: Добавить в Prometheus scrape_configs

Отредактируй `roles/monitoring/templates/prometheus-config.yml.j2`:

```yaml
scrape_configs:
  # K3s ноды (через Node Exporter DaemonSet)
  - job_name: "node-exporter-k8s"
    static_configs:
      - targets:
          - "10.0.1.33:9100"   # sema
          - "10.0.1.104:9100"  # leha
          - "10.0.1.55:9100"   # motya
          - "10.0.1.75:9100"   # osya
    relabel_configs:
      - source_labels: [__address__]
        regex: "([^:]+):.*"
        target_label: instance
        replacement: "$1"

  # Внешние хосты (standalone Node Exporter)
  - job_name: "node-exporter-external"
    static_configs:
      - targets:
          - "10.0.1.200:9100"  # внешний хост 1
          - "10.0.1.201:9100"  # внешний хост 2
    relabel_configs:
      - source_labels: [__address__]
        regex: "([^:]+):.*"
        target_label: instance
        replacement: "$1"
```

---

## Шаг 4: Применить изменения

```bash
ansible k3s_server -b -a "k3s kubectl rollout restart deployment/prometheus -n monitoring"
```

Или через Ansible роль:

```bash
ansible-playbook playbooks/monitoring-install.yml
```

---

## Шаг 5: Верификация

### В Grafana

1. Открой Grafana → Explore
2. Запрос: `up{job="node-exporter-external"}`
3. Должен появиться новый хост с `instance="10.0.1.200"`

### В Prometheus UI

```bash
k3s kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Открой http://localhost:9090/targets
```

---

## Автоматизация: Ansible роль для внешних хостов

Создай `playbooks/node-exporter-install.yml`:

```yaml
---
- name: Установка Node Exporter на внешние хосты
  hosts: external_monitoring
  become: true
  gather_facts: true

  roles:
    - role: node-exporter-standalone

  post_tasks:
    - name: Информация
      ansible.builtin.debug:
        msg: "Node Exporter установлен на {{ inventory_hostname }}: http://{{ ansible_default_ipv4.address }}:9100"
```

Добавь в `inventory.yml`:

```yaml
external_monitoring:
  hosts:
    nas:
      ansible_host: 10.0.1.200
    backup:
      ansible_host: 10.0.1.201
```

Запуск:

```bash
ansible-playbook playbooks/node-exporter-install.yml
```

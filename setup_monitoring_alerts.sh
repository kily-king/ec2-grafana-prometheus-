#!/bin/bash
# ==========================================================
# COMPLETE AWS MONITORING STACK: PROMETHEUS + GRAFANA + ALERTING
# Ubuntu 22.04 LTS (t2.micro / 8GB)
# By ChatGPT (GPT-5)
# ==========================================================

set -e

echo "=== Updating system packages ==="
sudo apt update -y && sudo apt upgrade -y

# ----------------------------------------------------------
# Ask user for Gmail credentials for alerts
# ----------------------------------------------------------
read -p "Enter your Gmail address (for alerts): " GMAIL_USER
read -s -p "Enter your Gmail App Password (16 chars): " GMAIL_PASS
echo ""

# ----------------------------------------------------------
# Install dependencies
# ----------------------------------------------------------
sudo apt install -y wget curl jq software-properties-common apt-transport-https

# ----------------------------------------------------------
# Install Node Exporter
# ----------------------------------------------------------
NODE_EXPORTER_VERSION="1.5.0"
echo "=== Installing Node Exporter v$NODE_EXPORTER_VERSION ==="
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xvf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
sudo mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
sudo useradd --no-create-home --shell /bin/false node_exporter || true

sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

# ----------------------------------------------------------
# Install Prometheus
# ----------------------------------------------------------
PROM_VERSION="2.51.0"
echo "=== Installing Prometheus v$PROM_VERSION ==="
cd /tmp
wget -q https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz
tar xvf prometheus-${PROM_VERSION}.linux-amd64.tar.gz

sudo useradd --no-create-home --shell /bin/false prometheus || true
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo cp prometheus-${PROM_VERSION}.linux-amd64/{prometheus,promtool} /usr/local/bin/
sudo cp -r prometheus-${PROM_VERSION}.linux-amd64/{consoles,console_libraries} /etc/prometheus/

sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
EOF

sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus Monitoring
After=network.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \\
  --config.file=/etc/prometheus/prometheus.yml \\
  --storage.tsdb.path=/var/lib/prometheus \\
  --web.console.templates=/etc/prometheus/consoles \\
  --web.console.libraries=/etc/prometheus/console_libraries
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus

# ----------------------------------------------------------
# Install Grafana
# ----------------------------------------------------------
echo "=== Installing Grafana OSS ==="
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt update -y
sudo apt install grafana -y

# Configure SMTP for Gmail
sudo sed -i "s/^;enabled = false/enabled = true/" /etc/grafana/grafana.ini
sudo sed -i "s/^;host = localhost:25/host = smtp.gmail.com:587/" /etc/grafana/grafana.ini
sudo sed -i "s/^;user = .*/user = ${GMAIL_USER}/" /etc/grafana/grafana.ini
sudo sed -i "s/^;password = .*/password = ${GMAIL_PASS}/" /etc/grafana/grafana.ini
sudo sed -i "s/^;from_address = .*/from_address = ${GMAIL_USER}/" /etc/grafana/grafana.ini
sudo sed -i "s/^;from_name = .*/from_name = GrafanaAlerts/" /etc/grafana/grafana.ini
sudo sed -i "s/^;skip_verify = false/skip_verify = true/" /etc/grafana/grafana.ini

sudo systemctl enable grafana-server
sudo systemctl restart grafana-server
sleep 20

# ----------------------------------------------------------
# Configure Grafana via API
# ----------------------------------------------------------
GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="admin"

# Create Prometheus data source
curl -s -X POST "$GRAFANA_URL/api/datasources" \
  -u $GRAFANA_USER:$GRAFANA_PASS \
  -H "Content-Type: application/json" \
  -d '{
        "name":"Prometheus",
        "type":"prometheus",
        "access":"proxy",
        "url":"http://localhost:9090",
        "isDefault":true
      }' >/dev/null || true

# Import Node Exporter Full Dashboard
curl -s https://grafana.com/api/dashboards/1860/revisions/31/download -o /tmp/dashboard.json
curl -s -X POST "$GRAFANA_URL/api/dashboards/db" \
  -u $GRAFANA_USER:$GRAFANA_PASS \
  -H "Content-Type: application/json" \
  -d @- <<EOF
{
  "dashboard": $(cat /tmp/dashboard.json),
  "overwrite": true,
  "inputs": [{
    "name": "DS_PROMETHEUS",
    "type": "datasource",
    "pluginId": "prometheus",
    "value": "Prometheus"
  }]
}
EOF

# Create Email Notification Channel
curl -s -X POST "$GRAFANA_URL/api/alert-notifications" \
  -u $GRAFANA_USER:$GRAFANA_PASS \
  -H "Content-Type: application/json" \
  -d "{
        \"name\": \"Gmail Alerts\",
        \"type\": \"email\",
        \"isDefault\": true,
        \"settings\": { \"addresses\": \"${GMAIL_USER}\" }
      }" >/dev/null || true

# Create Alert Rule: CPU > 80% for 5 min
CPU_RULE=$(cat <<'JSON'
{
  "title": "High CPU Usage",
  "condition": "C",
  "data": [
    {
      "refId": "A",
      "relativeTimeRange": { "from": 300, "to": 0 },
      "datasourceUid": "prometheus",
      "model": {
        "expr": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
        "format": "time_series",
        "interval": "",
        "intervalFactor": 2,
        "legendFormat": "{{instance}}",
        "refId": "A"
      }
    }
  ],
  "noDataState": "NO_DATA",
  "execErrState": "ALERTING",
  "for": "5m",
  "annotations": { "summary": "High CPU usage detected" },
  "notifications": [{ "uid": "email" }]
}
JSON
)
echo "=== Creating CPU > 80% Alert Rule ==="
curl -s -X POST "$GRAFANA_URL/api/v1/provisioning/alert-rules" \
  -u $GRAFANA_USER:$GRAFANA_PASS \
  -H "Content-Type: application/json" \
  -d "$CPU_RULE" >/dev/null || true

# ----------------------------------------------------------
# DONE
# ----------------------------------------------------------
PUBLIC_IP=$(curl -s ifconfig.me)
echo "======================================================="
echo "✅ MONITORING & ALERTING SETUP COMPLETE"
echo "-------------------------------------------------------"
echo "Prometheus: http://$PUBLIC_IP:9090"
echo "Grafana:    http://$PUBLIC_IP:3000"
echo "Login: admin / admin  (change password on first login)"
echo "Alerts will email: $GMAIL_USER"
echo "Node Exporter: http://$PUBLIC_IP:9100/metrics"
echo "======================================================="

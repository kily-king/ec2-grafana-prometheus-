# ec2-grafana-prometheus

## AWS EC2 monitoring 100% automated — including Grafana dashboards + email alerts!
- Below you’ll get a single Bash script that:

✅ Installs & configures
  - Prometheus
  - Node Exporter
  - Grafana

✅ Automatically:
  - Adds Prometheus as Grafana data source
  - Imports Node Exporter Full dashboard (ID 1860)
  - Configures Gmail SMTP for alerts (you’ll input your Gmail + App Password once)
  - Creates an alert rule (CPU > 80 % for 5 minutes → email notification)

🧩 ## Requirements

| Item|	Description|
|EC2 AMI	|Ubuntu 22.04 LTS|
|Instance Type	|t2.micro (or larger)|
|Storage|	8 GB|
|Inbound Security Group Ports	|22 (SSH), 3000 (Grafana), 9090 (Prometheus), 9100 (Node Exporter)|
|Your Gmail	|Must have App Password,  (since 2FA is on)|


#⚙️ Steps to Run

1️⃣ Launch EC2 and SSH in:
  - ssh -i your-key.pem ubuntu@<EC2_PUBLIC_IP>
  
2️⃣ Create the script file:
  - nano setup_monitoring_alerts.sh

3️⃣ Paste the script below, then save (Ctrl+O, Enter, Ctrl+X).

4️⃣ Run it:

```
chmod +x setup_monitoring_alerts.sh
./setup_monitoring_alerts.sh
```

5️⃣ Enter your Gmail and App Password when prompted.


#🚀 COMPLETE SCRIPT in the repo

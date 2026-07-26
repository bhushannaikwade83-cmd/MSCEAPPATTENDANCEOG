#!/bin/bash
# Run this on a fresh Oracle Cloud Ubuntu 22.04 VM
# (4 OCPUs, 24GB RAM - Always Free tier)

set -e

echo "=== 1. Update system ==="
sudo apt-get update && sudo apt-get upgrade -y

echo "=== 2. Install Python 3.11 + dependencies ==="
sudo apt-get install -y python3.11 python3.11-venv python3.11-dev \
    libgl1 libglib2.0-0 libsm6 libxrender1 libxext6 git curl

echo "=== 3. Create app directory ==="
mkdir -p ~/msce-face-server
cd ~/msce-face-server

echo "=== 4. Copy server files here (main.py, requirements.txt, .env) ==="
# scp these files from your Mac:
# scp server/main.py server/requirements.txt server/.env ubuntu@YOUR_VM_IP:~/msce-face-server/

echo "=== 5. Set up Python virtual environment ==="
python3.11 -m venv venv
source venv/bin/activate

echo "=== 6. Install packages (takes ~5 min, downloads buffalo_l model ~300MB) ==="
pip install --upgrade pip
pip install -r requirements.txt

echo "=== 7. Pre-download InsightFace model ==="
python3 -c "
from insightface.app import FaceAnalysis
app = FaceAnalysis(name='buffalo_l', providers=['CPUExecutionProvider'])
app.prepare(ctx_id=0, det_size=(640,640))
print('Model downloaded OK')
"

echo "=== 8. Open firewall port 8000 ==="
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 8000 -j ACCEPT
sudo netfilter-persistent save

echo "=== 9. Create systemd service for auto-start ==="
sudo tee /etc/systemd/system/msce-face.service > /dev/null <<EOF
[Unit]
Description=MSCE Face Recognition Server
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/msce-face-server
ExecStart=/home/ubuntu/msce-face-server/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 --workers 2
Restart=always
RestartSec=10
EnvironmentFile=/home/ubuntu/msce-face-server/.env

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable msce-face
sudo systemctl start msce-face

echo ""
echo "=== DONE ==="
echo "Server running at http://YOUR_VM_IP:8000"
echo "Test: curl http://YOUR_VM_IP:8000/health"
echo ""
echo "Now set in app_config.env:"
echo "INSIGHTFACE_API_BASE=http://YOUR_VM_IP:8000/api/v1"

# InsightFace Server Deployment on Oracle Cloud Always Free

## Overview

This guide sets up a production-ready face recognition API on Oracle Cloud Always Free tier with:
- 4 OCPUs + 24GB RAM (permanently free)
- InsightFace buffalo_l model (2GB)
- FastAPI server
- Docker containerization
- No cold starts, no spin-down

## Step 1: Create Oracle Cloud Account & VM

### 1.1 Sign Up
1. Go to https://cloud.oracle.com
2. Click "Start for free" → provide email/credit card (won't be charged)
3. Complete 2FA setup

### 1.2 Create VM Instance
1. Go to **Compute → Instances**
2. Click **Create Instance**
3. Configuration:
   - **Image**: Ubuntu 22.04 (included in Always Free)
   - **Shape**: Ampere (4 OCPUs, 24 GB RAM) — select this exact shape
   - **VCN**: Create new or use default
   - **Public IP**: Assign
   - **SSH Key**: Download and save (you'll need it)
4. Click **Create**
5. Wait 2-3 minutes for instance to start
6. Copy the **Public IP Address**

### 1.3 SSH into VM
```bash
chmod 600 your-ssh-key.key
ssh -i your-ssh-key.key ubuntu@YOUR_PUBLIC_IP
```

## Step 2: Install Dependencies

### 2.1 Automated Setup (Recommended)
```bash
# Download and run setup script
curl -sSL https://raw.githubusercontent.com/yourusername/repo/main/server_setup.sh | bash

# If you have it locally:
bash server_setup.sh
```

### 2.2 Manual Setup
```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Create swap (helps with memory management)
sudo dd if=/dev/zero of=/swapfile bs=1G count=8
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Allow firewall
sudo firewall-cmd --permanent --add-port=8000/tcp
sudo firewall-cmd --reload
```

## Step 3: Deploy Application

### 3.1 Upload Files
```bash
# On your local machine
scp -i your-ssh-key.key app.py ubuntu@YOUR_PUBLIC_IP:~/insightface-server/
scp -i your-ssh-key.key requirements.txt ubuntu@YOUR_PUBLIC_IP:~/insightface-server/
scp -i your-ssh-key.key Dockerfile ubuntu@YOUR_PUBLIC_IP:~/insightface-server/
scp -i your-ssh-key.key docker-compose.yml ubuntu@YOUR_PUBLIC_IP:~/insightface-server/
```

Or clone your repo:
```bash
ssh -i your-ssh-key.key ubuntu@YOUR_PUBLIC_IP
cd ~ && git clone https://github.com/yourusername/insightface-server.git
cd insightface-server
```

### 3.2 Build & Start Server
```bash
cd ~/insightface-server

# Build Docker image (first time, ~3-5 minutes)
docker-compose build

# Start server
docker-compose up -d

# Check logs
docker-compose logs -f insightface-api

# Stop server
docker-compose down
```

### 3.3 Verify
```bash
# Check if running
docker ps

# Test API
curl http://localhost:8000/health

# View interactive API docs
# Visit: http://YOUR_PUBLIC_IP:8000/docs
```

## Step 4: Integrate with Your App

### 4.1 Python Integration
```python
import requests
from pathlib import Path

class InsightFaceApiService:
    def __init__(self, api_url="http://YOUR_ORACLE_VM_IP:8000"):
        self.api_url = api_url
    
    def detect_faces(self, image_path: str):
        """Detect faces in image"""
        with open(image_path, 'rb') as f:
            files = {'file': f}
            response = requests.post(
                f"{self.api_url}/detect",
                files=files
            )
        return response.json()
    
    def recognize_faces(self, image_path: str):
        """Recognize faces against database"""
        with open(image_path, 'rb') as f:
            files = {'file': f}
            response = requests.post(
                f"{self.api_url}/recognize",
                files=files
            )
        return response.json()
    
    def register_face(self, person_id: str, image_path: str):
        """Register face to database"""
        with open(image_path, 'rb') as f:
            files = {'file': f}
            response = requests.post(
                f"{self.api_url}/register?person_id={person_id}",
                files=files
            )
        return response.json()
    
    def batch_recognize(self, image_path: str):
        """Recognize multiple faces (for attendance)"""
        with open(image_path, 'rb') as f:
            files = {'file': f}
            response = requests.post(
                f"{self.api_url}/batch-recognize",
                files=files
            )
        return response.json()
```

### 4.2 Usage Example
```python
service = InsightFaceApiService("http://YOUR_ORACLE_VM_IP:8000")

# Register faces
service.register_face("student_001", "photo_001.jpg")
service.register_face("student_002", "photo_002.jpg")

# Recognize from attendance photo
result = service.batch_recognize("classroom_photo.jpg")
for detection in result['detections']:
    if detection['matched']:
        print(f"Found: {detection['matched_person']}")
    else:
        print(f"Unknown face: {detection['similarity']:.2f}")
```

## Step 5: Network Configuration

### 5.1 Enable HTTPS (Recommended for Production)
```bash
# Install certbot
sudo apt-get install certbot python3-certbot-nginx -y

# Get SSL certificate (requires domain)
sudo certbot certonly --standalone -d your-domain.com
```

### 5.2 Configure Nginx Reverse Proxy (Optional)
```bash
sudo apt-get install nginx -y

# Create /etc/nginx/sites-available/insightface
sudo tee /etc/nginx/sites-available/insightface > /dev/null <<EOF
server {
    listen 80;
    server_name YOUR_DOMAIN_OR_IP;
    
    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/insightface /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

## API Endpoints

### Health Check
```bash
GET /health
# Response: {status, model_loaded, people_in_db, timestamp}
```

### Detect Faces
```bash
POST /detect
# File upload: image file
# Response: {faces_detected, faces[], image_shape}
```

### Recognize Faces
```bash
POST /recognize
# File upload: image file
# Response: {faces_detected, results[]} (with person_id, similarity)
```

### Register Face
```bash
POST /register?person_id=student_001
# File upload: image file
# Response: {status, person_id, embeddings_count, total_people}
```

### Batch Recognize (Attendance)
```bash
POST /batch-recognize
# File upload: image file
# Response: {timestamp, faces_detected, detections[]}
```

### Get Database Info
```bash
GET /database
# Response: {total_people, people{person_id: count}}
```

### Delete Person
```bash
DELETE /database/{person_id}
# Response: {status, person_id}
```

## Monitoring & Maintenance

### Check Server Status
```bash
# Logs
docker-compose logs -f insightface-api

# Resource usage
docker stats insightface-api

# Restart if needed
docker-compose restart insightface-api
```

### Persistent Data
- Face database stored in: `face_database.json`
- Automatically backed up on every registration
- Mount it as a volume in docker-compose.yml

### Backup
```bash
cp ~/insightface-server/face_database.json ~/backups/face_database_$(date +%Y%m%d).json
```

## Troubleshooting

### Model Loading Slow
- Expected: 30-60 seconds on first startup
- Model is cached after first load
- Check logs: `docker-compose logs`

### Out of Memory
- Ensure swap is enabled: `swapon -s`
- Check available RAM: `free -h`
- Monitor: `docker stats insightface-api`

### Port Already in Use
```bash
# Change port in docker-compose.yml:
ports:
  - "9000:8000"  # Access on port 9000
```

### Cannot Connect from Local Machine
- Ensure Security List allows port 8000
- Go to: **Compute → Instances → Your Instance → Security → Network Security Groups**
- Add Ingress Rule: Protocol = TCP, Port = 8000, CIDR = 0.0.0.0/0

## Cost

✅ **Always Free**
- 4 OCPUs
- 24 GB RAM
- 200 GB storage
- No time limit
- No credit card charges (unless you exceed Always Free limits)

## Performance Metrics

- **Detection**: ~50-200ms per image (depends on image size)
- **Recognition**: ~10-50ms per face (depends on database size)
- **Max concurrent requests**: ~10-20 (single worker)

For higher concurrency, scale workers:
```yaml
# In docker-compose.yml
command: uvicorn app:app --host 0.0.0.0 --port 8000 --workers 4
```

## Next Steps

1. Test API at `http://YOUR_ORACLE_VM_IP:8000/docs`
2. Register test faces
3. Integrate with your attendance system
4. Monitor logs regularly
5. Set up automated backups

---

**Need help?** Check server logs: `docker-compose logs -f`

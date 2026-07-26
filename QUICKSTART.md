# QuickStart: InsightFace on Oracle Cloud

## TL;DR (5 minutes)

### 1. Oracle Cloud Setup
```bash
# Go to https://cloud.oracle.com
# Click "Start for free"
# Create Ubuntu 22.04 VM (Ampere: 4 OCPUs, 24GB RAM)
# Note your Public IP
```

### 2. SSH Into VM
```bash
ssh -i your-key.key ubuntu@YOUR_PUBLIC_IP
```

### 3. Install & Run
```bash
# Copy files to ~/insightface-server/ first, then:
cd ~/insightface-server

# Install dependencies
bash server_setup.sh

# Start server
docker-compose up -d

# Verify
curl http://localhost:8000/health
```

### 4. Test API
```bash
# Open in browser:
http://YOUR_PUBLIC_IP:8000/docs

# Or use Python:
python client_example.py
```

## File Overview

| File | Purpose |
|------|---------|
| `app.py` | FastAPI server with all endpoints |
| `requirements.txt` | Python dependencies |
| `Dockerfile` | Container image definition |
| `docker-compose.yml` | Run with: `docker-compose up -d` |
| `server_setup.sh` | Automated VM setup |
| `client_example.py` | Python client for integration |
| `DEPLOYMENT.md` | Full deployment guide |

## API Endpoints

```python
# Detect faces
POST /detect (upload image)

# Recognize against database
POST /recognize (upload image)

# Register face to database
POST /register?person_id=student_001 (upload image)

# Batch recognize (for attendance)
POST /batch-recognize (upload image)

# Get database stats
GET /database

# Delete person
DELETE /database/{person_id}

# Health check
GET /health

# Interactive docs
GET /docs (Swagger UI)
```

## Quick Integration

```python
from client_example import InsightFaceApiClient

# Initialize
client = InsightFaceApiClient("http://YOUR_ORACLE_VM_IP:8000")

# Register face
client.register_face("student_001", "photo.jpg")

# Recognize from classroom photo
result = client.batch_recognize("classroom.jpg")

for detection in result['detections']:
    if detection['matched']:
        print(f"Found: {detection['matched_person']}")
```

## Common Commands

```bash
# View logs
docker-compose logs -f insightface-api

# Stop server
docker-compose down

# Restart server
docker-compose restart insightface-api

# Check resource usage
docker stats insightface-api

# SSH into container
docker exec -it insightface-server bash

# Backup database
cp ~/insightface-server/face_database.json ~/backup.json
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Can't connect | Check firewall: add port 8000 in Oracle Security Lists |
| Model slow to load | Expected 30-60s first time, then cached |
| Out of memory | Check swap: `swapon -s`, increase in docker-compose.yml |
| Port 8000 busy | Change port in docker-compose.yml: `"9000:8000"` |

## Production Tips

- ✅ Use Oracle Cloud Always Free (24GB RAM, no cost)
- ✅ Enable automatic restarts: `restart: unless-stopped` in docker-compose.yml
- ✅ Backup database regularly: `face_database.json`
- ✅ Monitor logs: `docker-compose logs -f`
- ✅ Use Nginx for HTTPS (see DEPLOYMENT.md)

## Performance

- Detection: ~50-200ms per image
- Recognition: ~10-50ms per face
- Max concurrent: ~10-20 per worker
- Scale by increasing workers in docker-compose.yml

---

**Full docs**: See `DEPLOYMENT.md`

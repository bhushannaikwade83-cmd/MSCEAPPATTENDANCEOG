# Deploy InsightFace on Hugging Face Spaces

## Overview
- Free tier: 16GB RAM (enough for buffalo_l)
- Cold starts: Yes (sleeps after 48 hours inactivity)
- Public URL: Automatic
- Best for: Testing, demos, moderate traffic

## Quick Setup (5 minutes)

### 1. Create Hugging Face Account
- Go to https://huggingface.co
- Sign up free
- Go to https://huggingface.co/spaces

### 2. Create New Space
1. Click **"Create new Space"**
2. Fill in:
   - **Space name**: `insightface-api`
   - **License**: OpenRAIL (default)
   - **Space SDK**: Choose below
   - **Visibility**: Public
3. Click **Create Space**

### 3. Choose Deployment Type

#### Option A: FastAPI (Recommended for API)
Select **"Docker"** SDK
```bash
# HF will ask for Dockerfile
# Use the Dockerfile from this repo
```

#### Option B: Streamlit (Easiest, Web UI)
Select **"Streamlit"** SDK
```bash
# Use app_streamlit.py (see below)
# More user-friendly interface
```

---

## Option A: FastAPI on Docker

### Step 1: Clone Space Repo
```bash
git clone https://huggingface.co/spaces/YOUR_USERNAME/insightface-api
cd insightface-api
```

### Step 2: Add Files
Copy these files to the repo:
```
.
├── Dockerfile           (same as Oracle version)
├── requirements.txt     (same as Oracle version)
├── app.py              (same as Oracle version)
└── README.md           (documentation)
```

### Step 3: Push to HF
```bash
git add .
git commit -m "Add InsightFace API"
git push
```

**That's it!** HF automatically builds and deploys.

### Access API
```
https://YOUR_USERNAME-insightface-api.hf.space/docs
```

---

## Option B: Streamlit (Easier)

### Step 1: Create Space with Streamlit SDK
- Space SDK: **Streamlit**
- Click Create

### Step 2: Clone Repo
```bash
git clone https://huggingface.co/spaces/YOUR_USERNAME/insightface-api
cd insightface-api
```

### Step 3: Add Files
```bash
# Copy to repo:
cp app_streamlit.py streamlit_app.py
cp requirements_streamlit.txt requirements.txt
```

### Step 4: Push
```bash
git add .
git commit -m "Add InsightFace Streamlit app"
git push
```

**Done!** Your app is live at:
```
https://huggingface.co/spaces/YOUR_USERNAME/insightface-api
```

---

## Using the API

### From Python
```python
from client_example import InsightFaceApiClient

# For FastAPI deployment
client = InsightFaceApiClient(
    "https://YOUR_USERNAME-insightface-api.hf.space"
)

# Register face
client.register_face("student_001", "photo.jpg")

# Recognize
result = client.batch_recognize("classroom.jpg")
```

### Direct cURL
```bash
# Detect
curl -X POST "https://YOUR_USERNAME-insightface-api.hf.space/detect" \
  -F "file=@photo.jpg"

# Register
curl -X POST "https://YOUR_USERNAME-insightface-api.hf.space/register?person_id=student_001" \
  -F "file=@photo.jpg"

# Recognize
curl -X POST "https://YOUR_USERNAME-insightface-api.hf.space/recognize" \
  -F "file=@photo.jpg"
```

### Web UI (Streamlit only)
- Upload image
- Click buttons to detect/recognize
- View results instantly
- Download database

---

## Cold Starts & Persistence

### Cold Start Behavior
- If unused for 48 hours: space goes to sleep
- First request after sleep: ~2-3 minutes to restart
- Subsequently: instant

### Persist Face Database
Add to `.gitignore`:
```
face_database.json
*.jpg
*.png
```

Then use Git to backup:
```bash
# Periodically save database
git add face_database.json
git commit -m "Update face database"
git push
```

Or mount external storage (HF Pro feature).

---

## Limits & Quotas

| Feature | Free Tier |
|---------|-----------|
| RAM | 16GB |
| CPU | 2 vCPU |
| Storage | 50GB |
| Monthly requests | Unlimited |
| Cold start sleep | After 48h inactivity |
| Concurrent users | ~5-10 |

---

## Troubleshooting

### Build Fails
Check **Space logs** (click Space → Logs)
Common issues:
```bash
# Model too large to download
→ Increase timeout in requirements.txt

# Out of memory during build
→ Build happens with 16GB, should work
→ If fails, try smaller model or Streamlit version
```

### Slow First Request
- Expected: 30-60s (model loading)
- Cached after: instant
- Cold start after sleep: 2-3 min

### Database Doesn't Persist
- Use Git to backup `face_database.json`
- Or use HF datasets API for storage

---

## Production Considerations

❌ **Not suitable for:**
- 24/7 attendance system (cold starts)
- High concurrency (limited workers)
- Long-term data retention (may reset)

✅ **Good for:**
- Testing/demos
- Prototyping
- Low-traffic attendance
- Educational use

---

## Upgrade Path

If you outgrow Hugging Face Spaces:
1. **HF Pro** ($9/mo) — better resources, no cold starts
2. **Oracle Cloud** (free) — production-ready, no limits
3. **DigitalOcean** ($5/mo) — simple alternative

---

## File Structure

### FastAPI Version
```
insightface-api/
├── Dockerfile
├── requirements.txt
├── app.py
└── README.md
```

### Streamlit Version
```
insightface-api/
├── streamlit_app.py
├── requirements.txt
└── README.md
```

---

## Example Git Workflow

```bash
# 1. Clone
git clone https://huggingface.co/spaces/YOUR_USERNAME/insightface-api
cd insightface-api

# 2. Add files
cp ~/insightface-app.py ./
cp ~/requirements.txt ./

# 3. Commit
git add .
git commit -m "Initial InsightFace deployment"

# 4. Push (auto-deploys!)
git push

# 5. Monitor
# Go to Space → Logs (shows build progress)

# 6. Test
# https://YOUR_USERNAME-insightface-api.hf.space/docs
```

---

## Next: Create Streamlit App

Want me to create `app_streamlit.py` for easier web interface?

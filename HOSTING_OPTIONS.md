# Python Backend Hosting Comparison

## Overview
Your backend: FastAPI + FAISS + Firebase (face recognition API)
**Use case:** Student attendance with face recognition (200k+ students)

---

## Hosting Comparison

| Feature | Render | Railway | Heroku | Cloud Run |
|---------|--------|---------|--------|-----------|
| **Cost** | $0-7/mo | $0-5/mo | $25/mo | $0 + usage |
| **Cold starts** | 30-60s | 30-60s | 30-60s | 30-60s |
| **Setup time** | 5 min | 5 min | 10 min | 20 min |
| **Persistent storage** | ✅ (via disk) | ✅ (limited) | ✅ | ⚠️ (complex) |
| **PostgreSQL** | ✅ (included) | ❌ | ❌ | ❌ (separate) |
| **Auto-deploy** | ✅ | ✅ | ✅ | ✅ |
| **FAISS file support** | ✅ | ✅ | ❌ | ⚠️ (Cloud Storage) |
| **Scaling** | ✅ | ✅ | ❌ | ✅ |
| **Learning curve** | Easy | Easy | Medium | Hard |

---

## Detailed Breakdown

### 🥇 Render (RECOMMENDED)
**Best for your use case**

**Pros:**
- Free tier includes 750 hours/month (enough for small scale)
- PostgreSQL database included (upgrade to pgvector later)
- GitHub auto-deploy works perfectly
- Can mount persistent disk volumes ($0.25/GB/month)
- Scales automatically when traffic increases
- Environment variables easy to manage
- Good for Indian users (servers in multiple regions)

**Cons:**
- Free tier spins down after 15 min of inactivity (cold starts)
- Upgraded plans are ~$7/month minimum

**Setup:**
```bash
# 1. Push code to GitHub
git push origin main

# 2. Go to render.com
# 3. Connect GitHub account
# 4. Create new Web Service
# 5. Configure:
# - Build: pip install -r requirements.txt
# - Start: uvicorn main:app --host 0.0.0.0 --port $PORT

# 6. Add environment variables in dashboard:
# FIREBASE_CREDENTIALS_PATH=/etc/secrets/firebase.json
# DATABASE_URL=postgres://...
# LOG_LEVEL=INFO

# 7. Click "Deploy" 
# Done! Takes 5-10 minutes
```

**Your monthly cost estimate:**
- Free tier (good for testing): $0
- Starter plan (production): $7/month for continuous running
- With persistent disk: +$5/month

---

### 🥈 Railway
**Good alternative, slightly simpler**

**Pros:**
- Slightly cheaper than Render at scale
- Very simple deploy (connect GitHub repo)
- Good documentation
- Generous free tier

**Cons:**
- Database costs extra ($5+/month)
- Less flexible than Render
- Fewer location options

**Cost estimate:** $5-15/month

---

### ❌ Heroku (Avoid)
**Free tier was discontinued (Nov 2022)**

**Why not:**
- Pricing increased to $50+/month
- No good free alternative anymore
- Community moved to Render/Railway

---

### 🟡 Google Cloud Run
**Only if you migrate from FAISS → Cloud Firestore Vector Search**

**Current problems:**
- FAISS files stored in memory, lost on cold start
- File persistence complex on Cloud Run
- Requires Cloud Storage + service account setup

**When it becomes viable:**
- After Cloud Firestore Vector Search is in your region
- After moving embeddings to Firestore (no FAISS files)
- Free tier still available: 2M requests/month

**Cost estimate after migration:** $5-30/month (depends on traffic)

---

## Migration Path: FAISS → PostgreSQL + pgvector

**Why migrate?** 
- No file management complexity
- Persistent across deployments
- Can run on any platform
- Better for scaling

**Timeline:**
1. **Week 1:** Keep current FAISS setup (works on Render)
2. **Week 2-3:** Test pgvector locally
3. **Week 4:** Migrate data
4. **Week 5:** Deploy with pgvector

**Code changes:** ~500 lines (manageable)

---

## Quick Decision Tree

```
Q1: Do you need it running 24/7?
├─ YES → Use Render Starter ($7/month)
└─ NO → Use Render Free tier

Q2: How many students?
├─ <10k → Free tier is fine
├─ 10k-100k → Starter plan ($7/month)
└─ >100k → Need to optimize (pgvector migration)

Q3: Expected requests/day?
├─ <1000 → Free tier
├─ 1000-10000 → Free → Starter transition
└─ >10000 → Need Starter or higher

Q4: Do you want PostgreSQL?
├─ YES → Render (included)
└─ NO → Railway
```

---

## Recommended Setup Now

**Option A: Fastest (Recommended)**
```
Platform: Render
Database: Use Firestore only (simpler)
FAISS: Save to Render persistent disk (/var/data/)
Timeline: Deploy today
Cost: $0 (free tier) or $7/month
```

**Option B: Better for Scale**
```
Platform: Render
Database: Add PostgreSQL with pgvector
FAISS: Migrate to pgvector
Timeline: 2-3 weeks
Cost: $15-20/month
```

---

## Step-by-Step: Deploy to Render Today

### 1. Create `requirements.txt`
```
fastapi==0.104.1
uvicorn==0.24.0
numpy==1.24.3
opencv-python==4.8.0
Pillow==10.0.0
insightface==0.7.3
onnxruntime==1.16.2
faiss-cpu==1.7.4
firebase-admin==6.2.0
python-multipart==0.0.6
slowapi==0.1.9
python-dotenv==1.0.0
```

### 2. Create `.env` (for local testing)
```
FIREBASE_CREDENTIALS_PATH=/path/to/firebase-credentials.json
LOG_LEVEL=INFO
ENVIRONMENT=development
```

### 3. Create `Dockerfile` (optional, for more control)
```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libgl1 \
    libsm6 \
    libxext6 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### 4. Deploy Steps
1. Push to GitHub:
   ```bash
   git add .
   git commit -m "Fix syntax error and prepare for deployment"
   git push origin main
   ```

2. Go to https://render.com
3. Click "New" → "Web Service"
4. Select your GitHub repo
5. Configure:
   - **Name:** `face-recognition-api`
   - **Environment:** `Python 3`
   - **Build command:** `pip install -r requirements.txt`
   - **Start command:** `uvicorn main:app --host 0.0.0.0 --port $PORT`
   
6. Add environment variables:
   ```
   FIREBASE_CREDENTIALS_PATH=/etc/secrets/firebase-key.json
   LOG_LEVEL=INFO
   ENVIRONMENT=production
   ```

7. Click "Create Web Service"
8. Done! Deploys in 5-10 minutes

---

## Testing After Deployment

```bash
# Replace with your Render URL
BACKEND_URL="https://your-api.onrender.com"

# Test 1: Health check
curl $BACKEND_URL/api/v1/health

# Expected response:
{
  "status": "healthy",
  "service": "face-recognition-api",
  "dependencies": {...}
}

# Test 2: Register test (with image file)
curl -F "file=@test_image.jpg" \
     -F "institute_id=test123" \
     -F "student_id=s001" \
     -F "roll_number=101" \
     -F "name=John Doe" \
     $BACKEND_URL/api/v1/register

# Test 3: Recognize test
curl -F "file=@test_image.jpg" \
     -F "institute_id=test123" \
     $BACKEND_URL/api/v1/recognize
```

---

## Cost Comparison Over 1 Year

| Platform | Setup | Monthly | Annual | Total |
|----------|-------|---------|--------|-------|
| **Render Free** | $0 | $0 | $0 | **$0** |
| **Render Starter** | $0 | $7 | $84 | **$84** |
| **Render + pgvector** | $0 | $15 | $180 | **$180** |
| **Railway** | $0 | $5 | $60 | **$60** |
| **Heroku** | $0 | $50 | $600 | **$600** ❌ |
| **Cloud Run** | $0 | $10 | $120 | **$120** ⏳ |

---

## Summary

✅ **Do this today:**
1. Fix syntax error (DONE)
2. Create `requirements.txt`
3. Deploy to Render (5 min setup)
4. Test with your Flask app

⏳ **Do this next week:**
- Monitor performance
- Optimize FAISS loading
- Consider pgvector migration

---


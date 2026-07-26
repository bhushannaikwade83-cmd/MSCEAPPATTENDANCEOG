# Hugging Face Spaces - Quick Deploy (3 steps)

## Step 1: Create Space
1. Go to https://huggingface.co/spaces
2. Click **Create new Space**
3. Enter:
   - **Name**: `insightface-api`
   - **SDK**: **Streamlit** (easiest) OR **Docker** (API)
   - **Visibility**: Public
4. Click **Create Space**

## Step 2: Clone & Push Files

### For Streamlit (Recommended - Easier)
```bash
# Clone
git clone https://huggingface.co/spaces/YOUR_USERNAME/insightface-api
cd insightface-api

# Add files
cp streamlit_app.py ./
cp requirements_streamlit.txt requirements.txt

# Push
git add .
git commit -m "Add InsightFace Streamlit app"
git push
```

### For FastAPI (Docker)
```bash
git clone https://huggingface.co/spaces/YOUR_USERNAME/insightface-api
cd insightface-api

# Add files
cp app.py ./
cp requirements.txt ./
cp Dockerfile ./

git add .
git commit -m "Add InsightFace API"
git push
```

## Step 3: Done!
Space auto-builds and deploys. Check **Logs** tab for progress.

**Your URL:**
```
https://huggingface.co/spaces/YOUR_USERNAME/insightface-api
```

---

## Streamlit vs FastAPI

| Feature | Streamlit | FastAPI |
|---------|-----------|---------|
| Easiest to deploy | ✅ Yes | ❌ Docker needed |
| Web UI included | ✅ Yes | ❌ No |
| API endpoints | ❌ No | ✅ Yes |
| File upload/download | ✅ Yes | ❌ Via API |
| Attendance marking | ✅ Built-in | ❌ Code required |

**→ Use Streamlit for easy testing & UI**
**→ Use FastAPI to build your own app**

---

## First Time Setup

Model loads ~1-2 minutes on first request. Subsequent requests are instant.

### Test Your Deployment
1. Wait for Space to build (see Logs)
2. Click "Open in iframe" or visit the URL
3. Upload a photo
4. Click "Detect Faces" to test

---

## Troubleshooting

### Build failed?
- Check **Logs** tab
- Most common: dependency issue
- Try: `pip install insightface --upgrade`

### App slow?
- First request: loading model (1-2 min)
- After: instant
- Cold start after 48h: 2-3 min

### Database not saving?
- Streamlit stores in `/tmp` (resets on restart)
- Use download button to save JSON
- Re-upload to restore

---

## Next Steps

1. Test Streamlit app first
2. Register some faces
3. Try attendance marking
4. If you need API, switch to FastAPI version

---

## Help

- **HF Spaces docs**: https://huggingface.co/docs/hub/spaces
- **InsightFace docs**: https://github.com/deepinsight/insightface
- **Streamlit docs**: https://docs.streamlit.io

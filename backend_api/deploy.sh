#!/bin/bash
# Quick deployment script for Cloud Run
# Uses your Firebase project: smartattendanceapp-bc2fe

echo "🚀 Deploying ArcFace Backend to Firebase/Cloud Run..."
echo "Project: smartattendanceapp-bc2fe"
echo ""

# Set project
gcloud config set project smartattendanceapp-bc2fe

# Enable APIs
echo "📦 Enabling required APIs..."
gcloud services enable run.googleapis.com
gcloud services enable cloudbuild.googleapis.com

# Deploy
echo "🚀 Deploying to Cloud Run..."
echo "💡 Setting minimum instances to 1 to prevent cold starts..."
gcloud run deploy face-recognition-api \
  --source . \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 4Gi \
  --timeout 300 \
  --min-instances 1 \
  --max-instances 10 \
  --project smartattendanceapp-bc2fe \
  --set-env-vars="PYTHONUNBUFFERED=1"

echo ""
echo "✅ Deployment complete!"
echo "📋 Copy the Service URL above and add it to your .env file:"
echo "   FACE_RECOGNITION_API_URL=https://your-url-here/api/v1"

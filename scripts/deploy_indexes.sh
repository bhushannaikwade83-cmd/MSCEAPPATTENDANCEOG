#!/bin/bash

# Script to automatically deploy Firestore indexes
# This ensures all required indexes are created

echo "🚀 Deploying Firestore indexes..."

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI is not installed"
    echo "📦 Install it with: npm install -g firebase-tools"
    exit 1
fi

# Check if logged in
if ! firebase projects:list &> /dev/null; then
    echo "🔐 Please login to Firebase first:"
    firebase login
fi

# Deploy indexes
echo "📋 Deploying indexes from firestore.indexes.json..."
firebase deploy --only firestore:indexes

if [ $? -eq 0 ]; then
    echo "✅ Indexes deployed successfully!"
    echo "⏳ Wait a few minutes for indexes to be created"
    echo "💡 Check status at: https://console.firebase.google.com/project/_/firestore/indexes"
else
    echo "❌ Failed to deploy indexes"
    exit 1
fi

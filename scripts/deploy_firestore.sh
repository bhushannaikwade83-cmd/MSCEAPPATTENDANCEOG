#!/bin/bash

# ============================================================
#   AUTOMATED FIRESTORE DEPLOYMENT SCRIPT
#   Deploys Rules, Indexes, and Initializes Collections
# ============================================================

echo ""
echo "============================================================"
echo "  🚀 FIRESTORE AUTOMATED DEPLOYMENT"
echo "============================================================"
echo ""

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "[❌ ERROR] Firebase CLI is not installed"
    echo ""
    echo "📦 Please install it with:"
    echo "   npm install -g firebase-tools"
    echo ""
    echo "Then run this script again."
    exit 1
fi

echo "[✅] Firebase CLI found"
echo ""

# Check if logged in
echo "[🔍] Checking Firebase login status..."
if ! firebase projects:list &> /dev/null; then
    echo "[⚠️] Not logged in to Firebase"
    echo ""
    echo "[🔐] Attempting to login..."
    firebase login
    if [ $? -ne 0 ]; then
        echo "[❌] Login failed"
        exit 1
    fi
    echo ""
    echo "[✅] Login successful"
fi

echo ""
echo "[✅] Firebase login verified"
echo ""

# Check if required files exist
if [ ! -f "firestore.rules" ]; then
    echo "[❌ ERROR] firestore.rules not found!"
    echo "Please make sure you're in the project root directory."
    exit 1
fi

if [ ! -f "firestore.indexes.json" ]; then
    echo "[❌ ERROR] firestore.indexes.json not found!"
    echo "Please make sure you're in the project root directory."
    exit 1
fi

echo "[✅] All required files found"
echo ""

# Set Firebase project
echo "[🔧] Setting Firebase project..."
if [ -f "firebase.json" ]; then
    echo "[✅] Using project from firebase.json"
else
    echo "[⚠️] firebase.json not found"
    echo "You may need to run: firebase use msce-attendace-app"
    echo ""
fi

echo ""
echo "============================================================"
echo "  📋 STEP 1: DEPLOYING FIRESTORE RULES"
echo "============================================================"
echo ""

firebase deploy --only firestore:rules

if [ $? -ne 0 ]; then
    echo ""
    echo "[❌] Rules deployment failed!"
    echo "Please check the error messages above."
    exit 1
fi

echo ""
echo "[✅] Firestore rules deployed successfully!"
echo ""

echo "============================================================"
echo "  📊 STEP 2: DEPLOYING FIRESTORE INDEXES"
echo "============================================================"
echo ""

firebase deploy --only firestore:indexes

if [ $? -ne 0 ]; then
    echo ""
    echo "[❌] Indexes deployment failed!"
    echo "Please check the error messages above."
    exit 1
fi

echo ""
echo "[✅] Firestore indexes deployed successfully!"
echo ""

echo "============================================================"
echo "  ✅ DEPLOYMENT COMPLETE!"
echo "============================================================"
echo ""
echo "📋 Summary:"
echo "   ✅ Firestore Rules: Deployed"
echo "   ✅ Firestore Indexes: Deployed"
echo ""
echo "⏳ Index Creation Status:"
echo "   - Indexes will be created in 2-5 minutes"
echo "   - Check status: https://console.firebase.google.com/project/msce-attendace-app/firestore/indexes"
echo ""
echo "📝 Collections:"
echo "   - Collections are auto-created when the app runs"
echo "   - No manual collection creation needed"
echo ""
echo "💡 Next Steps:"
echo "   1. Wait 2-5 minutes for indexes to be ready"
echo "   2. Run your Flutter app"
echo "   3. Collections will be auto-initialized on first run"
echo ""
echo "============================================================"
echo ""

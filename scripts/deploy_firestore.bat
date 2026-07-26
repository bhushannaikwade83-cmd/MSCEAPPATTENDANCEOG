@echo off
REM ============================================================
REM   AUTOMATED FIRESTORE DEPLOYMENT SCRIPT
REM   Deploys Rules, Indexes, and Initializes Collections
REM ============================================================

echo.
echo ============================================================
echo   🚀 FIRESTORE AUTOMATED DEPLOYMENT
echo ============================================================
echo.

REM Check if Firebase CLI is installed
where firebase >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [❌ ERROR] Firebase CLI is not installed
    echo.
    echo 📦 Please install it with:
    echo    npm install -g firebase-tools
    echo.
    echo Then run this script again.
    echo.
    pause
    exit /b 1
)

echo [✅] Firebase CLI found
echo.

REM Check if logged in
echo [🔍] Checking Firebase login status...
firebase projects:list >temp_firebase_check.txt 2>&1
set FIREBASE_CHECK_ERROR=%ERRORLEVEL%
if %FIREBASE_CHECK_ERROR% NEQ 0 (
    echo [⚠️] Not logged in to Firebase
    echo.
    echo [🔐] Attempting to login...
    firebase login --no-localhost
    if %ERRORLEVEL% NEQ 0 (
        echo [❌] Login failed
        del temp_firebase_check.txt >nul 2>&1
        pause
        exit /b 1
    )
    echo.
    echo [✅] Login successful
)
del temp_firebase_check.txt >nul 2>&1

echo.
echo [✅] Firebase login verified
echo.

REM Check if required files exist
if not exist "firestore.rules" (
    echo [❌ ERROR] firestore.rules not found!
    echo Please make sure you're in the project root directory.
    pause
    exit /b 1
)

if not exist "firestore.indexes.json" (
    echo [❌ ERROR] firestore.indexes.json not found!
    echo Please make sure you're in the project root directory.
    pause
    exit /b 1
)

echo [✅] All required files found
echo.

REM Set Firebase project
echo [🔧] Setting Firebase project...
if exist "firebase.json" (
    echo [✅] Using project from firebase.json
) else (
    echo [⚠️] firebase.json not found
    echo You may need to run: firebase use msce-attendace-app
    echo.
)

echo.
echo ============================================================
echo   📋 STEP 1: DEPLOYING FIRESTORE RULES
echo ============================================================
echo.

firebase deploy --only firestore:rules

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [❌] Rules deployment failed!
    echo Please check the error messages above.
    pause
    exit /b 1
)

echo.
echo [✅] Firestore rules deployed successfully!
echo.

echo ============================================================
echo   📊 STEP 2: DEPLOYING FIRESTORE INDEXES
echo ============================================================
echo.

firebase deploy --only firestore:indexes

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [❌] Indexes deployment failed!
    echo Please check the error messages above.
    pause
    exit /b 1
)

echo.
echo [✅] Firestore indexes deployed successfully!
echo.

echo ============================================================
echo   ✅ DEPLOYMENT COMPLETE!
echo ============================================================
echo.
echo 📋 Summary:
echo    ✅ Firestore Rules: Deployed
echo    ✅ Firestore Indexes: Deployed
echo.
echo ⏳ Index Creation Status:
echo    - Indexes will be created in 2-5 minutes
echo    - Check status: https://console.firebase.google.com/project/msce-attendace-app/firestore/indexes
echo.
echo 📝 Collections:
echo    - Collections are auto-created when the app runs
echo    - No manual collection creation needed
echo.
echo 💡 Next Steps:
echo    1. Wait 2-5 minutes for indexes to be ready
echo    2. Run your Flutter app
echo    3. Collections will be auto-initialized on first run
echo.
echo ============================================================
echo.

pause

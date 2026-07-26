@echo off
REM Script to automatically deploy Firestore indexes on Windows
REM This ensures all required indexes are created

echo.
echo ========================================
echo   Firestore Index Deployment Script
echo ========================================
echo.

REM Check if Firebase CLI is installed
where firebase >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Firebase CLI is not installed
    echo.
    echo Please install it with:
    echo   npm install -g firebase-tools
    echo.
    pause
    exit /b 1
)

echo [OK] Firebase CLI found
echo.

REM Check if logged in
echo Checking Firebase login status...
firebase projects:list >temp_firebase_check.txt 2>&1
set FIREBASE_CHECK_ERROR=%ERRORLEVEL%
if %FIREBASE_CHECK_ERROR% NEQ 0 (
    echo [WARNING] Not logged in to Firebase or connection issue
    echo.
    echo Attempting to login...
    firebase login --no-localhost
    if %ERRORLEVEL% NEQ 0 (
        echo [ERROR] Login failed
        del temp_firebase_check.txt >nul 2>&1
        pause
        exit /b 1
    )
    echo.
    echo Verifying login...
    firebase projects:list >nul 2>nul
    if %ERRORLEVEL% NEQ 0 (
        echo [ERROR] Login verification failed
        del temp_firebase_check.txt >nul 2>&1
        pause
        exit /b 1
    )
)
del temp_firebase_check.txt >nul 2>&1

echo [OK] Firebase login verified
echo.

REM Check if firestore.indexes.json exists
if not exist "firestore.indexes.json" (
    echo [ERROR] firestore.indexes.json not found!
    echo Please make sure you're in the project root directory.
    echo.
    pause
    exit /b 1
)

echo [OK] firestore.indexes.json found
echo.

REM Set project (optional - will use default if firebase.json exists)
if exist "firebase.json" (
    echo Using project from firebase.json...
) else (
    echo [WARNING] firebase.json not found
    echo You may need to run: firebase use PROJECT_ID
    echo.
)

echo.
echo ========================================
echo   Deploying Firestore Indexes...
echo ========================================
echo.

REM Deploy indexes
firebase deploy --only firestore:indexes

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo   ✅ SUCCESS!
    echo ========================================
    echo.
    echo Indexes have been deployed successfully!
    echo.
    echo ⏳ Please wait 2-5 minutes for indexes to be created
    echo 💡 Check status at: https://console.firebase.google.com/project/smartattendanceapp-bc2fe/firestore/indexes
    echo.
    echo Your app will automatically use these indexes once they're ready.
    echo.
) else (
    echo.
    echo ========================================
    echo   ❌ DEPLOYMENT FAILED
    echo ========================================
    echo.
    echo Please check the error messages above.
    echo.
    echo Common issues:
    echo   - Not logged in: Run 'firebase login'
    echo   - Wrong project: Run 'firebase use PROJECT_ID'
    echo   - Invalid index: Check firestore.indexes.json format
    echo.
)

pause

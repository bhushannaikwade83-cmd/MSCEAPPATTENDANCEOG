@echo off
REM Script to delete unused Firestore indexes
REM This removes indexes that are not used in the app

echo.
echo ========================================
echo   Delete Unused Firestore Indexes
echo ========================================
echo.
echo WARNING: This will delete unused indexes from Firebase
echo.
echo Unused indexes to delete:
echo   1. CICAgLjRyYIK - inOut (instituteCode, date, name_)
echo   2. CICAgJjmnlgK - inOut Collection scope (studentId, instituteCode, name)
echo   3. CICAgJjFZMK - batches (year, name, _name_)
echo.
set /p confirm="Are you sure you want to delete these indexes? (yes/no): "

if /i not "%confirm%"=="yes" (
    echo.
    echo Operation cancelled.
    pause
    exit /b 0
)

echo.
echo ========================================
echo   Deleting Indexes...
echo ========================================
echo.

REM Check if Firebase CLI is installed
where firebase >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Firebase CLI is not installed
    echo Please install it with: npm install -g firebase-tools
    pause
    exit /b 1
)

REM Check if logged in
firebase projects:list >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Not logged in to Firebase
    echo Please run: firebase login
    pause
    exit /b 1
)

echo.
echo NOTE: Firebase CLI doesn't support direct index deletion
echo.
echo Please delete indexes manually via Firebase Console:
echo.
echo 1. Go to: https://console.firebase.google.com/project/smartattendanceapp-bc2fe/firestore/indexes
echo.
echo 2. Delete these indexes:
echo    - CICAgLjRyYIK (inOut: instituteCode, date, name_)
echo    - CICAgJjmnlgK (inOut Collection: studentId, instituteCode, name)
echo    - CICAgJjFZMK (batches: year, name, _name_)
echo.
echo 3. For each index:
echo    - Click the three dots (⋮) on the right
echo    - Click "Delete"
echo    - Confirm deletion
echo.
echo ========================================
echo   Alternative: Update firestore.indexes.json
echo ========================================
echo.
echo You can also remove unused indexes from firestore.indexes.json
echo and deploy with: firebase deploy --only firestore:indexes --force
echo.
echo This will remove indexes not in the file.
echo.

pause

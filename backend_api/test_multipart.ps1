# Test multipart file upload with curl (PowerShell)

$imagePath = "C:\Users\naikw\Downloads\WhatsApp Image 2026-03-04 at 23.32.03.jpeg"
$url = "http://127.0.0.1:8000/api/v1/recognize"

Write-Host "Testing multipart file upload..." -ForegroundColor Cyan
Write-Host "Image: $imagePath" -ForegroundColor Yellow
Write-Host "URL: $url" -ForegroundColor Yellow
Write-Host ""

if (-not (Test-Path $imagePath)) {
    Write-Host "❌ Error: Image file not found at: $imagePath" -ForegroundColor Red
    exit 1
}

# Test with curl
curl.exe -X POST `
  "$url" `
  -F "file=@$imagePath" `
  -F "institute_id=11" `
  -F "threshold=0.85"

Write-Host ""
Write-Host "✅ Request sent!" -ForegroundColor Green

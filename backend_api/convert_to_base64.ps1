# PowerShell script to convert image to base64
param(
    [Parameter(Mandatory=$true)]
    [string]$ImagePath
)

if (-not (Test-Path $ImagePath)) {
    Write-Host "❌ Error: File not found: $ImagePath" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🔄 Converting image to base64..." -ForegroundColor Cyan
Write-Host "📁 Image: $ImagePath" -ForegroundColor Gray

try {
    # Read image file as bytes
    $imageBytes = [System.IO.File]::ReadAllBytes($ImagePath)
    $fileSize = (Get-Item $ImagePath).Length
    
    # Convert to base64
    $base64String = [Convert]::ToBase64String($imageBytes)
    
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Green
    Write-Host "✅ SUCCESS! BASE64 STRING GENERATED" -ForegroundColor Green
    Write-Host "=" * 80 -ForegroundColor Green
    Write-Host ""
    Write-Host "📁 Image Path: $ImagePath" -ForegroundColor Cyan
    Write-Host "📦 Original Size: $($fileSize.ToString('N0')) bytes ($([math]::Round($fileSize/1KB, 2)) KB)" -ForegroundColor Cyan
    Write-Host "📏 Base64 Length: $($base64String.Length.ToString('N0')) characters" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Green
    Write-Host "📋 COPY THIS BASE64 STRING (it's very long):" -ForegroundColor Yellow
    Write-Host "=" * 80 -ForegroundColor Green
    Write-Host ""
    Write-Host $base64String -ForegroundColor White
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Green
    Write-Host ""
    Write-Host "💡 Next Steps:" -ForegroundColor Cyan
    Write-Host "   1. Copy the entire base64 string above" -ForegroundColor Gray
    Write-Host "   2. Open: http://127.0.0.1:8000/docs" -ForegroundColor Gray
    Write-Host "   3. Click '/api/v1/recognize' → 'Try it out'" -ForegroundColor Gray
    Write-Host "   4. Paste base64 in 'image_base64' field" -ForegroundColor Gray
    Write-Host "   5. Set 'institute_id': 'INS001'" -ForegroundColor Gray
    Write-Host "   6. Click 'Execute'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Green
    
} catch {
    Write-Host ""
    Write-Host "❌ Error: $_" -ForegroundColor Red
    exit 1
}

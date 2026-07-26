# PowerShell script to test with your base64 string
# Replace YOUR_BASE64_STRING_HERE with your actual base64 string

$base64String = "YOUR_BASE64_STRING_HERE"

$body = @{
    image_base64 = $base64String
    institute_id = "INS001"
    threshold = 0.85
} | ConvertTo-Json

Write-Host "🚀 Testing face recognition with your base64 string..."
Write-Host ""

try {
    $response = Invoke-RestMethod -Uri "http://127.0.0.1:8000/api/v1/recognize" -Method POST -Body $body -ContentType "application/json"
    
    Write-Host "✅ SUCCESS!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Response:" -ForegroundColor Cyan
    $response | ConvertTo-Json -Depth 10
} catch {
    Write-Host "❌ ERROR:" -ForegroundColor Red
    Write-Host $_.Exception.Message
    if ($_.ErrorDetails) {
        Write-Host ""
        Write-Host "Error Details:" -ForegroundColor Yellow
        Write-Host $_.ErrorDetails.Message
    }
}

# Convert image to base64 using PowerShell
$imgPath = "C:\Users\naikw\Downloads\WhatsApp Image 2026-03-04 at 23.32.03.jpeg"

Write-Host "============================================================"
Write-Host "BASE64 CONVERSION"
Write-Host "============================================================"

if (-not (Test-Path $imgPath)) {
    Write-Host "❌ Error: Image file not found at: $imgPath" -ForegroundColor Red
    exit 1
}

try {
    # Read image bytes
    $imgBytes = [System.IO.File]::ReadAllBytes($imgPath)
    $fileSize = $imgBytes.Length
    
    # Convert to base64
    $base64String = [Convert]::ToBase64String($imgBytes)
    
    # Display info
    Write-Host "Image path: $imgPath"
    Write-Host "Original file size: $fileSize bytes ($([math]::Round($fileSize/1024, 2)) KB)"
    Write-Host "Base64 string length: $($base64String.Length) characters"
    Write-Host ""
    Write-Host "Base64 preview (first 100 chars): $($base64String.Substring(0, [Math]::Min(100, $base64String.Length)))..."
    Write-Host "Base64 preview (last 100 chars): ...$($base64String.Substring([Math]::Max(0, $base64String.Length - 100)))"
    Write-Host ""
    Write-Host "============================================================"
    Write-Host "FULL BASE64 STRING (copy this for API testing):"
    Write-Host "============================================================"
    Write-Host $base64String
    Write-Host "============================================================"
    
    # Save to file
    $outputFile = "base64_output.txt"
    $base64String | Out-File -FilePath $outputFile -Encoding utf8 -NoNewline
    Write-Host ""
    Write-Host "✅ Base64 string also saved to: $outputFile" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Error: $_" -ForegroundColor Red
    exit 1
}

# PowerShell script to test /api/v1/register with base64 image
# This script reads the base64 string from base64_output.txt and sends it to the API

$base64File = "base64_output.txt"
$apiUrl = "http://127.0.0.1:8000/api/v1/register"

# Check if base64 file exists
if (-not (Test-Path $base64File)) {
    Write-Host "❌ Error: $base64File not found!" -ForegroundColor Red
    Write-Host "   Please run convert_user_image.ps1 first to generate the base64 string." -ForegroundColor Yellow
    exit 1
}

# Read base64 string from file
Write-Host "📖 Reading base64 string from $base64File..." -ForegroundColor Cyan
$base64String = Get-Content $base64File -Raw
$base64String = $base64String.Trim() # Remove any whitespace

Write-Host "✅ Base64 string loaded (length: $($base64String.Length) characters)" -ForegroundColor Green

# Prepare JSON body
$requestBody = @{
    image_base64 = $base64String
    institute_id = "INS001"
    student_id = "STU001"
    roll_number = "ROLL001"
    name = "Test Student"
} | ConvertTo-Json

Write-Host "`n🚀 Sending registration request to $apiUrl..." -ForegroundColor Cyan
Write-Host "   Institute: INS001" -ForegroundColor Gray
Write-Host "   Roll: ROLL001" -ForegroundColor Gray
Write-Host "   Name: Test Student" -ForegroundColor Gray
Write-Host ""

try {
    # Send POST request
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $requestBody -ContentType "application/json" -ErrorAction Stop
    
    Write-Host "✅ SUCCESS!" -ForegroundColor Green
    Write-Host "`nResponse:" -ForegroundColor Cyan
    $response | ConvertTo-Json -Depth 10
    
} catch {
    Write-Host "`n❌ ERROR!" -ForegroundColor Red
    Write-Host "Status Code: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Yellow
    
    # Try to get error details
    if ($_.ErrorDetails.Message) {
        Write-Host "`nError Details:" -ForegroundColor Yellow
        $errorJson = $_.ErrorDetails.Message | ConvertFrom-Json
        $errorJson | ConvertTo-Json -Depth 10
    } else {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n" -NoNewline

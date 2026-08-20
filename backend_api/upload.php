<?php
/**
 * ✅ Simple PHP Photo Upload API
 *
 * Upload endpoint: POST /upload.php
 *
 * Params:
 * - photo: File upload
 * - sr_no: Student SR number
 * - institute_id: Institute ID
 * - record_type: "entry" or "exit"
 * - date: Date (YYYY-MM-DD)
 *
 * Example:
 * POST /upload.php
 * sr_no=990&institute_id=99099&record_type=entry&date=2026-08-21&photo=<file>
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');

// Enable error reporting
error_reporting(E_ALL);
ini_set('display_errors', 0);

// Log to file instead
$log_file = '/home/digitrix/public_html/attendance-photos/upload.log';

function log_debug($message) {
    global $log_file;
    $timestamp = date('Y-m-d H:i:s');
    $log_entry = "[$timestamp] $message\n";
    file_put_contents($log_file, $log_entry, FILE_APPEND);
    echo "[LOG] $message\n";
}

try {
    log_debug("=== UPLOAD REQUEST START ===");

    // Get parameters
    $sr_no = $_POST['sr_no'] ?? null;
    $institute_id = $_POST['institute_id'] ?? null;
    $record_type = $_POST['record_type'] ?? 'entry';
    $date = $_POST['date'] ?? date('Y-m-d');

    log_debug("SR No: $sr_no");
    log_debug("Institute: $institute_id");
    log_debug("Type: $record_type");
    log_debug("Date: $date");

    // Validate
    if (!$sr_no || !$institute_id) {
        throw new Exception("Missing sr_no or institute_id");
    }

    if (!isset($_FILES['photo'])) {
        throw new Exception("No photo file uploaded");
    }

    $file = $_FILES['photo'];
    log_debug("File: {$file['name']} ({$file['size']} bytes)");

    if ($file['error'] !== UPLOAD_ERR_OK) {
        throw new Exception("Upload error: {$file['error']}");
    }

    // Create directory structure
    $base_dir = "/home/digitrix/public_html/attendance-photos";
    $photo_dir = "$base_dir/$institute_id/$sr_no/$date";

    log_debug("Directory: $photo_dir");

    if (!is_dir($base_dir)) {
        log_debug("ERROR: Base dir does not exist: $base_dir");
        throw new Exception("Base directory not found");
    }

    // Create directories
    if (!is_dir($photo_dir)) {
        log_debug("Creating directory: $photo_dir");
        if (!mkdir($photo_dir, 0777, true)) {
            throw new Exception("Failed to create directory: $photo_dir");
        }
        log_debug("✅ Directory created");
    }

    // Generate filename
    $time_str = date('His');
    $filename = "{$record_type}_{$time_str}.jpg";
    $filepath = "$photo_dir/$filename";

    log_debug("Filename: $filename");
    log_debug("Full path: $filepath");

    // Save file
    log_debug("Saving file...");
    if (!move_uploaded_file($file['tmp_name'], $filepath)) {
        throw new Exception("Failed to save file");
    }

    // Verify
    if (!file_exists($filepath)) {
        throw new Exception("File not found after save");
    }

    $file_size = filesize($filepath);
    log_debug("✅ File saved: $file_size bytes");

    // List directory
    $dir_contents = scandir($photo_dir);
    log_debug("Directory now has " . count($dir_contents) . " items");

    // Generate URL
    $photo_url = "https://digitrixmedia.com/attendance-photos/$institute_id/$sr_no/$date/$filename";

    log_debug("URL: $photo_url");
    log_debug("=== UPLOAD SUCCESS ===");

    // Return response
    echo json_encode([
        'success' => true,
        'photo_url' => $photo_url,
        'filename' => $filename,
        'sr_no' => $sr_no,
        'institute_id' => $institute_id,
        'record_type' => $record_type,
        'file_size_kb' => round($file_size / 1024, 1)
    ]);

} catch (Exception $e) {
    log_debug("❌ ERROR: " . $e->getMessage());
    log_debug("=== UPLOAD FAILED ===");

    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage()
    ]);
}
?>

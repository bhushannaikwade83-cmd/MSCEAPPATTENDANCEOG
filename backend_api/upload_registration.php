<?php
/**
 * ✅ Registration Photo Upload API
 *
 * Saves registration photos (front/left/right) to separate folder
 *
 * Upload endpoint: POST /upload_registration.php
 *
 * Params:
 * - photo: File upload
 * - sr_no: Student SR number
 * - institute_id: Institute ID
 * - angle: "front", "left", or "right"
 *
 * Example:
 * POST /upload_registration.php
 * sr_no=990&institute_id=99099&angle=front&photo=<file>
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');

error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);
ini_set('error_log', '/home/digitrix/public_html/msceattendanceapp/registration-photos/php_errors.log');

$base_dir = "/home/digitrix/public_html/msceattendanceapp/registration-photos";
$log_file = "$base_dir/upload.log";

// Ensure base directory exists
if (!is_dir($base_dir)) {
    mkdir($base_dir, 0777, true);
}

function log_debug($message) {
    global $log_file;
    $timestamp = date('Y-m-d H:i:s');
    $log_entry = "[$timestamp] $message\n";
    @file_put_contents($log_file, $log_entry, FILE_APPEND);
    // Don't echo - breaks JSON response!
}

try {
    log_debug("=== REGISTRATION UPLOAD START ===");

    // Get parameters
    $sr_no = $_POST['sr_no'] ?? null;
    $institute_id = $_POST['institute_id'] ?? null;
    $angle = $_POST['angle'] ?? 'front'; // front, left, right

    log_debug("SR No: $sr_no");
    log_debug("Institute: $institute_id");
    log_debug("Angle: $angle");

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

    // Create directory structure: registration-photos/{student_id}/
    $base_dir = "/home/digitrix/public_html/msceattendanceapp/registration-photos";
    $photo_dir = "$base_dir/$institute_id/$sr_no";

    log_debug("Directory: $photo_dir");

    if (!is_dir($base_dir)) {
        log_debug("ERROR: Base dir does not exist: $base_dir");
        throw new Exception("Base directory not found");
    }

    // Create directories (with error suppression for race conditions)
    if (!is_dir($photo_dir)) {
        log_debug("Creating directory: $photo_dir");
        if (!@mkdir($photo_dir, 0777, true) && !is_dir($photo_dir)) {
            throw new Exception("Failed to create directory: $photo_dir");
        }
        log_debug("✅ Directory created/verified");
    }

    // Generate filename with timestamp: front_2026-08-22_14-30-45.jpg
    $timestamp = date('Y-m-d_H-i-s');
    $filename = "{$angle}_{$timestamp}.jpg";
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

    // Generate URL
    $photo_url = "https://digitrixmedia.com/msceattendanceapp/registration-photos/$institute_id/$sr_no/$filename";

    log_debug("URL: $photo_url");
    log_debug("=== REGISTRATION UPLOAD SUCCESS ===");

    // Return response
    echo json_encode([
        'success' => true,
        'photo_url' => $photo_url,
        'filename' => $filename,
        'sr_no' => $sr_no,
        'institute_id' => $institute_id,
        'angle' => $angle,
        'file_size_kb' => round($file_size / 1024, 1)
    ]);

} catch (Exception $e) {
    log_debug("❌ ERROR: " . $e->getMessage());
    log_debug("Stack: " . $e->getTraceAsString());
    log_debug("=== REGISTRATION UPLOAD FAILED ===");

    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage(),
        'type' => get_class($e),
        'line' => $e->getLine(),
        'file' => $e->getFile(),
        'timestamp' => date('Y-m-d H:i:s UTC'),
        'debug_info' => [
            'base_dir_exists' => is_dir($base_dir ?? 'N/A'),
            'photo_dir_exists' => isset($photo_dir) ? is_dir($photo_dir) : false,
            'institute_id' => $_POST['institute_id'] ?? 'N/A',
            'sr_no' => $_POST['sr_no'] ?? 'N/A',
            'angle' => $_POST['angle'] ?? 'N/A',
        ]
    ]);
}
?>

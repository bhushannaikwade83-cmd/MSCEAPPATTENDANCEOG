<?php
/**
 * Import students and attendance data from Supabase to MariaDB
 * Usage: php import_from_supabase.php students
 *        php import_from_supabase.php attendance
 */

// Load .env file from app root
$envPath = __DIR__ . '/../.env';
if (!file_exists($envPath)) {
    die("❌ Error: .env file not found at $envPath\n");
}

$envVars = parse_ini_file($envPath);
if (!$envVars) {
    die("❌ Error: Could not parse .env file\n");
}

// Supabase connection
$supabaseUrl = $envVars['SUPABASE_URL'] ?? null;
$supabaseKey = $envVars['SUPABASE_ANON_KEY'] ?? null;

if (!$supabaseUrl || !$supabaseKey) {
    die("❌ Error: Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env\n");
}

// MariaDB connection
$mariadbHost = $envVars['MARIADB_HOST'] ?? 'localhost';
$mariadbUser = $envVars['MARIADB_USER'] ?? 'root';
$mariadbPass = $envVars['MARIADB_PASS'] ?? '';
$mariadbDb = $envVars['MARIADB_DB'] ?? 'msce_attendance';

$mysqli = new mysqli($mariadbHost, $mariadbUser, $mariadbPass, $mariadbDb);
if ($mysqli->connect_error) {
    die("MariaDB Connection Error: " . $mysqli->connect_error . "\n");
}
$mysqli->set_charset("utf8mb4");

// Log file
$logFile = '/tmp/supabase_import_' . date('Y-m-d_H-i-s') . '.log';
file_put_contents($logFile, "=== Supabase → MariaDB Import Started ===\n" . date('Y-m-d H:i:s') . "\n\n");

function log_msg($msg) {
    global $logFile;
    echo $msg . "\n";
    file_put_contents($logFile, $msg . "\n", FILE_APPEND);
}

// Get table to import
$table = $argv[1] ?? 'students';

if ($table === 'students') {
    importStudents($supabaseUrl, $supabaseKey, $mysqli, $logFile);
} elseif ($table === 'attendance') {
    importAttendance($supabaseUrl, $supabaseKey, $mysqli, $logFile);
} else {
    log_msg("Usage: php import_from_supabase.php [students|attendance]");
    exit(1);
}

function importStudents($url, $key, $mysqli, $logFile) {
    log_msg("\n=== Importing STUDENTS ===\n");

    // Fetch from Supabase with pagination
    $page = 0;
    $pageSize = 100;
    $totalImported = 0;

    while (true) {
        $offset = $page * $pageSize;
        $endpoint = $url . '/rest/v1/students?limit=' . $pageSize . '&offset=' . $offset;

        $ch = curl_init($endpoint);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Authorization: Bearer ' . $key,
            'apikey: ' . $key,
            'Accept: application/json'
        ]);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        $response = curl_exec($ch);
        curl_close($ch);

        $data = json_decode($response, true);
        if (empty($data)) break;

        foreach ($data as $student) {
            $stmt = $mysqli->prepare("
                INSERT INTO students (
                    id, sr_no, institute_id, fname, mname, lname, student_name,
                    mother_nm, ctcd, identy_no, mobno, pmobno, year, allotted_hours,
                    sub1, sub2, sub3, sub4, sub5, sub6, sub7, sub8,
                    is_process, is_pay, is_delete_new, is_phname, status,
                    face_photo_url, face_photo_change_count, face_photo_change_disabled, photo_version,
                    face_embedding_front, face_embedding_left, face_embedding_right,
                    face_registered_at, face_registration_status, is_face_real, spoof_check_count,
                    old_face_registered_at, face_reset_snapshot, payid, created_at, updated_at
                ) VALUES (
                    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                    ?, ?, ?, ?, ?, ?, ?,
                    ?, ?, ?, ?, ?, ?, ?, ?, ?
                )
            ");

            $stmt->bind_param(
                'sssssssssssssd' .
                'ssssssss' .
                'iiiii' .
                'ssiis' .
                'sssissi' .
                'ss',
                $student['id'],
                $student['sr_no'],
                $student['institute_id'],
                $student['fname'],
                $student['mname'],
                $student['lname'],
                $student['student_name'],
                $student['mother_nm'],
                $student['ctcd'],
                $student['identy_no'],
                $student['mobno'],
                $student['pmobno'],
                $student['year'],
                (float)($student['allotted_hours'] ?? 0),
                $student['sub1'],
                $student['sub2'],
                $student['sub3'],
                $student['sub4'],
                $student['sub5'],
                $student['sub6'],
                $student['sub7'],
                $student['sub8'],
                (int)($student['is_process'] ?? 0),
                (int)($student['is_pay'] ?? 0),
                (int)($student['is_delete_new'] ?? 0),
                $student['is_phname'],
                (int)($student['status'] ?? 1),
                $student['face_photo_url'],
                (int)($student['face_photo_change_count'] ?? 0),
                (int)($student['face_photo_change_disabled'] ?? 0),
                (int)($student['photo_version'] ?? 0),
                json_encode($student['face_embedding_front'] ?? []),
                json_encode($student['face_embedding_left'] ?? []),
                json_encode($student['face_embedding_right'] ?? []),
                $student['face_registered_at'],
                $student['face_registration_status'] ?? 'pending',
                (int)($student['is_face_real'] ?? 0),
                (int)($student['spoof_check_count'] ?? 0),
                $student['old_face_registered_at'],
                $student['face_reset_snapshot'],
                $student['payid'],
                $student['created_at'],
                $student['updated_at']
            );

            if (!$stmt->execute()) {
                log_msg("Error inserting student {$student['id']}: " . $stmt->error);
            } else {
                $totalImported++;
            }
            $stmt->close();
        }

        log_msg("Imported batch " . ($page + 1) . " (" . count($data) . " records, total: $totalImported)");
        $page++;

        if (count($data) < $pageSize) break;
    }

    log_msg("\n✅ Students import completed: $totalImported records\n");
}

function importAttendance($url, $key, $mysqli, $logFile) {
    log_msg("\n=== Importing ATTENDANCE ===\n");

    // Fetch from Supabase with pagination
    $page = 0;
    $pageSize = 100;
    $totalImported = 0;

    while (true) {
        $offset = $page * $pageSize;
        $endpoint = $url . '/rest/v1/attendance?limit=' . $pageSize . '&offset=' . $offset;

        $ch = curl_init($endpoint);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Authorization: Bearer ' . $key,
            'apikey: ' . $key,
            'Accept: application/json'
        ]);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        $response = curl_exec($ch);
        curl_close($ch);

        $data = json_decode($response, true);
        if (empty($data)) break;

        foreach ($data as $record) {
            $stmt = $mysqli->prepare("
                INSERT INTO attendance (
                    id, student_id, institute_id, attendance_date,
                    entry_time, entry_photo_url, entry_gps_lat, entry_gps_lng,
                    exit_time, exit_photo_url, exit_gps_lat, exit_gps_lng,
                    attendance_status, is_on_leave, leave_reason,
                    device_info, is_verified, verified_by, verified_at,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ");

            $stmt->bind_param(
                'sssss' .
                'ssdd' .
                'ssdd' .
                'siss' .
                'siss',
                $record['id'],
                $record['student_id'],
                $record['institute_id'],
                $record['attendance_date'],
                $record['entry_time'],
                $record['entry_photo_url'],
                (float)($record['entry_gps_lat'] ?? 0),
                (float)($record['entry_gps_lng'] ?? 0),
                $record['exit_time'],
                $record['exit_photo_url'],
                (float)($record['exit_gps_lat'] ?? 0),
                (float)($record['exit_gps_lng'] ?? 0),
                $record['attendance_status'] ?? 'marked',
                (int)($record['is_on_leave'] ?? 0),
                $record['leave_reason'],
                $record['device_info'],
                (int)($record['is_verified'] ?? 1),
                $record['verified_by'],
                $record['verified_at'],
                $record['created_at'],
                $record['updated_at']
            );

            if (!$stmt->execute()) {
                log_msg("Error inserting attendance {$record['id']}: " . $stmt->error);
            } else {
                $totalImported++;
            }
            $stmt->close();
        }

        log_msg("Imported batch " . ($page + 1) . " (" . count($data) . " records, total: $totalImported)");
        $page++;

        if (count($data) < $pageSize) break;
    }

    log_msg("\n✅ Attendance import completed: $totalImported records\n");
}

log_msg("\nLog saved to: $logFile");
$mysqli->close();
?>

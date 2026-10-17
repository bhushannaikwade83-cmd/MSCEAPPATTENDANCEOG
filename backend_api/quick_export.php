<?php
/**
 * Quick export of all students from Supabase
 * Direct export without pagination (for small datasets)
 * Loads credentials from app's .env file
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

// Supabase credentials
$supabaseUrl = $envVars['SUPABASE_URL'] ?? null;
$supabaseKey = $envVars['SUPABASE_ANON_KEY'] ?? null;

if (!$supabaseUrl || !$supabaseKey) {
    die("❌ Error: Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env\n");
}

log_msg("=== Quick Export: Supabase → MariaDB ===\n");

// Fetch with pagination (1000 per batch for 9000 students)
$batchSize = 1000;
$page = 0;
$allStudents = [];
$totalFetched = 0;

log_msg("📥 Fetching students from Supabase (pagination: $batchSize per batch)\n");

while (true) {
    $offset = $page * $batchSize;
    $endpoint = $supabaseUrl . '/rest/v1/students?limit=' . $batchSize . '&offset=' . $offset;

    log_msg("   Page " . ($page + 1) . " (offset: $offset)...");

    $ch = curl_init($endpoint);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Authorization: Bearer ' . $supabaseKey,
        'apikey: ' . $supabaseKey,
        'Accept: application/json'
    ]);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 60);

    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($httpCode !== 200) {
        log_msg("❌ Error: HTTP $httpCode\n");
        log_msg("Response: " . substr($response, 0, 500) . "\n");
        exit(1);
    }

    $batch = json_decode($response, true);
    $batchCount = count($batch);

    if ($batchCount === 0) {
        log_msg(" Done!\n");
        break;
    }

    $allStudents = array_merge($allStudents, $batch);
    $totalFetched += $batchCount;
    log_msg(" ✅ " . $batchCount . " records (total: $totalFetched)\n");

    $page++;

    // Prevent memory bloat
    if ($totalFetched % 5000 === 0) {
        log_msg("   💾 Memory usage: " . round(memory_get_usage() / 1024 / 1024, 2) . " MB\n");
    }
}

$students = $allStudents;
log_msg("\n✅ Fetched " . count($students) . " students from Supabase\n\n");

// MariaDB credentials from .env
$mariadbHost = $envVars['MARIADB_HOST'] ?? 'localhost';
$mariadbUser = $envVars['MARIADB_USER'] ?? 'root';
$mariadbPass = $envVars['MARIADB_PASS'] ?? '';
$mariadbDb = $envVars['MARIADB_DB'] ?? 'msce_attendance';

$mysqli = new mysqli($mariadbHost, $mariadbUser, $mariadbPass, $mariadbDb);
if ($mysqli->connect_error) {
    log_msg("❌ MariaDB Error: " . $mysqli->connect_error . "\n");
    exit(1);
}
$mysqli->set_charset("utf8mb4");

log_msg("📡 Connected to MariaDB: $mariadbDb\n\n");

// Insert in batches (100 at a time for better performance)
$successCount = 0;
$errorCount = 0;
$batchInsertSize = 100;
$totalStudents = count($students);

log_msg("📤 Inserting " . number_format($totalStudents) . " students into MariaDB\n");
log_msg("   (Batch size: $batchInsertSize records)\n\n");

$startTime = time();

for ($i = 0; $i < $totalStudents; $i += $batchInsertSize) {
    $batch = array_slice($students, $i, $batchInsertSize);
    $progressPercent = round(($i / $totalStudents) * 100);
    log_msg("   [$progressPercent%] Inserting batch " . ($i / $batchInsertSize + 1) . "...");

    $mysqli->begin_transaction();

    foreach ($batch as $student) {
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
            ON DUPLICATE KEY UPDATE
                fname = VALUES(fname),
                lname = VALUES(lname),
                face_photo_url = VALUES(face_photo_url),
                face_registration_status = VALUES(face_registration_status),
                updated_at = NOW()
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

        if ($stmt->execute()) {
            $successCount++;
        } else {
            $errorCount++;
        }
        $stmt->close();
    }

    $mysqli->commit();
    $elapsedTime = time() - $startTime;
    log_msg(" ✅ " . count($batch) . " records (Elapsed: " . $elapsedTime . "s)\n");
}

$totalTime = time() - $startTime;
$recordsPerSecond = $totalStudents > 0 ? round($totalStudents / $totalTime) : 0;

log_msg("\n" . str_repeat("=", 60));
log_msg("📊 IMPORT SUMMARY:");
log_msg("   ✅ Success:          " . number_format($successCount));
log_msg("   ❌ Errors:           " . number_format($errorCount));
log_msg("   📅 Total:            " . number_format(count($students)) . " students");
log_msg("   ⏱️  Time Taken:        " . $totalTime . " seconds");
log_msg("   ⚡ Speed:            $recordsPerSecond records/second");
log_msg("   💾 Memory Peak:      " . round(memory_get_peak_usage() / 1024 / 1024, 2) . " MB");
log_msg(str_repeat("=", 60) . "\n");

// Verify inserted data
$result = $mysqli->query("SELECT COUNT(*) as total FROM students");
$row = $result->fetch_assoc();
log_msg("✅ Database now has: " . number_format($row['total']) . " students\n");

// Statistics
log_msg("📈 Statistics:\n");
$result = $mysqli->query("
    SELECT
        COUNT(*) as total,
        SUM(CASE WHEN face_registration_status = 'registered' THEN 1 ELSE 0 END) as registered,
        SUM(CASE WHEN face_registration_status = 'pending' THEN 1 ELSE 0 END) as pending,
        COUNT(DISTINCT institute_id) as institutes
    FROM students
");
$stats = $result->fetch_assoc();
log_msg("   Total Students:     " . number_format($stats['total']));
log_msg("   Registered Faces:   " . number_format($stats['registered'] ?? 0) . " (" . ($stats['total'] > 0 ? round(($stats['registered'] / $stats['total']) * 100) : 0) . "%)");
log_msg("   Pending Faces:      " . number_format($stats['pending'] ?? 0));
log_msg("   Institutes:         " . $stats['institutes']);

// Show sample
log_msg("\n📋 Sample Students (Last 10):\n");
$result = $mysqli->query("SELECT sr_no, student_name, institute_id, face_registration_status FROM students ORDER BY created_at DESC LIMIT 10");
while ($row = $result->fetch_assoc()) {
    $status = ($row['face_registration_status'] === 'registered') ? '✅' : '⏳';
    log_msg("  $status {$row['sr_no']} | {$row['student_name']} (Institute: {$row['institute_id']})");
}

$mysqli->close();

function log_msg($msg) {
    echo $msg . "\n";
}
?>

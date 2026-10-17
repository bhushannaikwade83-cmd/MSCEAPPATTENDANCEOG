<?php
/**
 * Attendance API - MariaDB Version
 * Handles all attendance operations
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

$db_host = getenv('DB_HOST') ?: 'localhost';
$db_user = getenv('DB_USER') ?: 'digitrix_msce_attendance_app_user';
$db_pass = getenv('DB_PASS') ?: 'Bhushan@70';
$db_name = getenv('DB_NAME') ?: 'digitrix_msce_attendance_app';

$conn = new mysqli($db_host, $db_user, $db_pass, $db_name);
if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => 'DB connection failed: ' . $conn->connect_error]);
    exit;
}
$conn->set_charset("utf8mb4");

$action = $_GET['action'] ?? '';

try {
    switch ($action) {
        // ✅ GET DAILY ATTENDANCE
        case 'get-daily-attendance':
            $institute_id = $_GET['institute_id'] ?? null;
            $date = $_GET['date'] ?? date('Y-m-d');

            if (!$institute_id) {
                http_response_code(400);
                echo json_encode(['success' => false, 'error' => 'institute_id required']);
                break;
            }

            $query = "SELECT id, sr_no, institute_id, record_type, similarity, photo_url, marked_time, status
                      FROM attendance
                      WHERE institute_id = ? AND DATE(marked_time) = ?
                      ORDER BY marked_time DESC";

            $stmt = $conn->prepare($query);
            if (!$stmt) {
                http_response_code(500);
                echo json_encode(['success' => false, 'error' => 'Prepare failed: ' . $conn->error]);
                break;
            }

            $stmt->bind_param("ss", $institute_id, $date);
            if (!$stmt->execute()) {
                http_response_code(500);
                echo json_encode(['success' => false, 'error' => 'Execute failed: ' . $stmt->error]);
                break;
            }

            $result = $stmt->get_result();
            $records = [];
            while ($row = $result->fetch_assoc()) {
                $records[] = $row;
            }

            echo json_encode([
                'success' => true,
                'attendance' => $records,
                'count' => count($records)
            ]);
            $stmt->close();
            break;

        // ✅ MARK ATTENDANCE (ENTRY/EXIT)
        case 'mark-attendance':
            $data = json_decode(file_get_contents('php://input'), true);

            $id = $data['id'] ?? bin2hex(random_bytes(16));
            $sr_no = $data['sr_no'] ?? '';
            $institute_id = $data['institute_id'] ?? '';
            $record_type = $data['record_type'] ?? 'entry';
            $similarity = floatval($data['similarity'] ?? 0);
            $photo_url = $data['photo_url'] ?? '';
            $status = $data['status'] ?? 'present';
            $marked_time = date('Y-m-d H:i:s');
            $attendance_date = date('Y-m-d');

            if (!$sr_no || !$institute_id) {
                http_response_code(400);
                echo json_encode(['success' => false, 'error' => 'sr_no and institute_id required']);
                break;
            }

            $query = "INSERT INTO attendance (id, sr_no, institute_id, attendance_date, record_type, similarity, photo_url, status, marked_time)
                      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";

            $stmt = $conn->prepare($query);
            if (!$stmt) {
                http_response_code(500);
                echo json_encode(['success' => false, 'error' => 'Prepare failed: ' . $conn->error]);
                break;
            }

            $stmt->bind_param("ssssdsss", $id, $sr_no, $institute_id, $attendance_date, $record_type, $similarity, $photo_url, $status, $marked_time);

            if ($stmt->execute()) {
                echo json_encode([
                    'success' => true,
                    'id' => $id,
                    'record_type' => $record_type,
                    'marked_time' => $marked_time
                ]);
            } else {
                http_response_code(500);
                echo json_encode(['success' => false, 'error' => 'Insert failed: ' . $stmt->error]);
            }
            $stmt->close();
            break;

        // ✅ GET ATTENDANCE STATS
        case 'get-attendance-stats':
            $institute_id = $_GET['institute_id'] ?? null;
            $date = $_GET['date'] ?? date('Y-m-d');

            if (!$institute_id) {
                http_response_code(400);
                echo json_encode(['success' => false, 'error' => 'institute_id required']);
                break;
            }

            // Count present (entry records)
            $query = "SELECT COUNT(DISTINCT sr_no) as present FROM attendance
                      WHERE institute_id = ? AND DATE(marked_time) = ? AND record_type = 'entry'";

            $stmt = $conn->prepare($query);
            if (!$stmt) {
                http_response_code(500);
                echo json_encode(['success' => false, 'error' => 'Prepare failed: ' . $conn->error]);
                break;
            }

            $stmt->bind_param("ss", $institute_id, $date);
            $stmt->execute();
            $present = $stmt->get_result()->fetch_assoc()['present'] ?? 0;
            $stmt->close();

            // Count total students
            $count_query = "SELECT COUNT(*) as total FROM students WHERE institute_id = ?";
            $count_stmt = $conn->prepare($count_query);
            if (!$count_stmt) {
                http_response_code(500);
                echo json_encode(['success' => false, 'error' => 'Prepare failed: ' . $conn->error]);
                break;
            }

            $count_stmt->bind_param("s", $institute_id);
            $count_stmt->execute();
            $total = $count_stmt->get_result()->fetch_assoc()['total'] ?? 0;
            $count_stmt->close();

            echo json_encode([
                'success' => true,
                'total' => intval($total),
                'present' => intval($present),
                'absent' => intval($total - $present)
            ]);
            break;

        // ✅ HEALTH CHECK
        case 'health':
            echo json_encode(['success' => true, 'message' => 'Attendance API OK']);
            break;

        default:
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => "Unknown action: $action"]);
    }
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => 'Exception: ' . $e->getMessage()]);
}

$conn->close();
?>

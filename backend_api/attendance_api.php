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
$db_user = getenv('DB_USER') ?: 'root';
$db_pass = getenv('DB_PASS') ?: '';
$db_name = getenv('DB_NAME') ?: 'attendance';

$conn = new mysqli($db_host, $db_user, $db_pass, $db_name);
if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => 'DB error: ' . $conn->connect_error]);
    exit;
}
$conn->set_charset("utf8mb4");

$action = $_GET['action'] ?? '';

try {
    switch ($action) {
        case 'get-daily-attendance':
            $institute_id = $_GET['institute_id'] ?? null;
            $date = $_GET['date'] ?? date('Y-m-d');
            
            if (!$institute_id) {
                http_response_code(400);
                echo json_encode(['success' => false, 'error' => 'institute_id required']);
                break;
            }
            
            $query = "SELECT sr_no, record_type, marked_time, similarity FROM attendance 
                      WHERE institute_id = ? AND DATE(marked_time) = ? 
                      ORDER BY sr_no, marked_time";
            $stmt = $conn->prepare($query);
            $stmt->bind_param("ss", $institute_id, $date);
            $stmt->execute();
            $result = $stmt->get_result();
            
            $records = [];
            while ($row = $result->fetch_assoc()) {
                $records[] = $row;
            }
            
            echo json_encode(['success' => true, 'data' => $records]);
            break;

        case 'mark-attendance':
            $data = json_decode(file_get_contents('php://input'), true);
            
            $id = $data['id'] ?? bin2hex(random_bytes(16));
            $sr_no = $data['sr_no'] ?? '';
            $institute_id = $data['institute_id'] ?? '';
            $record_type = $data['record_type'] ?? 'entry';
            $similarity = floatval($data['similarity'] ?? 0);
            $marked_time = date('Y-m-d H:i:s');
            
            $query = "INSERT INTO attendance (id, sr_no, institute_id, record_type, similarity, marked_time)
                      VALUES (?, ?, ?, ?, ?, ?)";
            $stmt = $conn->prepare($query);
            $stmt->bind_param("sssds", $id, $sr_no, $institute_id, $record_type, $similarity, $marked_time);
            
            if ($stmt->execute()) {
                echo json_encode(['success' => true, 'id' => $id]);
            } else {
                http_response_code(500);
                echo json_encode(['success' => false, 'error' => $conn->error]);
            }
            break;

        case 'get-attendance-stats':
            $institute_id = $_GET['institute_id'] ?? null;
            $date = $_GET['date'] ?? date('Y-m-d');
            
            if (!$institute_id) {
                http_response_code(400);
                echo json_encode(['success' => false, 'error' => 'institute_id required']);
                break;
            }
            
            $query = "SELECT COUNT(DISTINCT sr_no) as present FROM attendance 
                      WHERE institute_id = ? AND DATE(marked_time) = ?";
            $stmt = $conn->prepare($query);
            $stmt->bind_param("ss", $institute_id, $date);
            $stmt->execute();
            $present = $stmt->get_result()->fetch_assoc()['present'];
            
            $count_query = "SELECT COUNT(*) as total FROM students WHERE institute_id = ?";
            $count_stmt = $conn->prepare($count_query);
            $count_stmt->bind_param("s", $institute_id);
            $count_stmt->execute();
            $total = $count_stmt->get_result()->fetch_assoc()['total'];
            
            echo json_encode([
                'success' => true,
                'total' => $total,
                'present' => $present,
                'absent' => $total - $present
            ]);
            break;

        default:
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => 'Unknown action']);
    }
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}

$conn->close();
?>

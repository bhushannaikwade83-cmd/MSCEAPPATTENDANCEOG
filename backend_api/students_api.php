<?php
/**
 * Students API - MariaDB Version
 * Handles all student operations for face recognition system
 * Replaces Supabase with local MariaDB
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// ============================================
// DATABASE CONNECTION
// ============================================

$db_host = getenv('DB_HOST') ?: 'localhost';
$db_user = getenv('DB_USER') ?: 'root';
$db_pass = getenv('DB_PASS') ?: '';
$db_name = getenv('DB_NAME') ?: 'attendance';

try {
    $conn = new mysqli($db_host, $db_user, $db_pass, $db_name);

    if ($conn->connect_error) {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'Database connection failed: ' . $conn->connect_error
        ]);
        exit;
    }

    $conn->set_charset("utf8mb4");
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'Connection error: ' . $e->getMessage()
    ]);
    exit;
}

// ============================================
// API ROUTING
// ============================================

$request_method = $_SERVER['REQUEST_METHOD'];
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

// Extract action from query string
$action = $_GET['action'] ?? '';

log_debug("[API] $request_method $path?action=$action");

try {
    switch ($action) {
        // ===== READ OPERATIONS =====
        case 'get-students':
            handle_get_students($conn);
            break;

        case 'get-embeddings':
            handle_get_embeddings($conn);
            break;

        case 'get-student':
            handle_get_student($conn);
            break;

        case 'search-students':
            handle_search_students($conn);
            break;

        case 'count-students':
            handle_count_students($conn);
            break;

        // ===== WRITE OPERATIONS =====
        case 'add-student':
            handle_add_student($conn);
            break;

        case 'update-student':
            handle_update_student($conn);
            break;

        case 'update-embeddings':
            handle_update_embeddings($conn);
            break;

        case 'delete-student':
            handle_delete_student($conn);
            break;

        // ===== UTILITY =====
        case 'health':
            echo json_encode(['success' => true, 'message' => 'Students API OK']);
            break;

        default:
            http_response_code(400);
            echo json_encode([
                'success' => false,
                'error' => "Unknown action: $action"
            ]);
    }
} catch (Exception $e) {
    log_debug("[ERROR] " . $e->getMessage());
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage()
    ]);
}

$conn->close();

// ============================================
// HANDLER FUNCTIONS
// ============================================

/**
 * GET /students_api.php?action=get-students
 * List students with pagination, search, and filtering
 *
 * Params:
 *   - institute_id (required)
 *   - page (optional, default 0)
 *   - limit (optional, default 50)
 *   - search (optional, search term)
 */
function handle_get_students($conn) {
    $institute_id = $_GET['institute_id'] ?? null;
    $page = intval($_GET['page'] ?? 0);
    $limit = intval($_GET['limit'] ?? 50);
    $search = $_GET['search'] ?? '';

    if (!$institute_id) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'institute_id required']);
        return;
    }

    // Build query
    $query = "SELECT * FROM students WHERE institute_id = ?";
    $params = [$institute_id];
    $types = "s";

    // Add search filter
    if (!empty($search)) {
        $query .= " AND (fname LIKE ? OR lname LIKE ? OR sr_no LIKE ?)";
        $search_term = "%$search%";
        $params = array_merge($params, [$search_term, $search_term, $search_term]);
        $types .= "sss";
    }

    // Add sorting and pagination
    $offset = $page * $limit;
    $query .= " ORDER BY sr_no ASC, id ASC LIMIT ? OFFSET ?";
    $params[] = $limit;
    $params[] = $offset;
    $types .= "ii";

    // Execute query
    $stmt = $conn->prepare($query);
    if (!$stmt) {
        throw new Exception("Prepare failed: " . $conn->error);
    }

    $stmt->bind_param($types, ...$params);
    $start_time = microtime(true);
    $stmt->execute();
    $query_time = microtime(true) - $start_time;

    $result = $stmt->get_result();
    $students = [];

    while ($row = $result->fetch_assoc()) {
        // Decode JSON embeddings
        if (!empty($row['face_embedding_front'])) {
            $row['face_embedding_front'] = json_decode($row['face_embedding_front']);
        }
        if (!empty($row['face_embedding_left'])) {
            $row['face_embedding_left'] = json_decode($row['face_embedding_left']);
        }
        if (!empty($row['face_embedding_right'])) {
            $row['face_embedding_right'] = json_decode($row['face_embedding_right']);
        }
        $students[] = $row;
    }

    // Get total count
    $count_query = "SELECT COUNT(*) as total FROM students WHERE institute_id = ?";
    $count_params = [$institute_id];
    if (!empty($search)) {
        $count_query .= " AND (fname LIKE ? OR lname LIKE ? OR sr_no LIKE ?)";
        $count_params = array_merge($count_params, [$search_term, $search_term, $search_term]);
    }

    $count_stmt = $conn->prepare($count_query);
    $count_stmt->bind_param(str_repeat("s", count($count_params)), ...$count_params);
    $count_stmt->execute();
    $count_result = $count_stmt->get_result();
    $total = $count_result->fetch_assoc()['total'];

    log_debug("✅ Fetched " . count($students) . " students in {$query_time}ms");

    echo json_encode([
        'success' => true,
        'data' => $students,
        'total' => $total,
        'page' => $page,
        'limit' => $limit,
        'query_time_ms' => round($query_time * 1000, 2)
    ]);
}

/**
 * GET /students_api.php?action=get-embeddings
 * Get all registered student embeddings for face matching
 * CRITICAL FOR PERFORMANCE - Called during every attendance marking
 *
 * Params:
 *   - institute_id (required)
 */
function handle_get_embeddings($conn) {
    $institute_id = $_GET['institute_id'] ?? null;

    if (!$institute_id) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'institute_id required']);
        return;
    }

    log_debug("🔍 Loading embeddings for institute $institute_id...");

    $start_time = microtime(true);

    // Only select registered students with embeddings
    $query = "SELECT id, sr_no, fname, lname, face_embedding_front, face_embedding_left, face_embedding_right
              FROM students
              WHERE institute_id = ? AND face_registration_status = 'registered'
              ORDER BY sr_no ASC";

    $stmt = $conn->prepare($query);
    if (!$stmt) {
        throw new Exception("Prepare failed: " . $conn->error);
    }

    $stmt->bind_param("s", $institute_id);
    $stmt->execute();
    $result = $stmt->get_result();

    $students = [];
    while ($row = $result->fetch_assoc()) {
        // Decode JSON embeddings
        $row['face_embedding_front'] = json_decode($row['face_embedding_front'], true);
        $row['face_embedding_left'] = json_decode($row['face_embedding_left'], true);
        $row['face_embedding_right'] = json_decode($row['face_embedding_right'], true);
        $students[] = $row;
    }

    $query_time = microtime(true) - $start_time;

    log_debug("✅ Loaded " . count($students) . " embeddings in {$query_time}s");

    echo json_encode([
        'success' => true,
        'students' => $students,
        'count' => count($students),
        'query_time_sec' => round($query_time, 3)
    ]);
}

/**
 * GET /students_api.php?action=get-student&id=xxx
 * Get single student by ID
 */
function handle_get_student($conn) {
    $student_id = $_GET['id'] ?? null;

    if (!$student_id) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'id required']);
        return;
    }

    $query = "SELECT * FROM students WHERE id = ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("s", $student_id);
    $stmt->execute();
    $result = $stmt->get_result();

    if ($row = $result->fetch_assoc()) {
        // Decode embeddings
        if (!empty($row['face_embedding_front'])) {
            $row['face_embedding_front'] = json_decode($row['face_embedding_front']);
        }
        if (!empty($row['face_embedding_left'])) {
            $row['face_embedding_left'] = json_decode($row['face_embedding_left']);
        }
        if (!empty($row['face_embedding_right'])) {
            $row['face_embedding_right'] = json_decode($row['face_embedding_right']);
        }

        echo json_encode(['success' => true, 'student' => $row]);
    } else {
        http_response_code(404);
        echo json_encode(['success' => false, 'error' => 'Student not found']);
    }
}

/**
 * GET /students_api.php?action=search-students
 * Search students
 */
function handle_search_students($conn) {
    $institute_id = $_GET['institute_id'] ?? null;
    $query_term = $_GET['q'] ?? '';

    if (!$institute_id || !$query_term) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'institute_id and q required']);
        return;
    }

    $search = "%$query_term%";
    $query = "SELECT id, sr_no, fname, lname, face_photo_url FROM students
              WHERE institute_id = ? AND (fname LIKE ? OR lname LIKE ? OR sr_no LIKE ?)
              LIMIT 20";

    $stmt = $conn->prepare($query);
    $stmt->bind_param("ssss", $institute_id, $search, $search, $search);
    $stmt->execute();
    $result = $stmt->get_result();

    $students = [];
    while ($row = $result->fetch_assoc()) {
        $students[] = $row;
    }

    echo json_encode(['success' => true, 'results' => $students]);
}

/**
 * GET /students_api.php?action=count-students&institute_id=xxx
 * Count total students in institute
 */
function handle_count_students($conn) {
    $institute_id = $_GET['institute_id'] ?? null;

    if (!$institute_id) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'institute_id required']);
        return;
    }

    $query = "SELECT COUNT(*) as total FROM students WHERE institute_id = ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("s", $institute_id);
    $stmt->execute();
    $result = $stmt->get_result();
    $row = $result->fetch_assoc();

    echo json_encode(['success' => true, 'total' => $row['total']]);
}

/**
 * POST /students_api.php?action=add-student
 * Add new student
 */
function handle_add_student($conn) {
    $data = json_decode(file_get_contents('php://input'), true);

    $required = ['sr_no', 'fname', 'institute_id'];
    foreach ($required as $field) {
        if (empty($data[$field])) {
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => "Missing: $field"]);
            return;
        }
    }

    $id = $data['id'] ?? bin2hex(random_bytes(16));
    $sr_no = $data['sr_no'];
    $fname = $data['fname'];
    $lname = $data['lname'] ?? '';
    $mname = $data['mname'] ?? '';
    $institute_id = $data['institute_id'];
    $status = $data['status'] ?? 'active';
    $created_at = date('Y-m-d H:i:s');

    $query = "INSERT INTO students (id, sr_no, fname, lname, mname, institute_id, status, created_at, updated_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";

    $stmt = $conn->prepare($query);
    if (!$stmt) {
        throw new Exception("Prepare failed: " . $conn->error);
    }

    $stmt->bind_param("sssssss", $id, $sr_no, $fname, $lname, $mname, $institute_id, $status, $created_at, $created_at);

    if ($stmt->execute()) {
        echo json_encode(['success' => true, 'id' => $id]);
    } else {
        http_response_code(500);
        echo json_encode(['success' => false, 'error' => $conn->error]);
    }
}

/**
 * PUT /students_api.php?action=update-student
 * Update student info
 */
function handle_update_student($conn) {
    $data = json_decode(file_get_contents('php://input'), true);

    if (empty($data['id'])) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'id required']);
        return;
    }

    $id = $data['id'];
    $updates = [];
    $params = [];
    $types = "";

    $allowed = ['sr_no', 'fname', 'lname', 'mname', 'face_photo_url', 'status'];

    foreach ($allowed as $field) {
        if (isset($data[$field])) {
            $updates[] = "$field = ?";
            $params[] = $data[$field];
            $types .= "s";
        }
    }

    if (empty($updates)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Nothing to update']);
        return;
    }

    $updates[] = "updated_at = ?";
    $params[] = date('Y-m-d H:i:s');
    $types .= "s";

    $params[] = $id;
    $types .= "s";

    $query = "UPDATE students SET " . implode(", ", $updates) . " WHERE id = ?";

    $stmt = $conn->prepare($query);
    $stmt->bind_param($types, ...$params);

    if ($stmt->execute()) {
        echo json_encode(['success' => true]);
    } else {
        http_response_code(500);
        echo json_encode(['success' => false, 'error' => $conn->error]);
    }
}

/**
 * PUT /students_api.php?action=update-embeddings
 * Update face embeddings (critical for registration)
 */
function handle_update_embeddings($conn) {
    $data = json_decode(file_get_contents('php://input'), true);

    if (empty($data['id'])) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'id required']);
        return;
    }

    $id = $data['id'];
    $front = $data['face_embedding_front'] ? json_encode($data['face_embedding_front']) : null;
    $left = $data['face_embedding_left'] ? json_encode($data['face_embedding_left']) : null;
    $right = $data['face_embedding_right'] ? json_encode($data['face_embedding_right']) : null;
    $registration_status = $data['face_registration_status'] ?? 'registered';
    $now = date('Y-m-d H:i:s');

    $query = "UPDATE students SET
              face_embedding_front = ?,
              face_embedding_left = ?,
              face_embedding_right = ?,
              face_registration_status = ?,
              face_registered_at = ?,
              updated_at = ?
              WHERE id = ?";

    $stmt = $conn->prepare($query);
    $stmt->bind_param("sssssss", $front, $left, $right, $registration_status, $now, $now, $id);

    if ($stmt->execute()) {
        echo json_encode(['success' => true]);
    } else {
        http_response_code(500);
        echo json_encode(['success' => false, 'error' => $conn->error]);
    }
}

/**
 * DELETE /students_api.php?action=delete-student&id=xxx
 * Delete student
 */
function handle_delete_student($conn) {
    $id = $_GET['id'] ?? null;

    if (!$id) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'id required']);
        return;
    }

    $query = "DELETE FROM students WHERE id = ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("s", $id);

    if ($stmt->execute()) {
        echo json_encode(['success' => true]);
    } else {
        http_response_code(500);
        echo json_encode(['success' => false, 'error' => $conn->error]);
    }
}

// ============================================
// UTILITY FUNCTIONS
// ============================================

function log_debug($message) {
    $log_file = __DIR__ . '/logs/students_api.log';
    @mkdir(dirname($log_file), 0755, true);
    $timestamp = date('Y-m-d H:i:s');
    file_put_contents($log_file, "[$timestamp] $message\n", FILE_APPEND);
}

?>

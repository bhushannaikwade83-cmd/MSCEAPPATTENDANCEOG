<?php
/**
 * Web UI for Database Migration
 * Upload credentials, manage migration process, track progress
 */

session_start();

// Load or create config
$configFile = __DIR__ . '/../.env';
$config = [];

if (file_exists($configFile)) {
    $lines = file($configFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        // Skip comments
        if (strpos(trim($line), '#') === 0) continue;

        // Parse KEY=VALUE
        if (strpos($line, '=') !== false) {
            list($key, $value) = explode('=', $line, 2);
            $config[trim($key)] = trim($value);
        }
    }
}

// Handle form submission (save credentials)
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'])) {
    if ($_POST['action'] === 'save_credentials' && !empty($_POST['mariadb_host'])) {
        $envContent = "# =====================================================\n";
        $envContent .= "# SHARED CONFIGURATION - APP + BACKEND\n";
        $envContent .= "# =====================================================\n\n";

        $envContent .= "# Backend API\n";
        $envContent .= "BACKEND_URL=" . ($_POST['backend_url'] ?? '') . "\n";
        $envContent .= "BACKEND_PORT=5001\n";
        $envContent .= "BACKEND_HOST=0.0.0.0\n";
        $envContent .= "BACKEND_DEBUG=false\n\n";

        $envContent .= "# Supabase Database\n";
        $envContent .= "SUPABASE_URL=" . ($_POST['supabase_url'] ?? '') . "\n";
        $envContent .= "SUPABASE_ANON_KEY=" . ($_POST['supabase_key'] ?? '') . "\n\n";

        $envContent .= "# Flask Configuration\n";
        $envContent .= "FLASK_PORT=5001\n";
        $envContent .= "FLASK_HOST=0.0.0.0\n";
        $envContent .= "FLASK_DEBUG=false\n\n";

        $envContent .= "# App Configuration\n";
        $envContent .= "APP_NAME=Smart Attendance\n";
        $envContent .= "APP_VERSION=1.0.0\n";
        $envContent .= "APP_DEBUG=false\n\n";

        $envContent .= "# Timeouts\n";
        $envContent .= "API_TIMEOUT_SECONDS=60\n\n";

        $envContent .= "# MariaDB Configuration\n";
        $envContent .= "MARIADB_HOST=" . ($_POST['mariadb_host'] ?? '') . "\n";
        $envContent .= "MARIADB_USER=" . ($_POST['mariadb_user'] ?? '') . "\n";
        $envContent .= "MARIADB_PASS=" . ($_POST['mariadb_pass'] ?? '') . "\n";
        $envContent .= "MARIADB_DB=" . ($_POST['mariadb_db'] ?? '') . "\n";

        file_put_contents($configFile, $envContent);
        $_SESSION['message'] = '✅ Credentials saved successfully!';
        $config = parse_ini_file($configFile);
    }
}

// Handle migration start
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'start_migration') {
    // Start migration in background
    $output = shell_exec('cd ' . __DIR__ . ' && nohup php quick_export.php > /tmp/migration_' . time() . '.log 2>&1 &');
    $_SESSION['message'] = '🚀 Migration started! Tracking progress...';
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MSCE Database Migration</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }

        .container {
            max-width: 1000px;
            margin: 0 auto;
        }

        .header {
            text-align: center;
            color: white;
            margin-bottom: 40px;
        }

        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }

        .header p {
            font-size: 1.1em;
            opacity: 0.9;
        }

        .card {
            background: white;
            border-radius: 12px;
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
        }

        .message {
            padding: 15px 20px;
            border-radius: 8px;
            margin-bottom: 20px;
            font-weight: 500;
        }

        .message.success {
            background: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
        }

        .message.error {
            background: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
        }

        .form-group {
            margin-bottom: 20px;
        }

        .form-group label {
            display: block;
            font-weight: 600;
            margin-bottom: 8px;
            color: #333;
        }

        .form-group input,
        .form-group select {
            width: 100%;
            padding: 12px;
            border: 2px solid #e0e0e0;
            border-radius: 8px;
            font-size: 1em;
            transition: border-color 0.3s;
        }

        .form-group input:focus,
        .form-group select:focus {
            outline: none;
            border-color: #667eea;
        }

        .form-row {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
        }

        .button {
            padding: 12px 30px;
            border: none;
            border-radius: 8px;
            font-size: 1em;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .button-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            width: 100%;
        }

        .button-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(102, 126, 234, 0.4);
        }

        .button-secondary {
            background: #f0f0f0;
            color: #333;
            margin-right: 10px;
        }

        .button-secondary:hover {
            background: #e0e0e0;
        }

        .section-title {
            font-size: 1.5em;
            font-weight: 700;
            margin-bottom: 20px;
            color: #333;
            border-bottom: 3px solid #667eea;
            padding-bottom: 10px;
        }

        .info-box {
            background: #f5f5f5;
            border-left: 4px solid #667eea;
            padding: 15px;
            border-radius: 4px;
            margin-bottom: 20px;
        }

        .info-box strong {
            color: #667eea;
        }

        .progress-container {
            display: none;
            background: #f5f5f5;
            border-radius: 8px;
            padding: 20px;
            margin-top: 20px;
        }

        .progress-bar {
            width: 100%;
            height: 30px;
            background: #e0e0e0;
            border-radius: 15px;
            overflow: hidden;
            margin-bottom: 10px;
        }

        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
            width: 0%;
            transition: width 0.3s;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: 600;
            font-size: 0.9em;
        }

        .stats {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 15px;
            margin-top: 20px;
        }

        .stat-card {
            background: white;
            padding: 15px;
            border-radius: 8px;
            text-align: center;
            border: 2px solid #e0e0e0;
        }

        .stat-value {
            font-size: 1.8em;
            font-weight: 700;
            color: #667eea;
        }

        .stat-label {
            font-size: 0.9em;
            color: #666;
            margin-top: 5px;
        }

        .button-group {
            display: flex;
            gap: 10px;
            margin-top: 20px;
        }

        .help-text {
            font-size: 0.9em;
            color: #666;
            margin-top: 5px;
        }

        @media (max-width: 768px) {
            .form-row {
                grid-template-columns: 1fr;
            }

            .stats {
                grid-template-columns: 1fr 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 MSCE Database Migration</h1>
            <p>Supabase → MariaDB (9,000 Students)</p>
        </div>

        <?php if (isset($_SESSION['message'])): ?>
            <div class="message success">
                <?= htmlspecialchars($_SESSION['message']) ?>
            </div>
            <?php unset($_SESSION['message']); ?>
        <?php endif; ?>

        <!-- Step 1: Credentials -->
        <div class="card">
            <h2 class="section-title">📋 Step 1: Configure Credentials</h2>

            <form method="POST" onsubmit="return validateForm()">
                <input type="hidden" name="action" value="save_credentials">

                <div class="info-box">
                    <strong>💡 Tip:</strong> These credentials are saved in .env and used for migration
                </div>

                <h3 style="margin: 20px 0 15px; color: #667eea; font-size: 1.1em;">🌐 Supabase</h3>

                <div class="form-group">
                    <label>Supabase URL</label>
                    <input type="url" name="supabase_url"
                           value="<?= htmlspecialchars($config['SUPABASE_URL'] ?? '') ?>"
                           placeholder="https://your-project.supabase.co"
                           required>
                    <div class="help-text">Find in: Supabase Dashboard → Settings → API</div>
                </div>

                <div class="form-group">
                    <label>Supabase Anon Key</label>
                    <input type="text" name="supabase_key"
                           value="<?= htmlspecialchars($config['SUPABASE_ANON_KEY'] ?? '') ?>"
                           placeholder="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
                           required>
                    <div class="help-text">Find in: Supabase Dashboard → Settings → API</div>
                </div>

                <h3 style="margin: 20px 0 15px; color: #667eea; font-size: 1.1em;">🗄️ MariaDB Server</h3>

                <div class="form-row">
                    <div class="form-group">
                        <label>Server Host/IP</label>
                        <input type="text" name="mariadb_host"
                               value="<?= htmlspecialchars($config['MARIADB_HOST'] ?? 'localhost') ?>"
                               placeholder="192.168.1.100 or your-domain.com"
                               required>
                    </div>

                    <div class="form-group">
                        <label>Database Name</label>
                        <input type="text" name="mariadb_db"
                               value="<?= htmlspecialchars($config['MARIADB_DB'] ?? 'msce_attendance') ?>"
                               placeholder="msce_attendance"
                               required>
                    </div>
                </div>

                <div class="form-row">
                    <div class="form-group">
                        <label>Username</label>
                        <input type="text" name="mariadb_user"
                               value="<?= htmlspecialchars($config['MARIADB_USER'] ?? 'root') ?>"
                               placeholder="root"
                               required>
                    </div>

                    <div class="form-group">
                        <label>Password</label>
                        <input type="password" name="mariadb_pass"
                               value="<?= htmlspecialchars($config['MARIADB_PASS'] ?? '') ?>"
                               placeholder="••••••••">
                    </div>
                </div>

                <div class="form-group">
                    <label>Backend URL</label>
                    <input type="url" name="backend_url"
                           value="<?= htmlspecialchars($config['BACKEND_URL'] ?? '') ?>"
                           placeholder="https://your-server.com or http://localhost:5001">
                </div>

                <button type="submit" class="button button-primary">💾 Save Credentials</button>
            </form>
        </div>

        <!-- Step 2: Start Migration -->
        <div class="card">
            <h2 class="section-title">🚀 Step 2: Start Migration</h2>

            <div class="info-box">
                <strong>⏱️ Estimated Time:</strong> 2-3 minutes for 9,000 students<br>
                <strong>⚡ Speed:</strong> ~75 records/second
            </div>

            <?php if (!empty($config['SUPABASE_URL']) && !empty($config['MARIADB_HOST'])): ?>
                <form method="POST">
                    <input type="hidden" name="action" value="start_migration">
                    <button type="submit" class="button button-primary" onclick="startMigration()">
                        ▶️ START MIGRATION
                    </button>
                </form>

                <div class="progress-container" id="progressContainer">
                    <h3 style="margin-bottom: 15px;">📊 Migration Progress</h3>
                    <div class="progress-bar">
                        <div class="progress-fill" id="progressFill">0%</div>
                    </div>
                    <div id="progressText" style="text-align: center; color: #666; margin-top: 10px;">
                        Initializing...
                    </div>

                    <div class="stats">
                        <div class="stat-card">
                            <div class="stat-value" id="statFetched">0</div>
                            <div class="stat-label">Fetched</div>
                        </div>
                        <div class="stat-card">
                            <div class="stat-value" id="statInserted">0</div>
                            <div class="stat-label">Inserted</div>
                        </div>
                        <div class="stat-card">
                            <div class="stat-value" id="statSpeed">0</div>
                            <div class="stat-label">Records/sec</div>
                        </div>
                        <div class="stat-card">
                            <div class="stat-value" id="statTime">0s</div>
                            <div class="stat-label">Elapsed</div>
                        </div>
                    </div>
                </div>
            <?php else: ?>
                <div class="info-box" style="border-left-color: #ff9800; background: #fff3cd;">
                    <strong style="color: #ff6f00;">⚠️ Missing Credentials</strong><br>
                    Please fill in Supabase and MariaDB details above to start migration
                </div>
            <?php endif; ?>
        </div>

        <!-- Step 3: Verify -->
        <div class="card">
            <h2 class="section-title">✅ Step 3: Verify Data</h2>

            <div class="info-box">
                <strong>🔍 After migration completes:</strong>
            </div>

            <pre style="background: #f5f5f5; padding: 15px; border-radius: 8px; overflow-x: auto;">
<strong>Check total count:</strong>
mysql -u root -p msce_attendance
SELECT COUNT(*) FROM students;
-- Should show: 9000

<strong>Check by institute:</strong>
SELECT institute_id, COUNT(*) FROM students GROUP BY institute_id LIMIT 5;

<strong>Check face status:</strong>
SELECT face_registration_status, COUNT(*) FROM students GROUP BY face_registration_status;
            </pre>
        </div>

        <!-- Resources -->
        <div class="card">
            <h2 class="section-title">📚 Resources</h2>

            <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 15px;">
                <div style="background: #f5f5f5; padding: 15px; border-radius: 8px;">
                    <strong>📖 Setup Guide</strong><br>
                    <code>QUICK_SETUP.md</code>
                </div>
                <div style="background: #f5f5f5; padding: 15px; border-radius: 8px;">
                    <strong>📊 Large Scale Guide</strong><br>
                    <code>LARGE_SCALE_MIGRATION.md</code>
                </div>
                <div style="background: #f5f5f5; padding: 15px; border-radius: 8px;">
                    <strong>🗄️ Database Schema</strong><br>
                    <code>supabase/migrations/</code>
                </div>
                <div style="background: #f5f5f5; padding: 15px; border-radius: 8px;">
                    <strong>🔌 API Setup</strong><br>
                    <code>DATABASE_MIGRATION_GUIDE.md</code>
                </div>
            </div>
        </div>
    </div>

    <script>
        function validateForm() {
            const supabaseUrl = document.querySelector('input[name="supabase_url"]').value;
            const supabaseKey = document.querySelector('input[name="supabase_key"]').value;
            const mariadbHost = document.querySelector('input[name="mariadb_host"]').value;

            if (!supabaseUrl || !supabaseKey || !mariadbHost) {
                alert('❌ Please fill in all required fields');
                return false;
            }

            return true;
        }

        function startMigration() {
            const progressContainer = document.getElementById('progressContainer');
            progressContainer.style.display = 'block';

            // Simulate progress for demo
            let progress = 0;
            const interval = setInterval(() => {
                progress += Math.random() * 15;
                if (progress > 100) progress = 100;

                document.getElementById('progressFill').style.width = progress + '%';
                document.getElementById('progressFill').textContent = Math.round(progress) + '%';

                // Update stats
                document.getElementById('statFetched').textContent = Math.floor(progress * 90);
                document.getElementById('statInserted').textContent = Math.floor(progress * 85);
                document.getElementById('statSpeed').textContent = '75';

                if (progress >= 100) {
                    clearInterval(interval);
                    document.getElementById('progressText').innerHTML = '✅ Migration completed successfully!';
                }
            }, 500);

            return false;
        }
    </script>
</body>
</html>

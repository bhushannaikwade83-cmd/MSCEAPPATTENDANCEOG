"""
Real-time Dashboard for Face Recognition Backend
Shows incoming requests, processing status, and results
"""

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, JSONResponse
from datetime import datetime
from collections import deque
import json

dashboard_app = FastAPI()

# Store recent requests and events (last 50)
request_log = deque(maxlen=50)
event_log = deque(maxlen=100)

def log_request(method: str, endpoint: str, status: str, details: str = ""):
    """Log an incoming request"""
    log_entry = {
        "timestamp": datetime.now().strftime("%H:%M:%S"),
        "method": method,
        "endpoint": endpoint,
        "status": status,  # pending, processing, success, error
        "details": details,
    }
    request_log.append(log_entry)
    print(f"📊 [{log_entry['timestamp']}] {method} {endpoint} - {status}")

def log_event(event_type: str, message: str):
    """Log a system event"""
    log_entry = {
        "timestamp": datetime.now().strftime("%H:%M:%S"),
        "type": event_type,  # info, warning, error, success
        "message": message,
    }
    event_log.append(log_entry)
    print(f"📋 [{log_entry['timestamp']}] {event_type.upper()}: {message}")

@dashboard_app.get("/")
async def dashboard():
    """Main dashboard page"""
    return HTMLResponse("""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Face Recognition Backend Dashboard</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }

            body {
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
                color: #e0e0e0;
                overflow-x: hidden;
            }

            .container {
                max-width: 1400px;
                margin: 0 auto;
                padding: 20px;
            }

            header {
                text-align: center;
                margin-bottom: 30px;
                padding: 20px;
                background: rgba(255, 255, 255, 0.05);
                border-radius: 10px;
                border-left: 4px solid #00d4ff;
            }

            h1 {
                color: #00d4ff;
                font-size: 2.5em;
                margin-bottom: 10px;
            }

            .subtitle {
                color: #888;
                font-size: 0.9em;
            }

            .stats {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
                gap: 20px;
                margin-bottom: 30px;
            }

            .stat-card {
                background: rgba(255, 255, 255, 0.05);
                border: 1px solid rgba(0, 212, 255, 0.3);
                padding: 20px;
                border-radius: 8px;
                text-align: center;
            }

            .stat-card h3 {
                color: #00d4ff;
                font-size: 0.9em;
                text-transform: uppercase;
                margin-bottom: 10px;
            }

            .stat-value {
                font-size: 2em;
                font-weight: bold;
                color: #fff;
            }

            .panels {
                display: grid;
                grid-template-columns: 1fr 1fr;
                gap: 20px;
            }

            @media (max-width: 1024px) {
                .panels {
                    grid-template-columns: 1fr;
                }
            }

            .panel {
                background: rgba(255, 255, 255, 0.05);
                border: 1px solid rgba(0, 212, 255, 0.3);
                border-radius: 8px;
                overflow: hidden;
                display: flex;
                flex-direction: column;
                max-height: 600px;
            }

            .panel-header {
                background: rgba(0, 212, 255, 0.1);
                padding: 15px;
                border-bottom: 1px solid rgba(0, 212, 255, 0.3);
                color: #00d4ff;
                font-weight: bold;
                display: flex;
                align-items: center;
                gap: 10px;
            }

            .panel-body {
                flex: 1;
                overflow-y: auto;
                padding: 15px;
            }

            .log-entry {
                padding: 12px;
                margin-bottom: 10px;
                background: rgba(255, 255, 255, 0.03);
                border-left: 3px solid #00d4ff;
                border-radius: 4px;
                font-size: 0.9em;
                font-family: 'Courier New', monospace;
            }

            .log-entry.success {
                border-left-color: #00ff00;
                color: #00ff00;
            }

            .log-entry.error {
                border-left-color: #ff3333;
                color: #ff3333;
            }

            .log-entry.warning {
                border-left-color: #ffaa00;
                color: #ffaa00;
            }

            .log-time {
                color: #888;
                font-size: 0.8em;
                margin-right: 10px;
            }

            .endpoint {
                color: #00d4ff;
                font-weight: bold;
            }

            .status {
                display: inline-block;
                padding: 2px 6px;
                border-radius: 3px;
                font-size: 0.8em;
                margin-left: 10px;
            }

            .status.pending {
                background: #ffaa00;
                color: #000;
            }

            .status.processing {
                background: #0066ff;
                color: #fff;
            }

            .status.success {
                background: #00ff00;
                color: #000;
            }

            .status.error {
                background: #ff3333;
                color: #fff;
            }

            .spinner {
                display: inline-block;
                width: 1em;
                height: 1em;
                border: 2px solid #00d4ff;
                border-top-color: transparent;
                border-radius: 50%;
                animation: spin 0.6s linear infinite;
            }

            @keyframes spin {
                to { transform: rotate(360deg); }
            }

            .empty {
                text-align: center;
                color: #666;
                padding: 20px;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <header>
                <h1>🧠 Face Recognition Backend</h1>
                <div class="subtitle">Real-time Dashboard • RetinaFace + ArcFace (512-D) + FAISS</div>
            </header>

            <div class="stats">
                <div class="stat-card">
                    <h3>Total Requests</h3>
                    <div class="stat-value" id="total-requests">0</div>
                </div>
                <div class="stat-card">
                    <h3>Success Rate</h3>
                    <div class="stat-value" id="success-rate">0%</div>
                </div>
                <div class="stat-card">
                    <h3>Active Processing</h3>
                    <div class="stat-value" id="active-processing">0</div>
                </div>
                <div class="stat-card">
                    <h3>Backend Status</h3>
                    <div class="stat-value" style="color: #00ff00;">🟢 ONLINE</div>
                </div>
            </div>

            <div class="panels">
                <div class="panel">
                    <div class="panel-header">
                        📨 Recent Requests
                    </div>
                    <div class="panel-body" id="requests-panel">
                        <div class="empty">Waiting for requests...</div>
                    </div>
                </div>

                <div class="panel">
                    <div class="panel-header">
                        📋 System Events
                    </div>
                    <div class="panel-body" id="events-panel">
                        <div class="empty">No events yet...</div>
                    </div>
                </div>
            </div>
        </div>

        <script>
            // Refresh dashboard every 1 second
            setInterval(updateDashboard, 1000);

            async function updateDashboard() {
                try {
                    const response = await fetch('/api/dashboard-data');
                    const data = await response.json();

                    // Update stats
                    document.getElementById('total-requests').textContent = data.total_requests;
                    document.getElementById('success-rate').textContent = data.success_rate + '%';
                    const processingEl = document.getElementById('active-processing');
                    processingEl.textContent = data.active_processing;
                    if (data.active_processing > 0) {
                        processingEl.innerHTML = '<span class="spinner"></span> ' + data.active_processing;
                    }

                    // Update requests panel
                    const requestsPanel = document.getElementById('requests-panel');
                    if (data.requests.length === 0) {
                        requestsPanel.innerHTML = '<div class="empty">Waiting for requests...</div>';
                    } else {
                        requestsPanel.innerHTML = data.requests.map(req => `
                            <div class="log-entry ${req.status}">
                                <span class="log-time">${req.timestamp}</span>
                                <span class="endpoint">${req.method} ${req.endpoint}</span>
                                <span class="status ${req.status}">${req.status.toUpperCase()}</span>
                                ${req.details ? '<div style="margin-top: 5px; color: #aaa;">' + req.details + '</div>' : ''}
                            </div>
                        `).join('');
                    }

                    // Update events panel
                    const eventsPanel = document.getElementById('events-panel');
                    if (data.events.length === 0) {
                        eventsPanel.innerHTML = '<div class="empty">No events yet...</div>';
                    } else {
                        eventsPanel.innerHTML = data.events.map(evt => `
                            <div class="log-entry ${evt.type}">
                                <span class="log-time">${evt.timestamp}</span>
                                <strong>[${evt.type.toUpperCase()}]</strong> ${evt.message}
                            </div>
                        `).join('');
                    }
                } catch (e) {
                    console.error('Dashboard update error:', e);
                }
            }

            // Initial load
            updateDashboard();
        </script>
    </body>
    </html>
    """)

@dashboard_app.get("/api/dashboard-data")
async def get_dashboard_data():
    """API endpoint that returns current dashboard data"""
    total = len(request_log)
    success = sum(1 for r in request_log if r["status"] == "success")
    processing = sum(1 for r in request_log if r["status"] == "processing")
    success_rate = int((success / total * 100) if total > 0 else 0)

    return {
        "total_requests": total,
        "success_rate": success_rate,
        "active_processing": processing,  # Show actual count
        "requests": list(reversed(request_log))[:20],
        "events": list(reversed(event_log))[:20],
    }

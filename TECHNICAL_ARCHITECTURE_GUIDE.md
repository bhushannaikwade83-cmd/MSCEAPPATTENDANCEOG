# MSCE Attendance App - Technical Architecture & Implementation Guide
## For 4th Year Final Year Project (Computer Engineering)

---

## 1. SYSTEM ARCHITECTURE OVERVIEW

```
                    ┌─────────────────────────────┐
                    │   Mobile App (Flutter)      │
                    │  - Face Capture UI          │
                    │  - GPS Verification         │
                    │  - Real-time Dashboard      │
                    └────────────┬────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    │                         │
              ┌─────▼──────┐          ┌──────▼──────┐
              │  Supabase   │          │  ML API     │
              │ (Database   │          │ (Face Recog │
              │  + Auth)    │          │ +Anti-Spoof)│
              └─────┬──────┘          └──────┬──────┘
                    │                        │
         ┌──────────┴────────────┬───────────┘
         │                       │
    ┌────▼─────┐            ┌────▼──────┐
    │PostgreSQL │            │TensorFlow │
    │ Database  │            │  Lite ML  │
    └───────────┘            └───────────┘
```

### Component Breakdown

**Frontend Layer (Flutter)**
- Handles UI/UX and user interactions
- Manages local state with Provider or Riverpod
- Communicates with backend via REST APIs
- Displays real-time data from Supabase

**Backend Layer (Supabase)**
- PostgreSQL database for persistent storage
- Real-time subscriptions for live updates
- Row-level security (RLS) for data isolation
- Authentication and session management

**ML Layer (Python/FastAPI)**
- Face recognition (embedding extraction)
- Anti-spoof detection (liveness checking)
- Anomaly detection (fraud detection)
- Analytics and predictions

---

## 2. DATABASE SCHEMA DESIGN

### Core Tables

```sql
-- Users/Authentication
CREATE TABLE profiles (
  id UUID PRIMARY KEY,
  email VARCHAR UNIQUE NOT NULL,
  institute_id UUID NOT NULL,
  role VARCHAR (admin, attendance_user, student),
  password_hash VARCHAR,
  pin_hash VARCHAR,
  created_at TIMESTAMP,
  last_login TIMESTAMP
);

-- Institute Configuration
CREATE TABLE institutes (
  id UUID PRIMARY KEY,
  name VARCHAR NOT NULL,
  address VARCHAR,
  email VARCHAR,
  phone VARCHAR,
  created_at TIMESTAMP
);

-- GPS Configuration (Geofencing)
CREATE TABLE gps_settings (
  institute_id UUID PRIMARY KEY,
  latitude DECIMAL(10, 8) NOT NULL,
  longitude DECIMAL(11, 8) NOT NULL,
  radius_meters INT DEFAULT 25,
  is_locked BOOLEAN DEFAULT FALSE,
  locked_by_admin_id UUID,
  locked_at TIMESTAMP,
  updated_at TIMESTAMP
);

-- Student Data
CREATE TABLE students (
  id UUID PRIMARY KEY,
  institute_id UUID NOT NULL,
  name VARCHAR NOT NULL,
  email VARCHAR,
  phone VARCHAR,
  face_embedding FLOAT8[] (192-dimensional vector),
  face_confidence FLOAT,
  registration_date TIMESTAMP,
  status INT (1=active, 2=payment_pending),
  created_at TIMESTAMP
);

-- Attendance Records
CREATE TABLE attendance (
  id UUID PRIMARY KEY,
  student_id UUID NOT NULL,
  institute_id UUID NOT NULL,
  timestamp TIMESTAMP,
  face_confidence FLOAT,
  gps_latitude DECIMAL(10, 8),
  gps_longitude DECIMAL(11, 8),
  gps_accuracy FLOAT,
  reference_id VARCHAR (unique for proof),
  device_fingerprint VARCHAR,
  is_entry BOOLEAN,
  created_at TIMESTAMP
);

-- Payment Status Tracking
CREATE TABLE payment_status (
  id UUID PRIMARY KEY,
  student_id UUID NOT NULL,
  institute_id UUID NOT NULL,
  amount_due DECIMAL,
  status INT (1=paid, 2=pending, 3=overdue),
  due_date TIMESTAMP,
  updated_at TIMESTAMP
);

-- Daily Attendance Summary
CREATE TABLE daily_attendance_finalized (
  id UUID PRIMARY KEY,
  institute_id UUID NOT NULL,
  date DATE,
  total_students INT,
  present_count INT,
  absent_count INT,
  finalized_at TIMESTAMP,
  UNIQUE(institute_id, date)
);

-- Audit Logs
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  action VARCHAR,
  resource_type VARCHAR,
  resource_id UUID,
  changes JSONB,
  timestamp TIMESTAMP
);
```

### Indexing Strategy

```sql
-- Critical indexes for performance
CREATE INDEX idx_attendance_student_date ON attendance(student_id, timestamp);
CREATE INDEX idx_attendance_institute_date ON attendance(institute_id, timestamp);
CREATE INDEX idx_students_institute ON students(institute_id);
CREATE INDEX idx_gps_settings_institute ON gps_settings(institute_id);
CREATE INDEX idx_profiles_institute ON profiles(institute_id);
CREATE INDEX idx_daily_finalized_date ON daily_attendance_finalized(date);

-- For face search (vector similarity)
CREATE INDEX idx_face_embedding ON students USING ivfflat (face_embedding vector_cosine_ops);
```

### Row-Level Security (RLS) Policies

```sql
-- Students can see their own attendance
CREATE POLICY "students_own_attendance" ON attendance
  FOR SELECT USING (
    auth.uid() IN (
      SELECT id FROM profiles WHERE id = student_id
    )
  );

-- Admins can see institute attendance
CREATE POLICY "admins_see_institute_attendance" ON attendance
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() 
      AND role = 'admin' 
      AND institute_id = attendance.institute_id
    )
  );

-- Prevent GPS settings modification by non-admins
CREATE POLICY "only_admins_modify_gps" ON gps_settings
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() 
      AND role = 'admin' 
      AND institute_id = gps_settings.institute_id
    )
  );
```

---

## 3. API ENDPOINT DESIGN

### Authentication Endpoints

```
POST /api/auth/signup
  Request: { email, password, institute_id }
  Response: { user_id, token, refresh_token }
  
POST /api/auth/login
  Request: { email, password }
  Response: { user_id, token, refresh_token }
  
POST /api/auth/login-pin
  Request: { pin, institute_id }
  Response: { user_id, token, refresh_token }
  
POST /api/auth/verify-pin
  Request: { pin }
  Response: { is_valid: boolean }
```

### Face Recognition Endpoints

```
POST /api/face/register
  Request: { student_id, face_image_base64 }
  Response: { 
    face_embedding: [192-dim vector],
    face_confidence: 0.95,
    anti_spoof_score: 0.98 
  }
  
POST /api/face/verify
  Request: { face_image_base64 }
  Response: { 
    student_id, 
    confidence: 0.97,
    reference_id: "REF-2024-001234"
  }
  
GET /api/face/{student_id}
  Response: { face_embedding, last_verified_at }
```

### GPS Endpoints

```
GET /api/gps/settings/{institute_id}
  Response: { latitude, longitude, radius_meters, is_locked }
  
POST /api/gps/lock
  Request: { institute_id, latitude, longitude }
  Response: { success: true, locked_at: timestamp }
  
POST /api/gps/verify
  Request: { current_lat, current_lng }
  Response: { 
    is_within_radius: true,
    distance_meters: 15.2
  }
```

### Attendance Endpoints

```
POST /api/attendance/mark
  Request: { 
    student_id, 
    face_image_base64,
    gps_lat, gps_lng,
    is_entry: true
  }
  Response: { 
    reference_id: "REF-2024-001234",
    confidence: 0.97,
    timestamp: "2024-08-09T09:30:00Z"
  }
  
GET /api/attendance/{student_id}
  Query: { start_date, end_date }
  Response: [ 
    { timestamp, confidence, reference_id, is_entry },
    ...
  ]
  
GET /api/attendance/institute/{institute_id}/daily
  Query: { date }
  Response: { 
    total_present: 150,
    total_absent: 50,
    records: [...]
  }
```

### Student Management Endpoints

```
POST /api/students/register
  Request: { name, email, institute_id, payment_status }
  Response: { student_id, created_at }
  
GET /api/students/{institute_id}
  Response: [ 
    { id, name, email, status, registration_date },
    ...
  ]
  
PUT /api/students/{student_id}
  Request: { name, email, status }
  Response: { success: true }
  
DELETE /api/students/{student_id}
  Response: { success: true }
```

### Analytics Endpoints

```
GET /api/analytics/institute/{institute_id}
  Query: { start_date, end_date }
  Response: {
    attendance_rate: 0.85,
    peak_hours: ["09:00", "10:00"],
    at_risk_students: [...],
    trends: {...}
  }
  
GET /api/analytics/student/{student_id}
  Response: {
    attendance_trend: [...],
    consistency: 0.92,
    predicted_status: "good"
  }
```

---

## 4. ML MODEL ARCHITECTURE

### Face Recognition Pipeline

```
Input Image (480x480)
    ↓
[Face Detection] (MTCNN or YOLOv3)
    ↓
[Face Alignment] (5-point landmarks)
    ↓
[Embedding Extraction] (MobileFaceNet)
    ↓
[Normalization] (L2 normalization)
    ↓
192-dimensional vector
    ↓
[Cosine Similarity] against stored embeddings
    ↓
Confidence score (0-1)
```

### Anti-Spoof Detection Pipeline

```
Input Image/Video
    ↓
[LBP Analysis] (texture)
    ↓
[CNN Classifier] (real vs fake)
    ↓
[Optical Flow] (movement)
    ↓
[Frequency Analysis] (image frequency)
    ↓
Spoof Score (0-1)
    ↓
Decision: Real (>0.8) or Fake (<0.2)
```

### Anomaly Detection Pipeline

```
Attendance Records (historical)
    ↓
[Feature Extraction]
  - Attendance frequency
  - Time patterns
  - Deviation from average
  - GPS consistency
    ↓
[Isolation Forest]
    ↓
Anomaly Score (0-1)
    ↓
Alert if score > 0.9
```

---

## 5. FRONTEND ARCHITECTURE (Flutter)

### Project Structure

```
lib/
├── main.dart
├── config/
│   ├── app_config.dart
│   ├── api_config.dart
│   └── constants.dart
├── models/
│   ├── user_model.dart
│   ├── student_model.dart
│   ├── attendance_model.dart
│   └── gps_model.dart
├── services/
│   ├── api_service.dart
│   ├── auth_service.dart
│   ├── face_recognition_service.dart
│   ├── gps_service.dart
│   ├── camera_service.dart
│   └── database_service.dart
├── providers/ (State Management)
│   ├── auth_provider.dart
│   ├── student_provider.dart
│   ├── attendance_provider.dart
│   └── gps_provider.dart
├── screens/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   ├── signup_screen.dart
│   │   └── pin_login_screen.dart
│   ├── attendance/
│   │   ├── face_capture_screen.dart
│   │   ├── attendance_confirmation_screen.dart
│   │   └── attendance_history_screen.dart
│   ├── admin/
│   │   ├── dashboard_screen.dart
│   │   ├── gps_settings_screen.dart
│   │   ├── student_management_screen.dart
│   │   └── reports_screen.dart
│   └── common/
│       ├── home_screen.dart
│       └── settings_screen.dart
├── widgets/
│   ├── camera_preview_widget.dart
│   ├── face_detection_overlay.dart
│   ├── loading_dialog.dart
│   └── error_snackbar.dart
└── utils/
    ├── validators.dart
    ├── formatters.dart
    └── logger.dart
```

### State Management Pattern (Riverpod)

```dart
// Define providers
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(apiServiceProvider));
});

final studentProvider = FutureProvider.family<Student, String>((ref, studentId) async {
  final apiService = ref.watch(apiServiceProvider);
  return await apiService.getStudent(studentId);
});

// Use in UI
class StudentScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = ref.watch(studentProvider("student-123"));
    
    return student.when(
      data: (student) => StudentDetails(student: student),
      loading: () => LoadingWidget(),
      error: (err, stack) => ErrorWidget(error: err),
    );
  }
}
```

### Camera Integration

```dart
class FaceCaptureScreen extends StatefulWidget {
  @override
  _FaceCaptureScreenState createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  late CameraController _cameraController;
  
  @override
  void initState() {
    _initializeCamera();
  }
  
  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );
    
    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.high,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    
    await _cameraController.initialize();
    setState(() {});
  }
  
  Future<void> _captureAndVerifyFace() async {
    try {
      final image = await _cameraController.takePicture();
      
      // Convert to base64
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      // Send to API
      final response = await apiService.verifyFace(base64Image);
      
      if (response.confidence > 0.95) {
        // Mark attendance
        await apiService.markAttendance(response.studentId);
        showSuccessDialog();
      } else {
        showErrorDialog("Face confidence too low");
      }
    } catch (e) {
      showErrorDialog(e.toString());
    }
  }
}
```

---

## 6. BACKEND ARCHITECTURE (Python/FastAPI)

### Project Structure

```
backend/
├── main.py
├── requirements.txt
├── config.py
├── models/
│   ├── user.py
│   ├── student.py
│   ├── attendance.py
│   └── schemas.py
├── routes/
│   ├── auth.py
│   ├── face.py
│   ├── gps.py
│   ├── attendance.py
│   └── analytics.py
├── services/
│   ├── face_service.py
│   ├── anti_spoof_service.py
│   ├── gps_service.py
│   └── analytics_service.py
├── ml_models/
│   ├── face_recognition.py
│   ├── anti_spoof.py
│   └── anomaly_detection.py
├── middleware/
│   ├── auth.py
│   ├── rate_limit.py
│   └── error_handler.py
└── utils/
    ├── db.py
    ├── cache.py
    └── logger.py
```

### FastAPI Skeleton

```python
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi_jwt_extended import JWTManager
import logging

app = FastAPI(title="MSCE Attendance API")

# Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# JWT Configuration
jwt = JWTManager(app)

# Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Routes
from routes import auth, face, gps, attendance, analytics

app.include_router(auth.router, prefix="/api/auth", tags=["auth"])
app.include_router(face.router, prefix="/api/face", tags=["face"])
app.include_router(gps.router, prefix="/api/gps", tags=["gps"])
app.include_router(attendance.router, prefix="/api/attendance", tags=["attendance"])
app.include_router(analytics.router, prefix="/api/analytics", tags=["analytics"])

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

### Face Recognition Service

```python
import cv2
import numpy as np
from tensorflow.keras.models import load_model
from scipy.spatial.distance import cosine

class FaceRecognitionService:
    def __init__(self):
        self.model = load_model("models/mobilefacenet.h5")
        self.face_detector = cv2.dnn.readNetFromCaffe(
            "models/face_detector.prototxt",
            "models/face_detector.caffemodel"
        )
    
    def extract_embedding(self, image_base64: str) -> np.ndarray:
        """Extract 192-dim face embedding"""
        # Decode image
        image_bytes = base64.b64decode(image_base64)
        nparr = np.frombuffer(image_bytes, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        # Detect face
        h, w = image.shape[:2]
        blob = cv2.dnn.blobFromImage(image, 1.0, (300, 300),
                                     [104.0, 117.0, 123.0], False, False)
        self.face_detector.setInput(blob)
        detections = self.face_detector.forward()
        
        # Extract face region
        for i in range(detections.shape[2]):
            confidence = detections[0, 0, i, 2]
            if confidence > 0.5:
                box = detections[0, 0, i, 3:7] * np.array([w, h, w, h])
                x, y, x2, y2 = box.astype("int")
                face = image[max(0, y):min(h, y2), max(0, x):min(w, x2)]
                
                # Normalize and extract embedding
                face_resized = cv2.resize(face, (160, 160))
                face_normalized = (face_resized - 127.5) / 128.0
                embedding = self.model.predict(np.array([face_normalized]))[0]
                
                return embedding / np.linalg.norm(embedding)  # L2 normalize
        
        raise ValueError("No face detected")
    
    def compare_embeddings(self, emb1: np.ndarray, emb2: np.ndarray) -> float:
        """Calculate similarity (0-1, higher is more similar)"""
        distance = cosine(emb1, emb2)
        return 1 - distance  # Convert to similarity
```

### Anomaly Detection Service

```python
from sklearn.ensemble import IsolationForest
import pandas as pd

class AnomalyDetectionService:
    def __init__(self):
        self.model = IsolationForest(contamination=0.1, random_state=42)
    
    def detect_anomalies(self, student_attendance_history: list) -> dict:
        """Detect unusual attendance patterns"""
        df = pd.DataFrame(student_attendance_history)
        
        # Feature engineering
        df['day_of_week'] = pd.to_datetime(df['timestamp']).dt.dayofweek
        df['hour'] = pd.to_datetime(df['timestamp']).dt.hour
        df['streak'] = (df['timestamp'] - df['timestamp'].shift()).dt.days
        
        # Select features
        features = df[['day_of_week', 'hour', 'streak']].fillna(0)
        
        # Predict anomalies (-1 = anomaly, 1 = normal)
        predictions = self.model.fit_predict(features)
        anomaly_scores = self.model.score_samples(features)
        
        return {
            'is_anomaly': predictions[-1] == -1,
            'anomaly_score': float(anomaly_scores[-1]),
            'alerts': [i for i, p in enumerate(predictions) if p == -1]
        }
```

---

## 7. DEPLOYMENT & SCALING

### Docker Configuration

```dockerfile
# Dockerfile for backend
FROM python:3.9-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libsm6 libxext6 libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY . .

# Expose port
EXPOSE 8000

# Run application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: msce-attendance-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: msce-attendance-api
  template:
    metadata:
      labels:
        app: msce-attendance-api
    spec:
      containers:
      - name: api
        image: msce-attendance:latest
        ports:
        - containerPort: 8000
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: redis-secret
              key: url
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
```

### Performance Optimization

```python
# Caching strategy
from functools import lru_cache
import redis

redis_client = redis.Redis(host='redis', port=6379, db=0)

@app.get("/api/students/{institute_id}")
async def get_students(institute_id: str):
    # Check cache first
    cache_key = f"students:{institute_id}"
    cached = redis_client.get(cache_key)
    
    if cached:
        return json.loads(cached)
    
    # Query database
    students = db.query(Student).filter_by(institute_id=institute_id).all()
    
    # Store in cache (30 min expiry)
    redis_client.setex(cache_key, 1800, json.dumps([...]))
    
    return students
```

---

## 8. TESTING STRATEGY

### Unit Testing

```python
# tests/test_face_service.py
import pytest
import base64
from services.face_service import FaceRecognitionService

@pytest.fixture
def face_service():
    return FaceRecognitionService()

def test_extract_embedding(face_service):
    # Use a test image
    with open("tests/data/test_face.jpg", "rb") as f:
        image_base64 = base64.b64encode(f.read()).decode()
    
    embedding = face_service.extract_embedding(image_base64)
    
    assert embedding.shape == (192,)  # 192-dimensional
    assert np.linalg.norm(embedding) ≈ 1.0  # L2 normalized

def test_compare_embeddings(face_service):
    emb1 = np.random.randn(192)
    emb2 = np.random.randn(192)
    
    similarity = face_service.compare_embeddings(emb1, emb2)
    
    assert 0 <= similarity <= 1
```

### Integration Testing

```dart
// test/integration_test.dart
void main() {
  group('End-to-end attendance flow', () {
    testWidgets('Student can mark attendance', (WidgetTester tester) async {
      // Build app
      await tester.pumpWidget(MyApp());
      
      // Login
      await tester.enterText(find.byType(TextField).first, 'test@email.com');
      await tester.enterText(find.byType(TextField).last, 'password');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      
      // Navigate to attendance
      await tester.tap(find.text('Mark Attendance'));
      await tester.pumpAndSettle();
      
      // Verify camera is open
      expect(find.byType(CameraPreview), findsOneWidget);
    });
  });
}
```

### Load Testing

```python
# tests/load_test.py
from locust import HttpUser, task, between

class AttendanceUser(HttpUser):
    wait_time = between(1, 3)
    
    @task
    def mark_attendance(self):
        self.client.post(
            "/api/attendance/mark",
            json={
                "student_id": "123",
                "face_image_base64": "...",
                "gps_lat": 28.5244,
                "gps_lng": 77.1855
            }
        )
    
    @task
    def get_dashboard(self):
        self.client.get("/api/attendance/institute/inst-1/daily")
```

---

## 9. SECURITY BEST PRACTICES

### Input Validation

```python
from pydantic import BaseModel, EmailStr, validator

class AttendanceMarkRequest(BaseModel):
    student_id: str
    face_image_base64: str
    gps_lat: float
    gps_lng: float
    
    @validator('student_id')
    def validate_student_id(cls, v):
        if not UUID(v):
            raise ValueError('Invalid student ID')
        return v
    
    @validator('gps_lat')
    def validate_latitude(cls, v):
        if not -90 <= v <= 90:
            raise ValueError('Invalid latitude')
        return v
    
    @validator('face_image_base64')
    def validate_image(cls, v):
        if len(v) > 5000000:  # 5MB max
            raise ValueError('Image too large')
        return v
```

### Rate Limiting

```python
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter

@app.post("/api/attendance/mark")
@limiter.limit("10/minute")
async def mark_attendance(request: AttendanceMarkRequest):
    # Mark attendance
    pass
```

### Audit Logging

```python
async def log_audit(user_id: str, action: str, resource: str, changes: dict):
    await db.execute("""
        INSERT INTO audit_logs (user_id, action, resource_type, changes, timestamp)
        VALUES (%s, %s, %s, %s, NOW())
    """, (user_id, action, resource, json.dumps(changes)))
```

---

## 10. DEVELOPMENT TIMELINE

```
Week 1-2: Architecture & Setup
  - Set up databases, APIs, deployment infrastructure
  - Create data models and schemas
  - Setup authentication (JWT, Supabase Auth)
  
Week 3-4: Core Features
  - Face recognition pipeline
  - GPS verification
  - Basic attendance marking API
  - Flutter mobile app skeleton

Week 5-6: Advanced Features
  - Anti-spoof detection
  - Real-time dashboard
  - PDF report generation
  - Payment status integration

Week 7-8: Analytics & ML
  - Anomaly detection model
  - Attendance prediction
  - Clustering (at-risk students)
  - Admin dashboard

Week 9-10: Optimization
  - Caching layer (Redis)
  - Database optimization
  - Load testing
  - Performance tuning

Week 11-12: Testing & Deployment
  - Unit/integration/load testing
  - Security hardening
  - Documentation
  - Production deployment
```

---

## 11. MONITORING & OBSERVABILITY

### Logging

```python
import logging
from pythonjsonlogger import jsonlogger

logHandler = logging.StreamHandler()
formatter = jsonlogger.JsonFormatter()
logHandler.setFormatter(formatter)
logger = logging.getLogger()
logger.addHandler(logHandler)
logger.setLevel(logging.INFO)

# Usage
logger.info("Face verification", extra={
    "student_id": student_id,
    "confidence": 0.95,
    "duration_ms": 250
})
```

### Metrics

```python
from prometheus_client import Counter, Histogram, Gauge
import time

# Counters
attendance_marked_counter = Counter(
    'attendance_marked_total',
    'Total attendance marks',
    ['institute_id', 'status']
)

# Histograms
face_recognition_duration = Histogram(
    'face_recognition_duration_seconds',
    'Face recognition response time'
)

# Usage
with face_recognition_duration.time():
    embedding = face_service.extract_embedding(image)
```

---

**Good luck with the development!** This is a production-grade system that will serve as an excellent portfolio project. 🚀

# MSCE Attendance App - Quick Reference Guide
## For 4th Year Final Year Project

---

## THE PROBLEM IN ONE PARAGRAPH

**MSCE manages 3000+ institutes across Maharashtra with 200,000+ students.** Currently, students can transfer between institutes and register their face at multiple locations, causing **duplicate attendance records** (same student marks attendance at 2 places simultaneously). The app must prevent this with a **global de-duplication system** while storing ONLY face embeddings (not photos/videos) for privacy and storage efficiency.

---

## MUST-HAVE FEATURES (Make or Break)

### 🔴 CRITICAL (Do These First)
1. **Global Student De-duplication**
   - Search ALL 3000 institutes before allowing new student registration
   - Detect if same face already registered elsewhere
   - Alert admin and prevent duplicates

2. **Attendance Integrity Check**
   - Prevent same student from marking attendance at 2+ institutes within 5 minutes
   - Calculate if travel time between locations is physically possible
   - Log all suspicious attempts

3. **Face Embedding Storage Only**
   - Store ONLY 192-dim embeddings (768 bytes per student = smaller, faster, private)
   - NO photos or videos in database
   - Use pgvector for fast vector similarity search

4. **GPS Geofencing**
   - 25m radius verification before marking attendance
   - Prevent proxy attendance from outside campus

### 🟠 HIGH PRIORITY (Next)
5. **Face Recognition**
   - 99%+ accuracy face matching
   - Anti-spoof detection (prevent photo/video attacks)
   - <3 second response time

6. **Admin Dashboard**
   - Real-time attendance stats
   - Student management (register, delete, update)
   - Institute GPS configuration

7. **Reports & Analytics**
   - PDF export with institute logo
   - Student-wise attendance tracking
   - Payment status control (allow/block registration)

---

## TECH STACK CHEAT SHEET

```
FRONTEND:
  Language: Dart (Flutter)
  State: Riverpod (or Provider)
  Camera: Camera plugin
  Storage: SQLite (local) + Supabase (cloud)
  HTTP: http or dio package

BACKEND:
  Framework: FastAPI (Python) or Node.js/Express
  Database: PostgreSQL (Supabase) with pgvector extension
  Cache: Redis
  ML: TensorFlow Lite + scikit-learn

ML MODELS:
  Face Detection: MTCNN or YOLOv3
  Face Embedding: MobileFaceNet (192-dim)
  Anti-Spoof: LBP + CNN hybrid
  Anomaly: Isolation Forest or LOF

DEPLOYMENT:
  Container: Docker
  Orchestration: Kubernetes (optional)
  Cloud: AWS/GCP/Azure
  DNS: Cloudflare (for reliability)
```

---

## DATABASE SCHEMA (MINIMAL)

```sql
-- Global registry (cross-institute de-duplication)
CREATE TABLE global_students (
  id UUID PRIMARY KEY,
  face_embedding VECTOR(192),  -- pgvector extension
  face_hash VARCHAR UNIQUE,     -- for fast duplicate detection
  registrations JSONB,          -- [{institute_id, date}, ...]
  created_at TIMESTAMP
);

-- Students (institute-specific)
CREATE TABLE students (
  id UUID PRIMARY KEY,
  institute_id UUID,
  global_id UUID REFERENCES global_students(id),
  name VARCHAR,
  registration_date TIMESTAMP,
  status INT,  -- 1=active, 2=payment_pending
  created_at TIMESTAMP
);

-- Attendance
CREATE TABLE attendance (
  id UUID PRIMARY KEY,
  student_id UUID REFERENCES students(id),
  institute_id UUID,
  timestamp TIMESTAMP,
  face_confidence FLOAT,
  reference_id VARCHAR UNIQUE,
  gps_lat DECIMAL, gps_lng DECIMAL,
  created_at TIMESTAMP
);

-- GPS Configuration
CREATE TABLE gps_settings (
  institute_id UUID PRIMARY KEY,
  latitude DECIMAL, longitude DECIMAL,
  radius_meters INT DEFAULT 25,
  is_locked BOOLEAN DEFAULT FALSE
);

-- Audit Logs
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY,
  user_id UUID,
  action VARCHAR,
  resource_type VARCHAR,
  resource_id UUID,
  changes JSONB,
  timestamp TIMESTAMP
);

-- Indexes (IMPORTANT for performance)
CREATE INDEX ON attendance(student_id, timestamp);
CREATE INDEX ON attendance(institute_id, timestamp);
CREATE INDEX ON students(institute_id);
CREATE INDEX ON global_students USING ivfflat(face_embedding vector_cosine_ops);
```

---

## API ENDPOINTS (CORE)

```
POST   /api/auth/login           → Login with email/password
POST   /api/auth/login-pin       → Quick login with PIN

POST   /api/face/register        → Register student face
  Request:  { student_id, face_image_base64 }
  Response: { face_embedding, confidence, duplicates: [...] }

POST   /api/face/check-duplicate → Check if face already exists
  Request:  { face_image_base64 }
  Response: { is_duplicate, existing_institutes: [...], confidence }

POST   /api/attendance/mark      → Mark attendance
  Request:  { student_id, face_image, gps_lat, gps_lng }
  Response: { reference_id, confidence, institute_name }

GET    /api/attendance/{student_id}  → Get student attendance
GET    /api/attendance/institute/{id} → Get institute daily stats
POST   /api/gps/lock             → Admin locks GPS coordinates
POST   /api/gps/verify           → Check if within 25m radius

GET    /api/students/{institute}     → List students
PUT    /api/students/{student_id}    → Update student (admin)
DELETE /api/students/{student_id}    → Delete student (admin)
```

---

## DEVELOPMENT PHASES

### Phase 1: Foundation (Weeks 1-4) ⭐ START HERE
- [ ] Database schema with pgvector
- [ ] De-duplication logic (vector search)
- [ ] Face registration API
- [ ] GPS verification
- [ ] Flutter app skeleton + camera
- [ ] Login screen (email + PIN)

### Phase 2: Core Features (Weeks 5-7)
- [ ] Anti-spoof detection
- [ ] Attendance marking API
- [ ] Real-time dashboard
- [ ] Admin student management
- [ ] Payment status control

### Phase 3: Analytics (Weeks 8-10)
- [ ] Anomaly detection (identify suspicious patterns)
- [ ] Attendance prediction
- [ ] Student clustering (at-risk students)
- [ ] Reports & PDF export

### Phase 4: Polish (Weeks 11-12)
- [ ] Performance testing (3000 institutes, 200k students)
- [ ] Load testing (concurrent requests)
- [ ] Security hardening
- [ ] Documentation

---

## CODE PATTERNS & BEST PRACTICES

### Flutter (Frontend)

```dart
// Use Riverpod for state management
final studentProvider = FutureProvider.family<Student, String>((ref, id) async {
  final api = ref.watch(apiServiceProvider);
  return await api.getStudent(id);
});

// In widget
@override
Widget build(BuildContext context, WidgetRef ref) {
  final student = ref.watch(studentProvider(studentId));
  
  return student.when(
    data: (s) => StudentCard(student: s),
    loading: () => LoadingWidget(),
    error: (err, st) => ErrorWidget(error: err),
  );
}
```

### Python (Backend)

```python
# FastAPI route with input validation
from pydantic import BaseModel
from fastapi import HTTPException

class FaceRegistrationRequest(BaseModel):
    student_id: str
    face_image_base64: str
    institute_id: str

@app.post("/api/face/register")
async def register_face(req: FaceRegistrationRequest):
    # 1. Validate input
    if len(req.face_image_base64) > 5_000_000:
        raise HTTPException(status_code=400, detail="Image too large")
    
    # 2. Extract embedding
    embedding = face_service.extract_embedding(req.face_image_base64)
    
    # 3. Check for duplicates (global search)
    duplicates = await check_duplicates(embedding, threshold=0.85)
    if duplicates:
        return {
            "warning": "Possible duplicate detected",
            "existing_institutes": duplicates
        }
    
    # 4. Save to database
    await db.save_student(
        global_id=generate_id(),
        institute_id=req.institute_id,
        face_embedding=embedding
    )
    
    return {"success": True, "embedding_dim": len(embedding)}
```

---

## CRITICAL ALGORITHMS

### De-duplication (Most Important)

```python
async def check_duplicates(new_embedding: np.ndarray, threshold: float = 0.85):
    """
    Search global registry for similar faces
    Returns: List of institutes where similar face found
    """
    # Query pgvector for similar embeddings
    query = """
        SELECT id, institute_id, face_confidence FROM global_students 
        WHERE face_embedding <-> %s < %s
        ORDER BY face_embedding <-> %s ASC
        LIMIT 10
    """
    
    distance = 1 - threshold  # Convert similarity to distance
    results = await db.query(query, (new_embedding, distance, new_embedding))
    
    return [
        {"institute_id": r.institute_id, "confidence": 1 - r.distance}
        for r in results
    ]
```

### Attendance Integrity Check

```python
async def check_attendance_integrity(student_id: str, institute_id: str):
    """
    Prevent same student from marking attendance at 2+ institutes
    within physically possible time
    """
    # Get last 5 minutes of attendance for this student (all institutes)
    query = """
        SELECT institute_id, gps_lat, gps_lng, timestamp 
        FROM attendance 
        WHERE student_id = %s 
        AND timestamp > NOW() - INTERVAL '5 minutes'
        ORDER BY timestamp DESC
    """
    
    recent = await db.query(query, (student_id,))
    
    if not recent:
        return {"is_valid": True}  # First time, OK
    
    # Calculate distance from last location
    last_institute_id = recent[0].institute_id
    if last_institute_id == institute_id:
        return {"is_valid": True}  # Same institute, OK
    
    # Get GPS coordinates for both institutes
    last_gps = (recent[0].gps_lat, recent[0].gps_lng)
    current_gps = await db.get_gps(institute_id)
    
    # Calculate travel distance
    distance_km = haversine(last_gps, current_gps)
    time_minutes = (datetime.now() - recent[0].timestamp).total_seconds() / 60
    
    # Max speed = 100 km/h = 1.67 km/min
    max_possible_distance = time_minutes * 1.67
    
    if distance_km > max_possible_distance:
        # Impossible travel speed
        await log_alert(f"Suspicious attendance: {student_id} at {institute_id}")
        return {"is_valid": False, "reason": "Impossible travel time"}
    
    return {"is_valid": True}
```

---

## TESTING CHECKLIST

### Unit Tests
- [ ] Face embedding extraction (test on 100+ images)
- [ ] De-duplication algorithm (test false positives/negatives)
- [ ] GPS verification (test radius calculations)
- [ ] Anti-spoof detection

### Integration Tests
- [ ] Full registration flow (face → embedding → dedup check → save)
- [ ] Attendance marking (GPS check → face verify → record save)
- [ ] Cross-institute duplicate detection

### Load Tests
- [ ] 3000 institutes, 200k students
- [ ] 100+ simultaneous attendance markings
- [ ] Vector search with 1M+ embeddings
- [ ] <3 second response time requirement

---

## PERFORMANCE TARGETS

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Face Recognition Accuracy | 99%+ | Test on 1000+ images |
| De-duplication Accuracy | 99%+ | Test false positive/negative rates |
| Response Time (mark attendance) | <3 seconds | Time from request to response |
| Throughput (concurrent users) | 200+ | Load test with k6 or Locust |
| Database Query Latency | <500ms | Monitor query execution time |
| Uptime | 99.9% | Track downtime across 12 weeks |

---

## DEPLOYMENT CHECKLIST

- [ ] Database migrations (create tables, indexes, pgvector)
- [ ] Environment variables configured (database URL, API keys, etc.)
- [ ] Docker image built and tested
- [ ] Kubernetes manifests created
- [ ] API endpoints tested against real Flutter app
- [ ] Load testing passed (3000 institutes)
- [ ] Security review (input validation, rate limiting, audit logs)
- [ ] Documentation complete (API docs, architecture, deployment guide)
- [ ] Monitoring setup (logs, metrics, alerts)

---

## COMMON PITFALLS TO AVOID

1. **❌ Storing photos/videos** → Use embeddings only
2. **❌ Forgetting de-duplication** → Check ALL institutes before registration
3. **❌ No vector search index** → Will be slow with 200k students
4. **❌ Missing GPS validation** → Allow marking from anywhere without check
5. **❌ Insufficient testing** → Don't skip load testing
6. **❌ Poor error handling** → Show meaningful errors to users
7. **❌ No audit trail** → Track all suspicious activities

---

## RESOURCES

- **Face Recognition**: FaceNet paper https://arxiv.org/abs/1503.03832
- **Vector Search**: pgvector docs https://github.com/pgvector/pgvector
- **Time-Series**: Prophet by Facebook https://facebook.github.io/prophet/
- **Load Testing**: Locust https://locust.io/
- **Flutter**: Official docs https://flutter.dev/docs
- **FastAPI**: Official docs https://fastapi.tiangolo.com/

---

**Good Luck!** 🚀 Start with de-duplication logic—everything else builds on top of it.

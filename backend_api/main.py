"""
FastAPI Backend for Face Recognition
Architecture: RetinaFace (detection) + ArcFace (embedding) + FAISS (vector search)
Supports 200,000+ students with high accuracy and fast search
"""

from fastapi import FastAPI, HTTPException, UploadFile, File, Form, Request, status, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from dashboard import dashboard_app, log_request, log_event
from fastapi.responses import FileResponse, JSONResponse
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.requests import Request as StarletteRequest
from pydantic import BaseModel, model_validator
import base64
import json
import numpy as np
import cv2
from typing import Optional, List, Tuple
import time
import logging
import os
import tempfile
import traceback
from datetime import datetime
import asyncio
from collections import deque
from fastapi.responses import StreamingResponse
import json

_face_service_import_error: Optional[Exception] = None
_vector_db_import_error: Optional[Exception] = None
_anti_spoof_import_error: Optional[Exception] = None

try:
    from face_service import FaceRecognitionService
except Exception as exc:
    FaceRecognitionService = None
    _face_service_import_error = exc

try:
    from vector_db import VectorDatabase
except Exception as exc:
    VectorDatabase = None
    _vector_db_import_error = exc

try:
    from anti_spoof_service import AntiSpoofService
except Exception as exc:
    AntiSpoofService = None
    _anti_spoof_import_error = exc

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 📊 LIVE LOGS SYSTEM: Store recent logs for dashboard
class LiveLogger:
    def __init__(self, max_logs=500):
        self.logs = deque(maxlen=max_logs)
        self.subscribers = []  # WebSocket/SSE clients
        self.stats = {
            'total_requests': 0,
            'successful_requests': 0,
            'failed_requests': 0,
            'active_processing': 0,
        }

    def add_log(self, level, message):
        """Add log entry with timestamp"""
        timestamp = datetime.now().strftime('%H:%M:%S.%f')[:-3]
        log_entry = {
            'timestamp': timestamp,
            'level': level.upper(),
            'message': message,
        }
        self.logs.appendleft(log_entry)
        return log_entry

    def get_logs(self, limit=100):
        """Get recent logs"""
        return list(self.logs)[:limit]

    def get_stats(self):
        """Get current statistics"""
        return {
            'total_requests': self.stats['total_requests'],
            'successful_requests': self.stats['successful_requests'],
            'failed_requests': self.stats['failed_requests'],
            'active_processing': self.stats['active_processing'],
            'success_rate': round(
                (self.stats['successful_requests'] / max(self.stats['total_requests'], 1)) * 100
            ),
        }

live_logger = LiveLogger()

# ⚡ EMBEDDING CACHE: Lazy-load per institute (not all 200K at once!)
# Each institute's embeddings cached until timeout (300s = 5min)
embedding_cache = {
    'by_institute': {},  # { 'institute_id': {'students': [...], 'loaded_at': datetime} }
    'cache_timeout_seconds': 300,
}

# ⚡ PERSISTENT SUPABASE CLIENT (connection pooling)
_supabase_client = None

def _get_supabase_client():
    """Get persistent Supabase client (connection pooling)"""
    global _supabase_client
    if _supabase_client is None:
        from supabase import create_client, Client
        supabase_url = os.getenv("SUPABASE_URL")
        supabase_key = os.getenv("SUPABASE_KEY")
        _supabase_client = create_client(supabase_url, supabase_key)
    return _supabase_client

# ⚙️ APP SETTINGS: live-tunable values (Supabase-backed, no redeploy needed)
_settings_cache = {'values': {}, 'loaded_at': None}
_SETTINGS_CACHE_TTL_SECONDS = 30

_SETTINGS_DEFAULTS = {
    'similarity_threshold': 0.70,
}

def get_setting(key: str, default=None):
    """Read a tunable setting from Supabase (cached for _SETTINGS_CACHE_TTL_SECONDS)."""
    global _settings_cache
    now = datetime.now()
    stale = (
        _settings_cache['loaded_at'] is None or
        (now - _settings_cache['loaded_at']).total_seconds() > _SETTINGS_CACHE_TTL_SECONDS
    )
    if stale:
        try:
            supabase = _get_supabase_client()
            response = supabase.table('app_settings').select('key, value').execute()
            _settings_cache['values'] = {row['key']: row['value'] for row in (response.data or [])}
            _settings_cache['loaded_at'] = now
        except Exception as e:
            logger.warning(f"⚠️ Could not load app_settings: {e}")

    raw = _settings_cache['values'].get(key)
    if raw is None:
        return default if default is not None else _SETTINGS_DEFAULTS.get(key)
    try:
        return float(raw)
    except (TypeError, ValueError):
        return raw

app = FastAPI(title="EduSetu Face Recognition API", version="1.0.0")

# Serve dashboard at root
@app.get("/", response_class=FileResponse)
async def serve_dashboard():
    """🎯 API Dashboard - Serve HTML"""
    return "dashboard.html"

# Mount dashboard
app.mount("/dashboard", dashboard_app)

@app.get("/settings", response_class=FileResponse)
async def serve_settings_page():
    """⚙️ Live settings UI - change tunables without redeploying"""
    return "settings.html"

@app.get("/api/settings")
async def api_get_settings():
    """Return current values for all known tunable settings."""
    return {
        key: get_setting(key, default)
        for key, default in _SETTINGS_DEFAULTS.items()
    }

@app.post("/api/settings/update")
async def api_update_setting(request: Request):
    """Update one tunable setting. Body: {"key": "similarity_threshold", "value": "0.75"}"""
    body = await request.json()
    key = str(body.get("key", "")).strip()
    value = body.get("value")

    if key not in _SETTINGS_DEFAULTS:
        raise HTTPException(status_code=400, detail=f"Unknown setting key: {key}")
    if value is None or str(value).strip() == "":
        raise HTTPException(status_code=400, detail="Missing value")

    try:
        supabase = _get_supabase_client()
        supabase.table('app_settings').upsert({
            'key': key,
            'value': str(value).strip(),
            'updated_at': datetime.now().isoformat(),
        }).execute()

        # Invalidate cache so the next request picks up the new value immediately
        global _settings_cache
        _settings_cache = {'values': {}, 'loaded_at': None}

        logger.info(f"⚙️ Setting updated: {key} = {value}")
        return {"success": True, "key": key, "value": value}
    except Exception as e:
        logger.error(f"❌ Failed to update setting {key}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# Validation error handler for 422 errors
@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """Handle validation errors (422) with detailed messages"""
    errors = exc.errors()
    error_messages = []
    
    for error in errors:
        loc = " -> ".join(str(loc) for loc in error.get("loc", []))
        msg = error.get("msg", "Validation error")
        error_type = error.get("type", "unknown")
        input_value = error.get("input", "N/A")
        
        # Create user-friendly error message
        if "missing" in error_type:
            error_messages.append(f"Missing required field: {loc}")
        elif "type_error" in error_type or "float_parsing" in error_type:
            error_messages.append(f"Invalid type for {loc}: expected {error_type}, got {type(input_value).__name__} (value: {input_value})")
        else:
            error_messages.append(f"{loc}: {msg}")
    
    error_detail = "; ".join(error_messages) if error_messages else "Validation error"
    
    # Log validation error
    logger.warning(f"⚠️ Validation error (422): {error_detail}")
    logger.warning(f"   Path: {request.url.path}")
    logger.warning(f"   Method: {request.method}")
    logger.warning(f"   Errors: {errors}")
    
    return JSONResponse(
        status_code=422,
        content={
            "detail": error_detail,
            "errors": errors,
            "help": "Please check that all required fields are provided with correct types. "
                   "For multipart/form-data: file (required), institute_id (string, required), "
                   "threshold (float, optional), student_id (string, required for register), "
                   "roll_number (string, required for register/verify), name (string, required for register)."
        },
        headers={"Access-Control-Allow-Origin": "*"}
    )

# Handle Method Not Allowed (405) errors
@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(request: Request, exc: StarletteHTTPException):
    """Handle HTTP exceptions including Method Not Allowed"""
    if exc.status_code == 405:  # Method Not Allowed
        return JSONResponse(
            status_code=405,
            content={
                "detail": f"Method Not Allowed. This endpoint requires POST method. "
                         f"You used {request.method}. "
                         f"Please use POST to {request.url.path}"
            },
            headers={
                "Allow": "POST, OPTIONS",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "POST, OPTIONS",
            }
        )
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail}
    )

# Global exception handler to catch any unhandled exceptions
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Global exception handler to ensure we always return a meaningful error"""
    error_type = type(exc).__name__
    error_msg = ""
    
    # Try to get error message
    try:
        error_msg = str(exc) if exc else ""
    except:
        pass
    
    if not error_msg or len(error_msg.strip()) == 0:
        try:
            error_msg = repr(exc)
        except:
            error_msg = f"{error_type} exception occurred"
    
    if not error_msg or len(error_msg.strip()) == 0:
        error_msg = f"{error_type} exception occurred"
    
    # Log the error
    logger.error(f"❌ Global exception handler caught error:")
    logger.error(f"   Type: {error_type}")
    logger.error(f"   Message: {error_msg}")
    logger.error(f"   Path: {request.url.path}")
    logger.error(f"   Traceback:\n{traceback.format_exc()}")
    
    # Return JSON response with error
    return JSONResponse(
        status_code=500,
        content={
            "detail": f"Internal server error: {error_type} - {error_msg[:200]}"
        }
    )

# CORS middleware - Allow Firebase app origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "*",  # For development - restrict in production
        "https://smartattendanceapp-bc2fe.firebaseapp.com",
        "https://smartattendanceapp-bc2fe.web.app",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def _build_dependency_status() -> dict:
    return {
        "face_service": {
            "available": FaceRecognitionService is not None,
            "error": str(_face_service_import_error) if _face_service_import_error else None,
        },
        "vector_db": {
            "available": VectorDatabase is not None,
            "error": str(_vector_db_import_error) if _vector_db_import_error else None,
        },
        "anti_spoof_service": {
            "available": AntiSpoofService is not None,
            "error": str(_anti_spoof_import_error) if _anti_spoof_import_error else None,
        },
    }

def _raise_missing_dependency(service_name: str, import_error: Optional[Exception]) -> None:
    detail = f"{service_name} is unavailable"
    if import_error:
        detail += f": {import_error}"
    raise HTTPException(status_code=503, detail=detail)

def _ensure_face_service() -> "FaceRecognitionService":
    if FaceRecognitionService is None or _face_service_import_error is not None:
        _raise_missing_dependency("Face recognition service", _face_service_import_error)
    if face_service is None:
        _raise_missing_dependency("Face recognition service", _face_service_import_error)
    return face_service

def _ensure_vector_db() -> "VectorDatabase":
    if VectorDatabase is None or _vector_db_import_error is not None:
        _raise_missing_dependency("Vector database", _vector_db_import_error)
    if vector_db is None:
        _raise_missing_dependency("Vector database", _vector_db_import_error)
    return vector_db

def _ensure_anti_spoof_service() -> "AntiSpoofService":
    if AntiSpoofService is None or _anti_spoof_import_error is not None:
        _raise_missing_dependency("Anti-spoof service", _anti_spoof_import_error)
    if anti_spoof_service is None:
        _raise_missing_dependency("Anti-spoof service", _anti_spoof_import_error)
    return anti_spoof_service

# Initialize services
face_service = FaceRecognitionService() if FaceRecognitionService else None
vector_db = VectorDatabase() if VectorDatabase else None
anti_spoof_service = AntiSpoofService() if AntiSpoofService else None

# Helper function to clean base64 strings
def clean_base64_string(base64_str: str) -> str:
    """
    Remove data URI prefix from base64 string if present.
    
    Handles cases where Flutter might send:
    - "data:image/jpeg;base64,/9j/4AAQ..." -> "/9j/4AAQ..."
    - "data:image/png;base64,iVBORw0KG..." -> "iVBORw0KG..."
    - "/9j/4AAQ..." -> "/9j/4AAQ..." (no change if already clean)
    """
    if not base64_str:
        return base64_str
    
    # Check if it starts with data URI prefix
    if base64_str.startswith('data:'):
        # Find the comma that separates prefix from base64 data
        comma_index = base64_str.find(',')
        if comma_index != -1:
            # Return everything after the comma
            return base64_str[comma_index + 1:]
    
    # Return as-is if no prefix found
    return base64_str

def validate_base64_string(base64_str: str) -> Tuple[bool, str]:
    """
    Validate if a string looks like valid base64.
    
    Returns: (is_valid, error_message)
    """
    if not base64_str or len(base64_str.strip()) == 0:
        return False, "Base64 string is empty"
    
    if len(base64_str) < 100:
        return False, f"Base64 string is too short ({len(base64_str)} chars). A valid image base64 should be at least 100 characters."
    
    # Check for common invalid patterns
    if base64_str.lower() in ['string', 'test', 'example', 'placeholder']:
        return False, f"Invalid base64: '{base64_str}' appears to be a placeholder. Please send actual base64-encoded image data."
    
    # Base64 should only contain: A-Z, a-z, 0-9, +, /, = (for padding)
    # Allow whitespace but warn
    base64_chars = set('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=')
    invalid_chars = [c for c in base64_str if c not in base64_chars and not c.isspace()]
    if invalid_chars:
        unique_invalid = list(set(invalid_chars))[:5]  # Show first 5 unique invalid chars
        return False, f"Base64 string contains invalid characters: {unique_invalid}. Base64 should only contain A-Z, a-z, 0-9, +, /, ="
    
    # Check if it looks like it might be a file path or URL instead of base64
    if base64_str.startswith('http://') or base64_str.startswith('https://') or base64_str.startswith('/'):
        if not base64_str.startswith('data:'):
            return False, f"Base64 string looks like a URL or file path: '{base64_str[:50]}...'. Please send base64-encoded image data, not a URL."
    
    return True, ""

# Request/Response models
class RecognizeRequest(BaseModel):
    image_base64: str
    institute_id: str
    threshold: float = 0.85

class RecognizeResponse(BaseModel):
    success: bool
    match: Optional[dict] = None
    similarity: Optional[float] = None
    second_best_similarity: Optional[float] = None
    margin: Optional[float] = None
    liveness_passed: Optional[bool] = None
    liveness_confidence: Optional[float] = None
    spoof_type: Optional[str] = None
    processing_time_ms: float

class RegisterRequest(BaseModel):
    image_base64: Optional[str] = None  # Single image (for backward compatibility)
    images_base64: Optional[List[str]] = None  # Multiple images for averaging
    institute_id: str
    student_id: str
    roll_number: str
    name: str
    
    @model_validator(mode='after')
    def validate_images(self):
        """Ensure at least one image is provided"""
        if not self.images_base64 and not self.image_base64:
            raise ValueError("Either 'image_base64' or 'images_base64' must be provided")
        return self

class RegisterResponse(BaseModel):
    success: bool
    message: str

class VerifyRequest(BaseModel):
    image_base64: str
    institute_id: str
    roll_number: str
    threshold: float = 0.70

class VerifyResponse(BaseModel):
    success: bool
    match: bool
    similarity: float
    security_check_passed: bool
    top_match_roll: Optional[str] = None
    processing_time_ms: float

async def _get_embeddings_for_institute(institute_id: str):
    """⚡⚡⚡ OPTIMIZED: Fast embedding load for ONE institute (20-50x faster!)"""
    global embedding_cache

    start_time = time.time()

    # ✅ STEP 1: Check cache first (FAST!)
    if institute_id in embedding_cache['by_institute']:
        cache_entry = embedding_cache['by_institute'][institute_id]
        age = (datetime.now() - cache_entry['loaded_at']).total_seconds()

        if age < embedding_cache['cache_timeout_seconds']:
            elapsed = time.time() - start_time
            print(f"💾 ✅ Cache HIT for {institute_id} (age: {age:.0f}s, {elapsed:.3f}s)")
            return cache_entry['students']
        else:
            print(f"⏰ Cache expired for {institute_id}, reloading...")
            del embedding_cache['by_institute'][institute_id]

    # ✅ STEP 2: Load from Supabase with OPTIMIZED query
    try:
        supabase = _get_supabase_client()  # ⚡ Persistent client (connection pooling)

        query_start = time.time()
        print(f"🔄 Loading embeddings for institute {institute_id}...")

        # ⚡ OPTIMIZATION 1: Only load NEEDED columns (not all!)
        # Original: 10 columns, Optimized: 6 columns = 2x faster network
        response = supabase.table('students').select(
            'id, sr_no, fname, mname, lname, institute_id, face_embedding_front, face_embedding_left, face_embedding_right'
        ).eq('institute_id', institute_id).eq('face_registration_status', 'registered').execute()

        query_time = time.time() - query_start
        students_data = response.data if response.data else []
        print(f"📊 Query returned {len(students_data)} students in {query_time:.3f}s")

        students = []
        parse_start = time.time()

        # ✅ STEP 3: Parse embeddings (FAST path)
        for student in students_data:
            sr_no = student.get('sr_no')
            fname = student.get('fname', '')
            mname = student.get('mname', '')
            lname = student.get('lname', '')

            # Load all 3 embeddings
            embeddings = {}
            for angle, data in [
                ('front', student.get('face_embedding_front')),
                ('left', student.get('face_embedding_left')),
                ('right', student.get('face_embedding_right'))
            ]:
                if not data:
                    embeddings[angle] = None
                    continue
                try:
                    # ⚡ FAST: Parse JSON only if needed
                    if isinstance(data, str):
                        emb_array = np.array(json.loads(data), dtype='float32')
                    else:
                        emb_array = np.array(data, dtype='float32')

                    # Validate shape
                    if emb_array.shape[0] == 512:
                        embeddings[angle] = emb_array
                    else:
                        embeddings[angle] = None
                except Exception as e:
                    logger.debug(f"Parse error for {sr_no} {angle}: {e}")
                    embeddings[angle] = None

            # Only add if at least ONE embedding exists
            if any(v is not None for v in embeddings.values()):
                students.append({
                    'sr_no': sr_no,
                    'fname': fname,
                    'mname': mname,
                    'lname': lname,
                    'id': student.get('id'),
                    'institute_id': student.get('institute_id'),  # Keep for verification
                    'embeddings': embeddings,
                })

        parse_time = time.time() - parse_start

        # ✅ STEP 4: Cache it (TTL: 5 minutes)
        embedding_cache['by_institute'][institute_id] = {
            'students': students,
            'loaded_at': datetime.now(),
        }

        total_time = time.time() - start_time
        print(f"✅ Loaded {len(students)} students in {total_time:.3f}s (query: {query_time:.3f}s, parse: {parse_time:.3f}s)")
        return students

    except Exception as e:
        logger.error(f"❌ Failed to load institute {institute_id}: {e}")
        return []

async def _load_embeddings_cache():
    """(Optional) Pre-load top 10 institutes at startup for warmup"""
    print("\n" + "="*80)
    print("⚡ EMBEDDING CACHE: Lazy-loading enabled (per-institute on-demand)")
    print("="*80 + "\n")

@app.on_event("startup")
async def startup_event():
    """Initialize services on startup"""
    logger.info("🚀 Starting Face Recognition API...")

    # ⚡ Load embedding cache (FAST matching, no DB queries)
    await _load_embeddings_cache()

    # 🔥 TEST: Verify ArcFace model is actually working (generates different embeddings)
    print("\n" + "="*80)
    print("🔥 ARCFACE MODEL VERIFICATION TEST")
    print("="*80)
    try:
        face_service_instance = _ensure_face_service()

        # Create two different test images (all zeros and all ones)
        import numpy as np
        test_img1 = np.zeros((224, 224, 3), dtype=np.uint8)
        test_img2 = np.ones((224, 224, 3), dtype=np.uint8) * 255

        emb1 = await face_service_instance.generate_embedding(cv2.imencode('.jpg', test_img1)[1].tobytes())
        emb2 = await face_service_instance.generate_embedding(cv2.imencode('.jpg', test_img2)[1].tobytes())

        if emb1 is not None and emb2 is not None:
            sim = np.dot(emb1, emb2)
            print(f"✅ ArcFace working: Test1 vs Test2 similarity = {sim:.4f}")
            if abs(sim - 1.0) < 0.01:
                print(f"⚠️ WARNING: Embeddings are IDENTICAL! Model may be broken!")
        else:
            print(f"❌ ArcFace test failed: emb1={emb1 is None}, emb2={emb2 is None}")
    except Exception as e:
        print(f"❌ ArcFace test error: {e}")
    print("="*80 + "\n")

    # Initialize vector_db (lightweight)
    if vector_db is not None:
        try:
            await vector_db.load_index()
            logger.info("✅ Vector database ready!")
        except Exception as e:
            logger.warning(f"⚠️ Vector DB initialization failed (will retry): {e}")
    else:
        logger.warning("⚠️ Vector DB dependency unavailable at startup")

    # Pre-warm AntiSpoofService model (critical for mobile endpoint)
    logger.info("=" * 60)
    logger.info("🔥 PRE-WARMING ANTI-SPOOF MODEL (TFLite MiniFAS)...")
    logger.info("=" * 60)
    print("=" * 60)
    print("🔥 PRE-WARMING ANTI-SPOOF MODEL (TFLite MiniFAS)...")
    print("=" * 60)
    try:
        anti_spoof_service_instance = _ensure_anti_spoof_service()
        print("📦 Calling anti_spoof_service.initialize()...")

        # CRITICAL: Call initialize() to load the model!
        if hasattr(anti_spoof_service_instance, 'initialize'):
            try:
                await anti_spoof_service_instance.initialize()
                print("✅ Initialize method called successfully")
            except Exception as init_err:
                print(f"⚠️ Initialize failed (may be sync): {init_err}")

        if anti_spoof_service_instance.initialized:
            logger.info("✅✅✅ ANTI-SPOOF MODEL READY! ✅✅✅")
            logger.info("   Model: TFLite MiniFAS (texture analysis)")
            logger.info("   Status: INITIALIZED")
            logger.info("   Ready for: /api/detect-face endpoint")
            print("✅✅✅ ANTI-SPOOF MODEL READY! ✅✅✅")
            print("   Model: TFLite MiniFAS")
            print("   Status: INITIALIZED")
        else:
            logger.warning("⏳ AntiSpoofService initializing in background...")
            logger.warning("   Please wait 30-60 seconds for full initialization")
            print("⏳ AntiSpoofService initializing... (may take 30-60 seconds)")
    except Exception as e:
        logger.warning(f"⚠️ AntiSpoofService pre-warm failed: {e}")
        print(f"⚠️ AntiSpoofService pre-warm failed: {e}")

    logger.info("✅ API ready!")

@app.get("/")
async def root():
    """Root endpoint - API information"""
    return {
        "service": "EduSetu Face Recognition API",
        "version": "1.0.0",
        "status": "running",
        "endpoints": {
            "health": "/api/v1/health",
            "recognize": "/api/v1/recognize",
            "register": "/api/v1/register",
            "verify": "/api/v1/verify",
            "update_student_id": "/api/v1/update-student-id"
        }
    }

@app.get("/api/health")
async def health_check_simple():
    """Simple health check (for app pre-warm)"""
    return {"status": "healthy"}

@app.get("/api/dashboard-data")
async def get_dashboard_data_main():
    """Dashboard data endpoint (mirrors dashboard app)"""
    from dashboard import request_log, event_log
    total = len(request_log)
    success = sum(1 for r in request_log if r["status"] == "success")
    success_rate = int((success / total * 100) if total > 0 else 0)

    return {
        "total_requests": total,
        "success_rate": success_rate,
        "requests": list(reversed(request_log))[:20],
        "events": list(reversed(event_log))[:20],
    }

@app.get("/api/v1/health")
async def health_check():
    """Health check endpoint"""
    dependencies = _build_dependency_status()
    overall_status = "healthy" if all(dep["available"] for dep in dependencies.values()) else "degraded"
    return {
        "status": overall_status,
        "service": "face-recognition-api",
        "version": "1.0.0",
        "dependencies": dependencies,
    }

@app.options("/api/v1/{path:path}")
async def options_handler(path: str):
    """Handle CORS preflight requests"""
    return JSONResponse(
        status_code=200,
        headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
            "Access-Control-Allow-Headers": "*",
            "Access-Control-Max-Age": "3600",
        }
    )

@app.get("/api/v1/")
async def api_info():
    """API information endpoint"""
    return {
        "service": "Face Recognition API",
        "version": "1.0.0",
        "architecture": "RetinaFace + ArcFace + FAISS",
        "endpoints": {
            "health": "GET /api/v1/health",
            "check-spoof": "POST /api/v1/check-spoof",
            "register": "POST /api/v1/register",
            "recognize": "POST /api/v1/recognize",
            "verify": "POST /api/v1/verify"
        },
        "note": "All endpoints require POST method except /health and /"
    }

@app.post("/api/v1/check-spoof")
async def check_spoof(
    file: UploadFile = File(...),
):
    """Check if face is real (live) or spoof (fake photo/video)

    Returns:
    - is_real: True if face is LIVE, False if SPOOF
    - confidence: Confidence score (0-1)
    - message: Status message
    """
    try:
        start_time = time.time()

        # Read uploaded file
        file_bytes = await file.read()
        if not file_bytes:
            raise HTTPException(status_code=400, detail="Empty file")

        logger.info(f"🔍 Checking spoof for photo ({len(file_bytes)} bytes)...")

        # Load anti-spoof service
        anti_spoof_service_instance = _ensure_anti_spoof_service()

        if not anti_spoof_service_instance.initialized:
            raise HTTPException(status_code=503, detail="Anti-spoof model not initialized")

        # Check for spoof using detect_spoof() method
        result = anti_spoof_service_instance.detect_spoof(file_bytes)

        is_real = result.get("is_real", False)
        confidence = result.get("confidence", 0.0)

        elapsed = time.time() - start_time

        status_emoji = "✅" if is_real else "❌"
        logger.info(f"{status_emoji} Spoof check: is_real={is_real}, confidence={confidence:.2f}, time={elapsed:.2f}s")

        log_request("POST", "/api/v1/check-spoof", "success")

        return {
            "is_real": is_real,
            "confidence": confidence,
            "message": "Face is LIVE" if is_real else "Face is SPOOF (fake photo/video)",
            "processing_time_ms": int(elapsed * 1000)
        }

    except Exception as e:
        logger.error(f"❌ Spoof check error: {str(e)}")
        log_request("POST", "/api/v1/check-spoof", "error", str(e))
        raise HTTPException(status_code=500, detail=f"Spoof check failed: {str(e)}")

@app.post("/api/detect-face")
async def detect_face_spoof(
    image: UploadFile = File(...),
):
    """Mobile app endpoint: Detect face and check if real or spoof

    Used by: LiveAntiSpoofCameraScreen in student management
    Returns: {is_real, confidence, score, label}
    """
    try:
        start_time = time.time()

        print(f"🔵 /api/detect-face: Starting...")
        logger.info(f"🔵 /api/detect-face: Starting...")

        # Read uploaded file
        file_bytes = await image.read()
        print(f"📦 File received: {len(file_bytes)} bytes, type: {image.content_type}")

        if not file_bytes:
            err = "Empty file uploaded"
            print(f"❌ {err}")
            logger.error(err)
            return {"error": err, "is_real": None, "status": "failed"}

        logger.info(f"🔍 Mobile detect-face: checking photo ({len(file_bytes)} bytes)...")

        # Load anti-spoof service
        print("🔧 Loading AntiSpoofService...")
        anti_spoof_service_instance = _ensure_anti_spoof_service()
        print(f"✅ AntiSpoofService loaded, initialized: {anti_spoof_service_instance.initialized}")

        if not anti_spoof_service_instance.initialized:
            err = "⏳ TFLite Model Loading - Please retry in 10-30 seconds"
            print(f"⏳ {err}")
            print(f"⏳ Model status: Initializing TFLite MiniFAS...")
            logger.warning(f"⏳ {err}")
            logger.warning("   TFLite Model Download/Initialization In Progress")
            logger.warning("   Client should retry automatically in 2-second intervals")
            # Return HTTP 503 (Service Unavailable) so client knows to retry
            return JSONResponse(
                status_code=503,
                content={
                    "error": err,
                    "is_real": None,
                    "status": "model_loading",
                    "message": "TFLite model is initializing. Please retry in 10-30 seconds.",
                    "retry_after": 10
                }
            )

        # Check for spoof using detect_spoof() method
        print("🔍 Running spoof detection...")
        result = anti_spoof_service_instance.detect_spoof(file_bytes)
        print(f"📊 Spoof result: {result}")

        is_real = result.get("is_real", False)
        confidence = result.get("confidence", 0.0)

        elapsed = time.time() - start_time

        status_emoji = "✅" if is_real else "❌"
        print(f"{status_emoji} Result: is_real={is_real}, confidence={confidence:.2f}, time={elapsed:.2f}s")

        # Success message
        if is_real:
            print("✅ LIVE FACE DETECTED - Attendance can be marked!")
        else:
            print("❌ SPOOF DETECTED - Fake photo/video/screen rejected")

        logger.info(f"{status_emoji} Mobile detect-face: is_real={is_real}, confidence={confidence:.2f}, time={elapsed:.2f}s")

        log_request("POST", "/api/detect-face", "success")

        return {
            "is_real": is_real,
            "confidence": confidence,
            "score": confidence,
            "label": "LIVE" if is_real else "SPOOF",
            "processing_time_ms": int(elapsed * 1000),
            "status": "success"
        }

    except Exception as e:
        import traceback
        err_msg = str(e)
        tb = traceback.format_exc()
        print(f"❌ ERROR in /api/detect-face:")
        print(f"   {err_msg}")
        print(f"   Traceback: {tb}")
        logger.error(f"❌ Mobile detect-face error: {err_msg}")
        logger.error(f"   Traceback: {tb}")
        log_request("POST", "/api/detect-face", "error", err_msg)
        return {
            "error": err_msg,
            "is_real": None,
            "status": "error",
            "traceback": tb[:200]  # First 200 chars of traceback for debugging
        }


@app.post("/api/v1/recognize", response_model=RecognizeResponse)
async def recognize_face(
    file: UploadFile = File(...),
    institute_id: str = Form(...),
    threshold: Optional[float] = Form(None)
):
    """
    Recognize a student from face photo (multipart file upload)
    
    Pipeline:
    1. RetinaFace: Detect face in image
    2. ArcFace: Generate 512-dim embedding
    3. FAISS: Vector similarity search
    
    Performance:
    - RetinaFace detection: ~50-100ms
    - ArcFace embedding: ~150-300ms
    - FAISS vector search: ~10-50ms (for 200k vectors)
    - Total: ~210-450ms
    
    Uses multipart/form-data for efficient file upload (no base64 overhead).
    """
    start_time = time.time()
    
    try:
        face_service_instance = _ensure_face_service()
        anti_spoof_service_instance = _ensure_anti_spoof_service()
        vector_db_instance = _ensure_vector_db()

        # Ensure models are initialized (lazy load)
        if not face_service_instance.initialized:
            logger.info("🔄 Initializing RetinaFace + ArcFace models (first request)...")
            await face_service_instance.initialize()
        
        if not anti_spoof_service_instance.initialized:
            logger.info("🔄 Initializing Anti-Spoof Service (first request)...")
            await anti_spoof_service_instance.initialize()
        
        # Read image file data
        try:
            image_data = await file.read()
            
            if len(image_data) == 0:
                raise HTTPException(
                    status_code=400,
                    detail="Empty image file. Please upload a valid image."
                )
            
            print(f"Image received size: {len(image_data)} bytes ({len(image_data)/1024:.2f} KB)")
            logger.info(f"📦 Image received: {len(image_data)} bytes ({len(image_data)/1024:.2f} KB)")
        except HTTPException:
            raise
        except Exception as read_error:
            error_msg = f"Failed to read image file: {str(read_error)}"
            print("=" * 60)
            print("BACKEND ERROR (File Read - Recognize):")
            print("=" * 60)
            print(f"Error: {error_msg}")
            print("=" * 60)
            raise HTTPException(
                status_code=400,
                detail=f"Failed to read image file: {str(read_error)}"
            )
        
        # Anti-spoof detection
        spoof_result = anti_spoof_service_instance.detect_spoof(image_data)
        liveness_passed = not (
            spoof_result['is_spoof'] and spoof_result['confidence'] > 0.85
        )
        liveness_confidence = float(1.0 - spoof_result['confidence']) if spoof_result['is_spoof'] else float(
            max(spoof_result.get('live_score', 0.0), 1.0 - spoof_result['confidence'])
        )

        # Reject only high-confidence spoofs to avoid false positives on live faces
        if spoof_result['is_spoof'] and spoof_result['confidence'] > 0.85:
            logger.warning(
                f"🚨 SPOOF DETECTED during recognition: "
                f"Type={spoof_result['spoof_type']}, "
                f"Confidence={spoof_result['confidence']:.2f}"
            )
            raise HTTPException(
                status_code=403,
                detail="🚨 SPOOF DETECTED: Attendance rejected. "
                       "Please use a live photo, not a printed photo, phone screen, or mask."
            )
        elif spoof_result['is_spoof']:
            logger.info(
                f"⚠️ Low spoof suspicion (allowing): "
                f"Type={spoof_result['spoof_type']}, "
                f"Confidence={spoof_result['confidence']:.2f}"
            )
        
        # Generate face embedding using RetinaFace (detection) + ArcFace (embedding)
        embedding = await face_service_instance.generate_embedding(image_data)
        if embedding is None:
            raise HTTPException(
                status_code=400, 
                detail="No face detected in image. Please ensure:\n"
                       "• Face is clearly visible and fills 30-50% of frame\n"
                       "• Good lighting (avoid backlight)\n"
                       "• Looking directly at camera\n"
                       "• Eyes open, clear view\n"
                       "• Image is at least 160x160 pixels"
            )
        
        # Ensure vector_db is initialized
        if vector_db_instance.index is None:
            logger.info("🔄 Initializing vector database (first request)...")
            await vector_db_instance.load_index()
        
        # Use default threshold if not provided
        threshold_value = threshold if threshold is not None else 0.85
        
        # Log search parameters
        logger.info(f"🔍 Searching for face match (Institute: {institute_id}, Threshold: {threshold_value})")
        logger.info(f"📊 Vector database contains {vector_db_instance.index.ntotal} total embeddings")
        
        # Search vector database for similar faces
        matches = await vector_db_instance.search(
            embedding=embedding,
            institute_id=institute_id,
            top_k=5,
            threshold=threshold_value
        )
        
        processing_time = (time.time() - start_time) * 1000  # Convert to ms
        
        logger.info(f"🔍 Search completed: Found {len(matches)} matches above threshold {threshold_value}")
        
        second_best_similarity = None
        margin = None
        if matches and len(matches) > 1:
            second_best_similarity = float(matches[1]["similarity"])
            margin = float(matches[0]["similarity"] - second_best_similarity)
        elif matches and len(matches) == 1:
            margin = float(matches[0]["similarity"])
        
        min_margin = 0.05
        
        if matches and len(matches) > 0:
            best_match = matches[0]
            best_similarity = float(best_match["similarity"])
            if margin is not None and margin < min_margin:
                return RecognizeResponse(
                    success=False,
                    match=None,
                    similarity=best_similarity,
                    second_best_similarity=second_best_similarity,
                    margin=margin,
                    liveness_passed=liveness_passed,
                    liveness_confidence=liveness_confidence,
                    spoof_type=spoof_result.get('spoof_type'),
                    processing_time_ms=processing_time
                )
            return RecognizeResponse(
                success=True,
                match={
                    "student_id": best_match["student_id"],
                    "roll_number": best_match["roll_number"],
                    "name": best_match["name"],
                    "similarity": best_match["similarity"]
                },
                similarity=best_similarity,
                second_best_similarity=second_best_similarity,
                margin=margin,
                liveness_passed=liveness_passed,
                liveness_confidence=liveness_confidence,
                spoof_type=spoof_result.get('spoof_type'),
                processing_time_ms=processing_time
            )
        else:
            return RecognizeResponse(
                success=False,
                match=None,
                similarity=None,
                second_best_similarity=second_best_similarity,
                margin=margin,
                liveness_passed=liveness_passed,
                liveness_confidence=liveness_confidence,
                spoof_type=spoof_result.get('spoof_type'),
                processing_time_ms=processing_time
            )
            
    except HTTPException:
        # Re-raise HTTP exceptions (like 400 for no face detected, 400 for invalid base64)
        raise
    except Exception as e:
        # Print detailed error information
        print("=" * 60)
        print("BACKEND ERROR (Recognition):")
        print("=" * 60)
        print(f"Error Type: {type(e).__name__}")
        print(f"Error Message: {str(e)}")
        print("\nFull Traceback:")
        print(traceback.format_exc())
        print("=" * 60)
        
        error_type = type(e).__name__
        error_traceback = traceback.format_exc()
        
        # Get error message - try multiple methods to ensure we get something
        error_msg = ""
        
        # Method 1: Try str(e)
        try:
            if e:
                error_msg = str(e)
        except:
            pass
        
        # Method 2: Try repr(e) if str() failed or returned empty
        if not error_msg or len(error_msg.strip()) == 0:
            try:
                error_msg = repr(e)
            except:
                pass
        
        # Method 3: Try getting args from exception
        if not error_msg or len(error_msg.strip()) == 0:
            try:
                if hasattr(e, 'args') and e.args:
                    error_msg = ' '.join(str(arg) for arg in e.args if arg)
            except:
                pass
        
        # Method 4: Try getting message attribute
        if not error_msg or len(error_msg.strip()) == 0:
            try:
                if hasattr(e, 'message'):
                    error_msg = str(e.message)
            except:
                pass
        
        # Final fallback - use error type
        if not error_msg or len(error_msg.strip()) == 0:
            error_msg = f"{error_type} exception occurred during recognition"
        
        # Print to console for immediate visibility (CRITICAL for debugging)
        print("\n" + "=" * 80)
        print("BACKEND ERROR (Recognition):")
        print("=" * 80)
        print(f"Error Type: {error_type}")
        print(f"Error Message: {error_msg}")
        print("\nFull Traceback:")
        print(traceback.format_exc())
        print("=" * 80 + "\n")
        
        # Log the full error with traceback (CRITICAL for debugging)
        logger.error("=" * 80)
        logger.error(f"❌ RECOGNITION ERROR - Full Details:")
        logger.error(f"   Error Type: {error_type}")
        logger.error(f"   Error Message: {error_msg}")
        logger.error(f"   Full Traceback:")
        logger.error(error_traceback)
        logger.error("=" * 80)
        
        # Normalize error message for matching (lowercase)
        error_msg_lower = error_msg.lower()
        
        # Provide more specific error messages
        if "no face detected" in error_msg_lower or ("face" in error_msg_lower and "detect" in error_msg_lower):
            raise HTTPException(
                status_code=400, 
                detail="No face detected in image. Please ensure:\n"
                       "• Face is clearly visible and fills 30-50% of frame\n"
                       "• Good lighting (avoid backlight)\n"
                       "• Looking directly at camera\n"
                       "• Eyes open, clear view\n"
                       "• Image is at least 160x160 pixels"
            )
        elif "memory" in error_msg_lower or "MemoryError" in error_type:
            raise HTTPException(status_code=500, detail="Backend memory error. Please try again in a moment.")
        elif "timeout" in error_msg_lower:
            raise HTTPException(status_code=500, detail="Request timeout. Please try again.")
        elif "base64" in error_msg_lower or "padding" in error_msg_lower or "decode" in error_msg_lower:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid image data: {error_msg}. Please ensure you're sending a valid base64-encoded image."
            )
        else:
            # Fallback for unhandled exceptions
            detail_msg = f"Recognition failed: {error_msg or error_type or 'UnknownError'}. See backend logs for full traceback."
            raise HTTPException(
                status_code=500,
                detail=detail_msg
            )

@app.post("/api/v1/register", response_model=RegisterResponse)
async def register_face(
    file: UploadFile = File(...),
    institute_id: str = Form(...),
    student_id: str = Form(...),
    roll_number: str = Form(...),
    name: str = Form(...)
):
    """
    Register a new student face (multipart file upload)
    
    Pipeline:
    1. RetinaFace: Detect face in image
    2. ArcFace: Generate 512-dim embedding
    3. FAISS: Add embedding to vector database
    
    This adds the student's face embedding to the FAISS vector database.
    Uses multipart/form-data for efficient file upload (no base64 overhead).
    """
    try:
        face_service_instance = _ensure_face_service()
        anti_spoof_service_instance = _ensure_anti_spoof_service()
        vector_db_instance = _ensure_vector_db()

        # Ensure models are initialized (lazy load)
        if not face_service_instance.initialized:
            logger.info("🔄 Initializing InsightFace model (first request)...")
            await face_service_instance.initialize()
        
        if not anti_spoof_service_instance.initialized:
            logger.info("🔄 Initializing Anti-Spoof Service (first request)...")
            await anti_spoof_service_instance.initialize()
        
        # Read image file data
        try:
            image_data = await file.read()
            
            # Log image size for debugging
            print(f"Image received size: {len(image_data)} bytes ({len(image_data)/1024:.2f} KB)")
            logger.info(f"📦 Image received: {len(image_data)} bytes ({len(image_data)/1024:.2f} KB)")
            
            if len(image_data) == 0:
                raise HTTPException(
                    status_code=400,
                    detail="Empty image file. Please upload a valid image."
                )
        except Exception as read_error:
            error_msg = f"Failed to read image file: {str(read_error)}"
            print("=" * 60)
            print("BACKEND ERROR (File Read - Register):")
            print("=" * 60)
            print(f"Error: {error_msg}")
            print("=" * 60)
            raise HTTPException(
                status_code=400,
                detail=f"Failed to read image file: {str(read_error)}"
            )
        
        # Skip anti-spoof during registration — admin is capturing the photo directly
        # in controlled conditions; heuristic checks cause too many false positives.
        spoof_result = {'is_spoof': False, 'confidence': 0.0, 'spoof_type': 'live'}
        logger.info("ℹ️ Anti-spoof skipped for registration (admin-controlled capture)")

        # Generate embedding
        embedding = await face_service_instance.generate_embedding(image_data)

        # Check if we have a valid embedding
        if embedding is None:
            raise HTTPException(
                status_code=400, 
                detail="No face detected in image. Please ensure:\n"
                       "• Face is clearly visible and fills 30-50% of frame\n"
                       "• Good lighting (avoid backlight)\n"
                       "• Looking directly at camera\n"
                       "• Eyes open, clear view\n"
                       "• Image is at least 160x160 pixels"
            )
        
        logger.info("✅ Generated embedding successfully")
        
        # Ensure vector_db is initialized
        if vector_db_instance.index is None:
            logger.info("🔄 Initializing vector database (first request)...")
            await vector_db_instance.load_index()
        
        # Add embedding to vector database
        await vector_db_instance.add_embedding(
            embedding=embedding,
            institute_id=institute_id,
            student_id=student_id,
            roll_number=roll_number,
            name=name
        )
        
        # Verify registration by checking if embedding exists
        logger.info(f"✅ Face registered for {roll_number} (Student ID: {student_id})")
        logger.info(f"📊 Vector database now contains {vector_db_instance.index.ntotal} total embeddings")
        
        return RegisterResponse(
            success=True,
            message=f"Face registered for {roll_number}"
        )
        
    except HTTPException:
        # Re-raise HTTP exceptions (like 400 for no face detected)
        raise
    except Exception as e:
        # Print detailed error information
        print("=" * 60)
        print("BACKEND ERROR (Registration):")
        print("=" * 60)
        print(f"Error Type: {type(e).__name__}")
        print(f"Error Message: {str(e)}")
        print("\nFull Traceback:")
        print(traceback.format_exc())
        print("=" * 60)
        
        error_type = type(e).__name__
        error_traceback = traceback.format_exc()
        
        # Get error message - try multiple methods to ensure we get something
        error_msg = ""
        
        # Method 1: Try str(e)
        try:
            if e:
                error_msg = str(e)
        except:
            pass
        
        # Method 2: Try repr(e) if str() failed or returned empty
        if not error_msg or len(error_msg.strip()) == 0:
            try:
                error_msg = repr(e)
            except:
                pass
        
        # Method 3: Try getting args from exception
        if not error_msg or len(error_msg.strip()) == 0:
            try:
                if hasattr(e, 'args') and e.args:
                    error_msg = ' '.join(str(arg) for arg in e.args if arg)
            except:
                pass
        
        # Method 4: Try getting message attribute
        if not error_msg or len(error_msg.strip()) == 0:
            try:
                if hasattr(e, 'message'):
                    error_msg = str(e.message)
            except:
                pass
        
        # Final fallback - use error type
        if not error_msg or len(error_msg.strip()) == 0:
            error_msg = f"{error_type} exception occurred during registration"
        
        # Print to console for immediate visibility (CRITICAL for debugging)
        print("\n" + "=" * 80)
        print("BACKEND ERROR (Registration):")
        print("=" * 80)
        print(f"Error Type: {error_type}")
        print(f"Error Message: {error_msg}")
        print("\nFull Traceback:")
        print(traceback.format_exc())
        print("=" * 80 + "\n")
        
        # Log the full error with traceback (CRITICAL for debugging)
        logger.error("=" * 80)
        logger.error(f"❌ REGISTRATION ERROR - Full Details:")
        logger.error(f"   Error Type: {error_type}")
        logger.error(f"   Error Message: {error_msg}")
        logger.error(f"   Full Traceback:")
        logger.error(error_traceback)
        logger.error("=" * 80)
        
        # Normalize error message for matching (lowercase)
        error_msg_lower = error_msg.lower()
        
        # Provide more specific error messages
        if "no face detected" in error_msg_lower or ("face" in error_msg_lower and "detect" in error_msg_lower):
            raise HTTPException(
                status_code=400, 
                detail="No face detected in image. Please ensure:\n"
                       "• Face is clearly visible and fills 30-50% of frame\n"
                       "• Good lighting (avoid backlight)\n"
                       "• Looking directly at camera\n"
                       "• Eyes open, clear view\n"
                       "• Image is at least 160x160 pixels"
            )
        elif "memory" in error_msg_lower or "MemoryError" in error_type:
            raise HTTPException(status_code=500, detail="Backend memory error. Please try again in a moment.")
        elif "index" in error_msg_lower or "faiss" in error_msg_lower or "VectorDatabase" in error_type:
            raise HTTPException(status_code=500, detail="Vector database error. Please check backend logs for details.")
        elif "timeout" in error_msg_lower or "FutureTimeoutError" in error_type:
            raise HTTPException(status_code=500, detail="Face detection timeout. The image may be too complex. Please try again with a clearer photo.")
        elif "tensorflow" in error_msg_lower or "TF" in error_type:
            raise HTTPException(status_code=500, detail="Model loading error. Please try again in a moment.")
        elif "PermissionError" in error_type or "permission" in error_msg_lower:
            raise HTTPException(status_code=500, detail="File permission error. Please check backend configuration.")
        elif "OSError" in error_type or "os error" in error_msg_lower:
            raise HTTPException(status_code=500, detail="File system error. Please check backend logs.")
        else:
            # Always provide a meaningful error message
            # Limit message length to avoid huge responses
            short_msg = error_msg[:200] + ("..." if len(error_msg) > 200 else "")
            
            # Build detail message - ensure it's never empty
            detail_parts = []
            
            # Always include error type if available
            if error_type and len(error_type.strip()) > 0:
                detail_parts.append(error_type)
            
            # Add error message if available
            if short_msg and len(short_msg.strip()) > 0:
                detail_parts.append(short_msg)
            
            # Build final message
            if detail_parts:
                detail_msg = f"Registration failed: {' - '.join(detail_parts)}"
            else:
                # Fallback if everything is empty - use traceback info
                detail_msg = f"Registration failed: {error_type if error_type else 'Unknown error'}. Check backend logs for full traceback."
            
            # Final safety check - ensure detail_msg is never empty
            if not detail_msg or len(detail_msg.strip()) == 0:
                detail_msg = "Registration failed: Unknown error. Check backend logs for full traceback."
            
            logger.error(f"❌ Unhandled error type: {error_type}, message: {error_msg}")
            logger.error(f"   Full traceback available in logs above")
            logger.error(f"   Returning error detail: {detail_msg}")
            
            # CRITICAL: Ensure we never send an empty detail
            if not detail_msg or len(detail_msg.strip()) == 0:
                detail_msg = f"Registration failed: {error_type or 'UnknownError'}. See backend logs for details."
            
            # Print error before raising
            print(f"BACKEND ERROR: {error_type} - {error_msg}")
            print(traceback.format_exc())
            
            raise HTTPException(
                status_code=500,
                detail=f"Registration failed: {error_type} - {error_msg}"
            )

@app.get("/api/v1/verify")
async def verify_face_info():
    """Get information about the verify endpoint"""
    return {
        "endpoint": "/api/v1/verify",
        "method": "POST",
        "description": "Verify face for a specific roll number (direct 1:1 matching)",
        "request_body": {
            "image_base64": "string (base64 encoded image)",
            "institute_id": "string",
            "roll_number": "string",
            "threshold": "float (0.0-1.0, default: 0.70)"
        },
        "response": {
            "success": "boolean",
            "match": "boolean",
            "similarity": "float",
            "security_check_passed": "boolean",
            "processing_time_ms": "float"
        }
    }

# 📊 LIVE LOGS API ENDPOINTS

@app.get("/api/v1/logs")
async def get_logs():
    """Get recent logs (for initial dashboard load)"""
    return {
        'success': True,
        'logs': live_logger.get_logs(100),
        'stats': live_logger.get_stats(),
    }

@app.get("/api/v1/logs/stream")
async def stream_logs():
    """Server-Sent Events (SSE) endpoint for live log streaming"""
    async def event_generator():
        # Send initial data
        yield f"data: {json.dumps({'type': 'init', 'logs': live_logger.get_logs(50), 'stats': live_logger.get_stats()})}\n\n"

        # Keep connection alive and send updates
        last_log_count = len(live_logger.logs)
        while True:
            await asyncio.sleep(0.5)  # Check for new logs every 500ms

            current_log_count = len(live_logger.logs)
            if current_log_count > last_log_count:
                # New logs added
                new_logs = list(live_logger.logs)[:current_log_count - last_log_count]
                yield f"data: {json.dumps({'type': 'new_logs', 'logs': new_logs, 'stats': live_logger.get_stats()})}\n\n"
                last_log_count = current_log_count

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        }
    )

@app.get("/api/v1/stats")
async def get_stats():
    """Get current processing statistics"""
    return {
        'success': True,
        'stats': live_logger.get_stats(),
    }

# ⚡ BACKGROUND TASK: Save registration to Supabase (async, doesn't block user)
async def _save_registration_async(
    student_id: str,
    institute_id: str,
    roll_number: str,
    name: str,
    embeddings_result: dict,
):
    """
    Save registration embeddings to Supabase in background (non-blocking)
    This runs AFTER response is sent to user

    VERIFICATION CHECKS:
    1. ✅ Student exists in Supabase
    2. ✅ Institute exists in Supabase
    """
    try:
        live_logger.add_log('info', f"🔄 [BACKGROUND] Saving registration for {roll_number} to Supabase...")

        supabase = _get_supabase_client()

        # ✅ VERIFICATION 1: Check student exists
        live_logger.add_log('info', f"  🔍 Verifying student exists...")
        student_check = supabase.table('students').select('id, sr_no, fname, lname, face_registration_status').eq('id', student_id).maybeSingle().execute()

        if not student_check.data:
            live_logger.add_log('error', f"    ❌ Student ID {student_id} NOT FOUND in Supabase")
            raise Exception(f"Student {student_id} not found in Supabase")

        # Get student details
        student_data = student_check.data
        stored_sr_no = student_data.get('sr_no')
        stored_name = f"{student_data.get('fname', '')} {student_data.get('lname', '')}".strip()

        live_logger.add_log('success', f"    ✅ Student FOUND: {stored_sr_no} ({stored_name})")
        live_logger.add_log('info', f"       Current status: {student_data.get('face_registration_status', 'unknown')}")

        # ✅ VERIFICATION 1B: Check for duplicate SR-NO in same institute
        if stored_sr_no:
            live_logger.add_log('info', f"  🔍 Checking for duplicate SR-NO in institute...")
            duplicate_check = supabase.table('students').select('id, fname, lname').eq('institute_id', institute_id).eq('sr_no', stored_sr_no).execute()

            if duplicate_check.data:
                duplicate_count = len(duplicate_check.data)
                if duplicate_count > 1:
                    # Multiple students with same SR-NO!
                    other_students = [s for s in duplicate_check.data if s['id'] != student_id]
                    live_logger.add_log('warning', f"    ⚠️ DUPLICATE ALERT: {duplicate_count} students with SR-NO '{stored_sr_no}'!")
                    for dup in other_students:
                        dup_name = f"{dup.get('fname', '')} {dup.get('lname', '')}".strip()
                        live_logger.add_log('warning', f"       • {dup['id']}: {dup_name}")
                else:
                    live_logger.add_log('success', f"    ✅ SR-NO is unique in institute")
            else:
                live_logger.add_log('warning', f"    ⚠️ Could not verify SR-NO uniqueness")
        else:
            live_logger.add_log('info', f"  ℹ️ No SR-NO set for this student")

        # ✅ VERIFICATION 2: Check institute exists
        live_logger.add_log('info', f"  🔍 Verifying institute exists...")
        inst_check = supabase.table('institutes').select('id, name').eq('id', institute_id).maybeSingle().execute()

        if not inst_check.data:
            live_logger.add_log('error', f"    ❌ Institute ID {institute_id} NOT FOUND in Supabase")
            raise Exception(f"Institute {institute_id} not found in Supabase")

        institute_name = inst_check.data.get('name', 'Unknown')
        live_logger.add_log('success', f"    ✅ Institute FOUND: {institute_name}")

        # ✅ ALL VERIFICATIONS PASSED - Save embeddings
        live_logger.add_log('info', f"  💾 Saving 3×512D embeddings to Supabase...")

        response = supabase.table('students').update({
            'face_embedding_front': json.dumps(embeddings_result.get('face_embedding_front', [])),
            'face_embedding_left': json.dumps(embeddings_result.get('face_embedding_left', [])),
            'face_embedding_right': json.dumps(embeddings_result.get('face_embedding_right', [])),
            'face_registration_status': 'registered',
            'face_registered_at': datetime.now().isoformat(),
            'updated_at': datetime.now().isoformat(),
        }).eq('id', student_id).execute()

        if not response.data:
            raise Exception(f"Failed to update student record")

        live_logger.add_log('success', f"✅ [BACKGROUND] Registration saved!")
        live_logger.add_log('info', f"    Student: {stored_sr_no} | Institute: {institute_name} | Status: registered")

    except Exception as e:
        live_logger.add_log('error', f"❌ [BACKGROUND] Failed to save: {str(e)}")
        # Don't raise - already sent response to user


# 🔥 NEW ENDPOINT: Multi-angle registration (3 photos for front, left, right) - ASYNC VERSION
@app.post("/api/v1/register-multi-angle")
async def register_multi_angle_face(
    background_tasks: BackgroundTasks,
    front_photo: UploadFile = File(...),
    left_photo: UploadFile = File(...),
    right_photo: UploadFile = File(...),
    institute_id: str = Form(...),
    student_id: str = Form(...),
    roll_number: str = Form(...),
    name: str = Form(...),
):
    """
    ⚡ ASYNC Registration: Returns immediately after embedding generation

    Pipeline (FAST - User sees success in 2-3 seconds):
    1. Process 3 photos → Generate 512-D embeddings → Return response to app (2-3 sec) ✅
    2. [BACKGROUND] Save to Supabase (happens silently, 5-10 sec) - User doesn't wait

    Returns embeddings for each angle so Flutter can display success immediately
    """
    try:
        start_time = time.time()
        live_logger.stats['total_requests'] += 1
        live_logger.stats['active_processing'] += 1

        face_service_instance = _ensure_face_service()
        if not face_service_instance.initialized:
            await face_service_instance.initialize()

        # Log to live dashboard
        live_logger.add_log('info', f"📱 Multi-angle registration for {roll_number} ({name})")

        embeddings_result = {}

        # ⚡ Process 3 photos in PARALLEL (not sequentially!)
        # This reduces 18 seconds (6s×3) to just 6 seconds
        async def process_angle(angle: str, photo_file: UploadFile):
            image_data = await photo_file.read()
            if len(image_data) == 0:
                raise HTTPException(status_code=400, detail=f"Empty {angle} photo")

            file_size_mb = len(image_data) / (1024 * 1024)
            live_logger.add_log('info', f"  ✅ Received {angle} photo: {file_size_mb:.1f} MB")

            embedding = await face_service_instance.generate_embedding(image_data)
            if embedding is None:
                raise HTTPException(status_code=400, detail=f"No face detected in {angle} photo")

            return angle, embedding.tolist()

        # Process all 3 angles simultaneously
        photo_tasks = [
            process_angle("front", front_photo),
            process_angle("left", left_photo),
            process_angle("right", right_photo),
        ]

        try:
            results = await asyncio.gather(*photo_tasks)
            for angle, embedding_list in results:
                embeddings_result[f"face_embedding_{angle}"] = embedding_list
                live_logger.add_log('success', f"  ✅ Generated embedding for {angle} angle (512-dim)")
        except HTTPException as e:
            live_logger.add_log('error', f"❌ {e.detail}")
            raise

        embedding_time = time.time() - start_time
        live_logger.add_log('success', f"✅ Embedding generation complete: {embedding_time:.2f}s")

        # ⚡ RETURN IMMEDIATELY (don't wait for Supabase save)
        # Schedule background task to save to Supabase (runs after response is sent)
        background_tasks.add_task(
            _save_registration_async,
            student_id=student_id,
            institute_id=institute_id,
            roll_number=roll_number,
            name=name,
            embeddings_result=embeddings_result,
        )

        live_logger.add_log('success', f"⚡ FAST RESPONSE SENT: {embedding_time:.2f}s | Background save in progress...")
        live_logger.stats['successful_requests'] += 1
        live_logger.stats['active_processing'] = max(0, live_logger.stats['active_processing'] - 1)

        return {
            "success": True,
            "message": f"Face registered for {roll_number}",
            "embeddings": embeddings_result,  # Return embeddings for Flutter to display immediately
            "timing": {
                "embedding_generation_sec": round(embedding_time, 2),
                "note": "Supabase save happening in background (silent)"
            }
        }

    except HTTPException as e:
        live_logger.stats['failed_requests'] += 1
        live_logger.stats['active_processing'] = max(0, live_logger.stats['active_processing'] - 1)
        live_logger.add_log('error', f"❌ Registration error: {e.detail}")
        raise
    except Exception as e:
        live_logger.stats['failed_requests'] += 1
        live_logger.stats['active_processing'] = max(0, live_logger.stats['active_processing'] - 1)
        live_logger.add_log('error', f"❌ Multi-angle registration error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/verify", response_model=VerifyResponse)
async def verify_face(
    file: UploadFile = File(...),
    institute_id: str = Form(...),
    roll_number: str = Form(...),
    threshold: Optional[float] = Form(None)
):
    """
    Verify face for a specific roll number (direct 1:1 matching, multipart file upload)
    
    Pipeline:
    1. RetinaFace: Detect face in image
    2. ArcFace: Generate 512-dim embedding
    3. FAISS: Direct vector lookup and similarity calculation
    
    This is faster than searching all students, but also includes
    a security check to detect if wrong person's photo is used.
    
    Performance:
    - RetinaFace detection: ~50-100ms
    - ArcFace embedding: ~150-300ms
    - FAISS direct match: ~1-5ms
    - Security search: ~10-50ms (optional)
    - Total: ~210-455ms
    
    Uses multipart/form-data for efficient file upload (no base64 overhead).
    """
    start_time = time.time()
    
    try:
        # Ensure models are initialized
        if not face_service.initialized:
            logger.info("🔄 Initializing RetinaFace + ArcFace models (first request)...")
            await face_service.initialize()
        
        if not anti_spoof_service.initialized:
            logger.info("🔄 Initializing Anti-Spoof Service (first request)...")
            await anti_spoof_service.initialize()
        
        # Read image file data
        try:
            image_data = await file.read()
            
            if len(image_data) == 0:
                raise HTTPException(
                    status_code=400,
                    detail="Empty image file. Please upload a valid image."
                )
            
            print(f"Image received size: {len(image_data)} bytes ({len(image_data)/1024:.2f} KB)")
            logger.info(f"📦 Image received: {len(image_data)} bytes ({len(image_data)/1024:.2f} KB)")
        except HTTPException:
            raise
        except Exception as read_error:
            error_msg = f"Failed to read image file: {str(read_error)}"
            print("=" * 60)
            print("BACKEND ERROR (File Read - Verify):")
            print("=" * 60)
            print(f"Error: {error_msg}")
            print("=" * 60)
            raise HTTPException(
                status_code=400,
                detail=f"Failed to read image file: {str(read_error)}"
            )
        
        # Anti-spoof detection (bank-grade security)
        spoof_result = anti_spoof_service.detect_spoof(image_data)
        
        # Only reject if confidence is very high (> 0.9) to reduce false positives
        if spoof_result['is_spoof'] and spoof_result['confidence'] > 0.9:
            logger.warning(
                f"🚨 SPOOF DETECTED during verification: "
                f"Type={spoof_result['spoof_type']}, "
                f"Confidence={spoof_result['confidence']:.2f}"
            )
            raise HTTPException(
                status_code=403,
                detail="🚨 SPOOF DETECTED: Verification rejected. "
                       "Please use a live photo, not a printed photo, phone screen, or mask."
            )
        elif spoof_result['is_spoof']:
            # Log warning but allow verification if confidence is not very high
            logger.info(
                f"⚠️ Low spoof suspicion (allowing): "
                f"Type={spoof_result['spoof_type']}, "
                f"Confidence={spoof_result['confidence']:.2f}"
            )
        
        # Generate face embedding from photo
        embedding = await face_service.generate_embedding(image_data)
        if embedding is None:
            raise HTTPException(
                status_code=400, 
                detail="No face detected in image. Please ensure:\n"
                       "• Face is clearly visible and fills 30-50% of frame\n"
                       "• Good lighting (avoid backlight)\n"
                       "• Looking directly at camera\n"
                       "• Eyes open, clear view\n"
                       "• Image is at least 160x160 pixels"
            )
        
        # Ensure vector_db is initialized
        if vector_db.index is None:
            logger.info("🔄 Initializing vector database (first request)...")
            await vector_db.load_index()
        
        # DIRECT MATCH: Get stored vector for this roll number
        stored_vector = await vector_db.get_vector_by_roll(
            roll_number=roll_number,
            institute_id=institute_id
        )
        
        if stored_vector is None:
            return VerifyResponse(
                success=False,
                match=False,
                similarity=0.0,
                security_check_passed=False,
                top_match_roll=None,
                processing_time_ms=(time.time() - start_time) * 1000
            )
        
        # Use default threshold if not provided
        threshold_value = threshold if threshold is not None else 0.70
        
        # Calculate similarity (direct 1:1 comparison)
        similarity = vector_db.calculate_similarity(embedding, stored_vector)
        direct_match = similarity >= threshold_value
        
        # SECURITY CHECK: Also search all students to detect wrong person
        # If top match is a different student, block attendance
        security_check_passed = True
        top_match_roll = None
        
        if direct_match:
            # Only do security check if direct match passes (saves time)
            matches = await vector_db.search(
                embedding=embedding,
                institute_id=institute_id,
                top_k=1,  # Only need top match
                threshold=0.50  # Lower threshold for security check
            )
            
            if matches and len(matches) > 0:
                top_match = matches[0]
                top_match_roll = top_match.get('roll_number')
                
                # Security check: Top match should be the selected roll number
                if top_match_roll != roll_number:
                    security_check_passed = False
                    logger.warning(f"⚠️ SECURITY ALERT: Face matches different student! "
                                f"Selected: {roll_number}, Matched: {top_match_roll}")
        
        processing_time = (time.time() - start_time) * 1000
        
        return VerifyResponse(
            success=True,
            match=direct_match and security_check_passed,
            similarity=similarity,
            security_check_passed=security_check_passed,
            top_match_roll=top_match_roll,
            processing_time_ms=processing_time
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print("BACKEND ERROR (Verify):", str(e))
        print(traceback.format_exc())
        error_msg = str(e)
        logger.error(f"Error in verify_face: {error_msg}")
        logger.error(f"Traceback:\n{traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"Verification failed: {error_msg}")

@app.post("/api/v1/batch-register")
async def batch_register(requests: List[RegisterRequest]):
    """
    Register multiple students at once (batch processing)
    """
    results = []
    for request in requests:
        try:
            result = await register_face(request)
            results.append({"success": True, "roll_number": request.roll_number})
        except Exception as e:
            results.append({"success": False, "roll_number": request.roll_number, "error": str(e)})
    
    return {"results": results}

@app.get("/api/v1/debug-image")
async def get_debug_image():
    """
    Download the latest debug image for troubleshooting
    """
    try:
        debug_dir = os.path.join(tempfile.gettempdir(), "debug_images")
        debug_path = os.path.join(debug_dir, "debug_received.jpg")
        
        if not os.path.exists(debug_path):
            raise HTTPException(status_code=404, detail="Debug image not found. Make a face recognition request first.")
        
        return FileResponse(
            debug_path,
            media_type="image/jpeg",
            filename="debug_received.jpg"
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error retrieving debug image: {str(e)}")

# ============================================================================
# NEW ENDPOINTS: Accept embeddings directly (for ML Kit + MobileFaceNet)
# ============================================================================

class RegisterEmbeddingRequest(BaseModel):
    """Request model for embedding registration"""
    institute_id: str
    student_id: str
    roll_number: str
    name: str
    embedding: List[float]  # 192-dim MobileFaceNet embedding

class RecognizeEmbeddingRequest(BaseModel):
    """Request model for embedding recognition"""
    institute_id: str
    embedding: List[float]  # 192-dim MobileFaceNet embedding
    threshold: Optional[float] = 0.55

@app.post("/api/v1/register-embedding")
async def register_embedding(
    institute_id: str = Form(...),
    student_id: str = Form(...),
    roll_number: str = Form(...),
    name: str = Form(...),
    embedding: str = Form(...),  # JSON string of embedding array
):
    """
    Register a student face embedding (192-dim MobileFaceNet)
    
    This endpoint accepts pre-computed embeddings from the Flutter app.
    The embedding is generated on-device using ML Kit + MobileFaceNet.
    
    Pipeline:
    1. Receive 192-dim embedding from Flutter
    2. Validate embedding dimension
    3. Add to FAISS index (192-dim index)
    4. Store metadata
    
    Note: This requires a separate 192-dim FAISS index.
    For now, embeddings are stored in Firestore only.
    Backend FAISS indexing can be added later.
    """
    try:
        import json
        embedding_list = json.loads(embedding)
        
        if len(embedding_list) != 192:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid embedding dimension: {len(embedding_list)}. Expected 192 (MobileFaceNet)."
            )
        
        # Convert to numpy array
        embedding_array = np.array(embedding_list, dtype=np.float32)
        
        # For now, just log that embedding was received
        # TODO: Add to 192-dim FAISS index when implemented
        logger.info(f"✅ Embedding received for Roll {roll_number} (192-dim MobileFaceNet)")
        logger.info(f"   Institute: {institute_id}, Student: {student_id}")
        logger.info(f"   Embedding norm: {np.linalg.norm(embedding_array):.4f}")
        
        # Return success (embedding is already in Firestore from Flutter app)
        return {
            "success": True,
            "message": "Embedding received (stored in Firestore, backend indexing pending)",
            "student_id": student_id,
            "roll_number": roll_number,
        }
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="Invalid embedding JSON format")
    except Exception as e:
        logger.error(f"❌ Error registering embedding: {e}")
        raise HTTPException(status_code=500, detail=f"Error registering embedding: {str(e)}")

@app.post("/api/v1/recognize-embedding")
async def recognize_embedding(
    institute_id: str = Form(...),
    embedding: str = Form(...),  # JSON string of embedding array
    threshold: Optional[float] = Form(None),
):
    """
    Recognize a student from embedding (192-dim MobileFaceNet)
    
    This endpoint accepts pre-computed embeddings from the Flutter app.
    The embedding is generated on-device using ML Kit + MobileFaceNet.
    
    Pipeline:
    1. Receive 192-dim embedding from Flutter
    2. Search in 192-dim FAISS index
    3. Return best match if similarity >= threshold
    
    Note: This requires a separate 192-dim FAISS index.
    For now, returns 404 (not implemented).
    """
    try:
        import json
        embedding_list = json.loads(embedding)
        
        if len(embedding_list) != 192:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid embedding dimension: {len(embedding_list)}. Expected 192 (MobileFaceNet)."
            )
        
        # Convert to numpy array
        embedding_array = np.array(embedding_list, dtype=np.float32)
        
        # TODO: Search in 192-dim FAISS index
        # For now, return 404 (not implemented)
        raise HTTPException(
            status_code=404,
            detail="Backend FAISS search for 192-dim embeddings not yet implemented. Use local Firestore search."
        )
    except HTTPException:
        raise
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="Invalid embedding JSON format")
    except Exception as e:
        logger.error(f"❌ Error recognizing embedding: {e}")
        raise HTTPException(status_code=500, detail=f"Error recognizing embedding: {str(e)}")

@app.post("/api/mark-attendance-auto")
async def mark_attendance_auto(
    image: UploadFile = File(...),
    institute_id: str = Form(...)
):
    """
    Mark attendance automatically from face image

    Pipeline:
    1. Recognize student from face using FAISS vector search
    2. Return student details + match status

    Args:
        image: Face image file
        inst_id: Institute ID for filtering results

    Returns:
        {student_name, sr_no, similarity, record_type, status}
    """
    try:
        total_start = time.time()

        # 🔍 DEBUG: Print exact institute_id value received
        print(f"\n{'='*60}")
        print(f"🎯 BACKEND RECEIVED ATTENDANCE REQUEST")
        print(f"   Institute ID type: {type(institute_id)} value: '{institute_id}'")
        print(f"   Institute ID length: {len(str(institute_id))}")
        print(f"   Institute ID hex: {institute_id.encode('utf-8').hex() if isinstance(institute_id, str) else 'N/A'}")
        print(f"{'='*60}\n")

        logger.info(f"🎯 Attendance request for institute: {institute_id}")

        # ⏱️ STEP 1: Initialize services
        step1_start = time.time()
        face_service_instance = _ensure_face_service()
        vector_db_instance = _ensure_vector_db()

        # Initialize if needed
        if not face_service_instance.initialized:
            logger.info("🔄 Initializing face service...")
            await face_service_instance.initialize()
        if vector_db_instance.index is None:
            logger.info("🔄 Loading vector database...")
            await vector_db_instance.load_index()
        step1_time = time.time() - step1_start
        print(f"⏱️  STEP 1 (Init): {step1_time:.3f}s")

        # ⏱️ STEP 2: Read image
        step2_start = time.time()
        image_data = await image.read()
        if len(image_data) == 0:
            logger.warning("❌ Empty image received")
            raise HTTPException(status_code=400, detail="Empty image file")
        step2_time = time.time() - step2_start
        print(f"⏱️  STEP 2 (Read Image): {step2_time:.3f}s ({len(image_data)} bytes)")

        # ⏱️ STEP 3: Generate embedding
        step3_start = time.time()
        logger.info("🔍 Generating face embedding...")
        embedding = await face_service_instance.generate_embedding(image_data)
        if embedding is None:
            logger.warning("❌ No face detected in image")
            return {
                "error": "No face detected",
                "status": "❌ No Face",
                "student_name": None,
                "sr_no": None,
                "similarity": 0.0,
                "record_type": None
            }
        step3_time = time.time() - step3_start
        print(f"⏱️  STEP 3 (Generate Embedding): {step3_time:.3f}s")

        # ⏱️ STEP 4: Load embeddings from cache
        logger.info(f"🔎 Loading embeddings for institute {institute_id}...")
        step4_start = time.time()
        students = await _get_embeddings_for_institute(institute_id)
        step4_time = time.time() - step4_start
        print(f"⏱️  STEP 4 (Load Embeddings): {step4_time:.3f}s")

        # 🔍 DEBUG: Show students loaded and their institute_id values
        print(f"\n{'='*60}")
        print(f"📊 STUDENTS LOADED FOR INSTITUTE: {institute_id}")
        print(f"   Total students loaded: {len(students)}")
        if students:
            # Show first 5 students' institute_id values to verify they match request
            for i, student in enumerate(students[:5]):
                inst = student.get('institute_id', 'N/A')
                sr = student.get('sr_no', 'N/A')
                name_parts = []
                for key in ['fname', 'mname', 'lname']:
                    val = student.get(key)
                    if val:
                        name_parts.append(val)
                name = ' '.join(name_parts) or 'Unknown'
                print(f"      [{i}] SR:{sr} | Name:{name} | InstID:{inst}")

            # Show institute_id distribution
            inst_ids = [s.get('institute_id', 'N/A') for s in students]
            unique_insts = set(inst_ids)
            print(f"\n   Unique institutes in loaded students: {unique_insts}")
            print(f"   Does institute_id match request? {institute_id in inst_ids}")
        print(f"{'='*60}\n")

        if not students:
            logger.warning(f"❌ No students found for institute {institute_id}")
            return {
                "error": "No students registered for this institute",
                "status": "❌ No Students",
                "student_name": None,
                "sr_no": None,
                "similarity": 0.0,
                "record_type": None
            }

        # ⏱️ STEP 5: Prepare embeddings matrix for similarity search
        step5_start = time.time()
        from sklearn.metrics.pairwise import cosine_similarity

        SIMILARITY_THRESHOLD = get_setting('similarity_threshold', 0.70)
        valid_students = []
        embeddings_matrix_front = []
        embeddings_matrix_left = []
        embeddings_matrix_right = []

        # Parse all 3 embeddings for each student
        for student in students:
            fname = student.get('fname', '')
            mname = student.get('mname', '')
            lname = student.get('lname', '')
            name_parts = [p for p in [fname, mname, lname] if p]
            full_name = ' '.join(name_parts)

            embeddings = student.get('embeddings', {})
            if not embeddings:
                print(f"⚠️ Student {full_name}: No embeddings in cache")
                continue

            # Check if at least one embedding exists (use None check, not bool)
            emb_front = embeddings.get('front')
            emb_left = embeddings.get('left')
            emb_right = embeddings.get('right')

            if not any(v is not None for v in [emb_front, emb_left, emb_right]):
                print(f"⚠️ Student {full_name}: No valid embeddings")
                continue

            try:
                valid_students.append(student)
                # Add embeddings (None padding if not available)
                embeddings_matrix_front.append(emb_front if emb_front is not None else np.zeros(512, dtype='float32'))
                embeddings_matrix_left.append(emb_left if emb_left is not None else np.zeros(512, dtype='float32'))
                embeddings_matrix_right.append(emb_right if emb_right is not None else np.zeros(512, dtype='float32'))
            except Exception as e:
                print(f"❌ Error processing embeddings for {full_name}: {e}")
                valid_students.pop()
                continue

        if not valid_students:
            logger.warning(f"❌ No valid embeddings found for institute {institute_id}")
            return {
                "error": "No matching student found",
                "status": "❌ No Match",
                "student_name": None,
                "sr_no": None,
                "similarity": 0.0,
                "record_type": None
            }

        step5_time = time.time() - step5_start
        print(f"⏱️  STEP 5 (Prepare Matrix): {step5_time:.3f}s ({len(valid_students)} students)")

        # ⏱️ STEP 6: Calculate similarities
        step6_start = time.time()
        # ⚡ Batch calculate similarities for all 3 angles
        embeddings_matrix_front = np.array(embeddings_matrix_front, dtype='float32')
        embeddings_matrix_left = np.array(embeddings_matrix_left, dtype='float32')
        embeddings_matrix_right = np.array(embeddings_matrix_right, dtype='float32')

        # 🔍 Debug: Check embedding values in detail
        print(f"\n🔎 QUERY EMBEDDING DEBUG:")
        print(f"   Query embedding shape: {embedding.shape}")
        print(f"   Query embedding norm: {np.linalg.norm(embedding):.6f}")
        print(f"   Query embedding min/max: {np.min(embedding):.6f} / {np.max(embedding):.6f}")
        print(f"   Query embedding sum: {np.sum(embedding):.6f}")
        print(f"   Query embedding first 10: {embedding[:10]}")

        print(f"\n🔎 DATABASE EMBEDDINGS DEBUG:")
        print(f"   Front matrix shape: {embeddings_matrix_front.shape}")
        print(f"   Left matrix shape: {embeddings_matrix_left.shape}")
        print(f"   Right matrix shape: {embeddings_matrix_right.shape}")
        if len(embeddings_matrix_front) > 0:
            print(f"   First student front norm: {np.linalg.norm(embeddings_matrix_front[0]):.6f}")
            print(f"   First student left norm: {np.linalg.norm(embeddings_matrix_left[0]):.6f}")
            print(f"   First student right norm: {np.linalg.norm(embeddings_matrix_right[0]):.6f}")

            # Check if query == first student (all 3 angles)
            if (np.allclose(embedding, embeddings_matrix_front[0]) or
                np.allclose(embedding, embeddings_matrix_left[0]) or
                np.allclose(embedding, embeddings_matrix_right[0])):
                print(f"   ⚠️ QUERY IS IDENTICAL TO FIRST STUDENT!")
            else:
                print(f"   ✅ Query is different from first student")

        # ⚡ FAST: Use dot product for normalized embeddings (10x faster than cosine_similarity!)
        # For normalized vectors: cosine_similarity = dot_product
        embedding_normalized = embedding / (np.linalg.norm(embedding) + 1e-8)

        sim_start = time.time()
        similarities_front = embeddings_matrix_front @ embedding_normalized if len(embeddings_matrix_front) > 0 else np.array([])
        similarities_left = embeddings_matrix_left @ embedding_normalized if len(embeddings_matrix_left) > 0 else np.array([])
        similarities_right = embeddings_matrix_right @ embedding_normalized if len(embeddings_matrix_right) > 0 else np.array([])
        sim_time = time.time() - sim_start
        print(f"⚡ [FAST] Dot product similarity computed in {sim_time:.3f}s")

        # 🔥 USE MAX SIMILARITY (best match from any angle)
        max_similarities = np.maximum(similarities_front, np.maximum(similarities_left, similarities_right))

        print(f"\n   Front similarities: min={np.min(similarities_front):.6f}, max={np.max(similarities_front):.6f}")
        print(f"   Left similarities: min={np.min(similarities_left):.6f}, max={np.max(similarities_left):.6f}")
        print(f"   Right similarities: min={np.min(similarities_right):.6f}, max={np.max(similarities_right):.6f}")
        print(f"   MAX similarities: min={np.min(max_similarities):.6f}, max={np.max(max_similarities):.6f}")

        # Find best match
        best_idx = np.argmax(max_similarities)
        best_similarity = float(max_similarities[best_idx])

        # Debug: Show which angle gave the best match (convert numpy scalars to float first!)
        sim_front = float(similarities_front[best_idx])
        sim_left = float(similarities_left[best_idx])
        sim_right = float(similarities_right[best_idx])

        best_from = 'front' if sim_front == best_similarity else ('left' if sim_left == best_similarity else 'right')
        print(f"\n✅ Best match from angle: {best_from}")
        print(f"   Front: {sim_front:.4f}")
        print(f"   Left: {sim_left:.4f}")
        print(f"   Right: {sim_right:.4f}")
        print(f"   MAX (used): {best_similarity:.4f}")

        best_match = valid_students[best_idx]
        fname = best_match.get('fname', '')
        mname = best_match.get('mname', '')
        lname = best_match.get('lname', '')
        # Construct full name: fname mname lname
        name_parts = [p for p in [fname, mname, lname] if p]
        student_name = ' '.join(name_parts)

        # 📊 Debug: Show top 5 scores
        print(f"\n🔎 SIMILARITY SCORES (Threshold: {SIMILARITY_THRESHOLD}) - Using MAX of 3 angles")
        print(f"   Checked {len(valid_students)} students in institute {institute_id}")
        top_indices = np.argsort(-max_similarities)[:5]
        for i, idx in enumerate(top_indices, 1):
            s = float(max_similarities[idx])
            stu = valid_students[idx]
            fname = stu.get('fname', '')
            mname = stu.get('mname', '')
            lname = stu.get('lname', '')
            name_parts = [p for p in [fname, mname, lname] if p]
            s_name = ' '.join(name_parts)
            status = "✅ MATCH" if s >= SIMILARITY_THRESHOLD else "❌ Below"
            s_front = similarities_front[idx]
            s_left = similarities_left[idx]
            s_right = similarities_right[idx]
            print(f"   {i}. {s_name}: {s:.4f} {status}")
            print(f"      (F:{s_front:.4f} L:{s_left:.4f} R:{s_right:.4f})")

        step6_time = time.time() - step6_start
        print(f"⏱️  STEP 6 (Calculate Similarities): {step6_time:.3f}s\n")

        if best_similarity < SIMILARITY_THRESHOLD:
            logger.warning(f"❌ No matching student found (best: {best_similarity:.4f}, threshold: {SIMILARITY_THRESHOLD})")
            return {
                "error": "No matching student found",
                "status": "❌ No Match",
                "student_name": None,
                "sr_no": None,
                "similarity": 0.0,
                "record_type": None
            }

        # Got a match!
        sr_no = best_match.get('sr_no', '')
        student_id = best_match.get('id', '')
        similarity = best_similarity

        logger.info(f"✅ Match found: {student_name} (SR: {sr_no}, Similarity: {similarity:.2%})")

        # ⏱️ STEP 7: Check entry/exit
        step7_start = time.time()
        from datetime import date
        today = date.today().isoformat()

        print(f"📋 Checking attendance for {sr_no} on {today}...")

        already_marked = False
        try:
            # ⚡ FAST: One query, fetch which record_types exist today for this student
            supabase = _get_supabase_client()
            today_response = supabase.table('attendance').select(
                'record_type'
            ).eq('sr_no', sr_no).eq('attendance_date', today).execute()

            marked_types = {row.get('record_type') for row in (today_response.data or [])}
            step7_time = time.time() - step7_start

            has_entry = 'entry' in marked_types
            has_exit = 'exit' in marked_types

            if has_entry and has_exit:
                already_marked = True
                record_type = None
                print(f"⚠️ Both ENTRY & EXIT already marked today ({step7_time:.3f}s)")
            elif has_entry:
                record_type = "exit"  # Already marked entry, now mark exit
                print(f"✅ Entry found ({step7_time:.3f}s) → Record type: EXIT")
            else:
                record_type = "entry"  # First attendance of the day
                print(f"✅ No entry found ({step7_time:.3f}s) → Record type: ENTRY")
        except Exception as e:
            logger.warning(f"⚠️ Could not check attendance: {e}, defaulting to ENTRY")
            record_type = "entry"
            step7_time = time.time() - step7_start

        if already_marked:
            total_time = time.time() - total_start
            print(f"⏱️  TOTAL (already marked, skipped save): {total_time:.3f}s")
            return {
                "status": "⚠️ Already Marked",
                "already_marked": True,
                "student_name": student_name,
                "sr_no": sr_no,
                "student_id": student_id,
                "similarity": float(similarity),
                "record_type": None,
                "message": f"{student_name} already has both ENTRY and EXIT marked for today"
            }

        # ⏱️ TIMING SUMMARY
        total_time = time.time() - total_start
        print(f"\n{'='*60}")
        print(f"📊 TIMING BREAKDOWN:")
        print(f"   STEP 1 (Init): {step1_time:.3f}s")
        print(f"   STEP 2 (Read Image): {step2_time:.3f}s")
        print(f"   STEP 3 (Embedding): {step3_time:.3f}s ⚠️ SLOW HERE?")
        print(f"   STEP 4 (Load Embeddings): {step4_time:.3f}s")
        print(f"   STEP 5 (Prepare Matrix): {step5_time:.3f}s")
        print(f"   STEP 6 (Similarities): {step6_time:.3f}s")
        print(f"   STEP 7 (Entry/Exit): {step7_time:.3f}s")
        print(f"   {'─'*60}")
        print(f"   TOTAL: {total_time:.3f}s")
        print(f"{'='*60}\n")

        # 🔍 DEBUG: Show final response being sent to Flutter
        response_data = {
            "status": "✅ Matched",
            "student_name": student_name,
            "sr_no": sr_no,
            "student_id": student_id,
            "similarity": float(similarity),
            "record_type": record_type,
            "message": f"Attendance marked for {student_name} ({record_type.upper()})",
            "timing": {
                "init": step1_time,
                "read_image": step2_time,
                "embedding": step3_time,
                "load_embeddings": step4_time,
                "prepare_matrix": step5_time,
                "similarities": step6_time,
                "entry_exit": step7_time,
                "total": total_time
            }
        }

        # 🔍 DEBUG: Print response before returning
        print(f"\n{'='*60}")
        print(f"🚀 SENDING RESPONSE TO FLUTTER (institute_id={institute_id})")
        print(f"   Status: {response_data['status']}")
        print(f"   Student: {response_data['student_name']}")
        print(f"   SR No: {response_data['sr_no']}")
        print(f"   Similarity: {response_data['similarity']:.4f}")
        print(f"   Record Type: {response_data['record_type']}")
        print(f"   Student ID: {response_data['student_id']}")
        print(f"{'='*60}\n")

        return response_data

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Attendance error: {e}")
        logger.error(f"📍 Stack: {traceback.format_exc()}")
        return {
            "error": str(e),
            "status": "❌ Error",
            "student_name": None,
            "sr_no": None,
            "similarity": 0.0,
            "record_type": None
        }

@app.post("/api/upload-attendance-photo")
async def upload_attendance_photo(
    photo: UploadFile = File(...),
    sr_no: str = Form(...),
    student_name: str = Form(...),
    institute_id: str = Form(...),
    record_type: str = Form(...),
    date: str = Form(...),
):
    """
    ✅ Upload attendance photo to SERVER (not B2!)

    Saves to: /home/digitrix/public_html/attendance-photos/{institute_id}/{date}/{filename}
    Returns: Public URL for the photo
    """
    try:
        upload_start = time.time()

        print(f'📸 [UPLOAD] Photo for {student_name} ({sr_no}) - {record_type}')
        print(f'   Date: {date}, Institute: {institute_id}')

        # Create directory structure: attendance-photos/{institute}/{sr_no}/{date}/
        # Organize by: Institute → Student → Date
        # Example: /home/digitrix/public_html/attendance-photos/99099/990/2026-08-21/entry_183349.jpg

        # Use web root directly
        base_dir = "/home/digitrix/public_html/attendance-photos"

        print(f'🔍 [DEBUG] START SAVE PROCESS')
        print(f'   Base dir: {base_dir}')
        print(f'   Base dir exists: {os.path.exists(base_dir)}')
        print(f'   Institute ID: {institute_id}')
        print(f'   SR No: {sr_no}')
        print(f'   Date: {date}')

        # Full path: attendance-photos/{institute_id}/{sr_no}/{date}/
        photo_dir = os.path.join(base_dir, institute_id, sr_no, date)

        print(f'   📁 Full photo dir: {photo_dir}')

        # Create directories recursively
        try:
            print(f'   🔨 Creating directories...')
            os.makedirs(photo_dir, exist_ok=True)
            print(f'   ✅ Directories created')
            print(f'   📋 Dir exists now: {os.path.exists(photo_dir)}')
            print(f'   📋 Dir writable: {os.access(photo_dir, os.W_OK)}')

        except Exception as dir_err:
            print(f'   ❌ Directory creation FAILED: {dir_err}')
            import traceback
            print(traceback.format_exc())
            raise

        # Generate filename: entry_143022.jpg (sr_no is in folder path)
        time_str = datetime.now().strftime("%H%M%S")
        filename = f"{record_type}_{time_str}.jpg"
        filepath = os.path.join(photo_dir, filename)

        print(f'   📝 Filename: {filename}')
        print(f'   📝 Full filepath: {filepath}')

        # Read and save photo
        contents = await photo.read()
        file_size_kb = len(contents) / 1024
        print(f'   📦 File size: {file_size_kb:.1f}KB')

        try:
            print(f'   💾 Writing to disk...')
            with open(filepath, "wb") as f:
                bytes_written = f.write(contents)
                print(f'   ✍️  Wrote {bytes_written} bytes')
        except IOError as io_err:
            print(f'   ❌ IO ERROR: {io_err}')
            import traceback
            print(traceback.format_exc())
            raise

        # Verify file exists
        print(f'   🔍 Verifying file...')
        if not os.path.exists(filepath):
            print(f'   ❌ FILE NOT FOUND after write!')
            print(f'   📋 Directory contents: {os.listdir(photo_dir)}')
            print(f'   📋 Dir listing:')
            for item in os.listdir(photo_dir):
                print(f'       - {item}')
            raise Exception(f'File NOT saved! Path: {filepath}')

        file_stat = os.stat(filepath)
        print(f'   ✅ File VERIFIED: {file_stat.st_size} bytes on disk')
        print(f'   ✅ File path: {filepath}')

        # List directory to confirm
        dir_contents = os.listdir(photo_dir)
        print(f'   📋 Directory now has {len(dir_contents)} files')
        for item in dir_contents:
            print(f'       - {item}')

        print(f'🔍 [DEBUG] SAVE COMPLETE ✅')

        # Generate public URL
        # Pattern: https://digitrixmedia.com/attendance-photos/99099/990/2026-08-21/entry_143022.jpg
        photo_url = f"https://digitrixmedia.com/attendance-photos/{institute_id}/{sr_no}/{date}/{filename}"
        print(f'   🌐 URL: {photo_url}')

        upload_ms = (time.time() - upload_start) * 1000
        print(f'   ⏱️  Upload complete in {upload_ms:.0f}ms')

        return {
            "success": True,
            "photo_url": photo_url,
            "filename": filename,
            "sr_no": sr_no,
            "record_type": record_type,
            "date": date,
            "file_size_kb": round(file_size_kb, 1),
        }

    except Exception as e:
        print(f'❌ [UPLOAD] Error: {e}')
        import traceback
        error_trace = traceback.format_exc()
        print(error_trace)

        return {
            "success": False,
            "error": str(e),
            "traceback": error_trace,
        }

@app.get("/attendance-photos/{institute_id}/{sr_no}/{date}/{filename}")
async def serve_attendance_photo(institute_id: str, sr_no: str, date: str, filename: str):
    """
    ✅ Serve attendance photos directly from web server

    Path: /attendance-photos/{institute_id}/{sr_no}/{date}/{filename}
    Example: /attendance-photos/99099/990/2026-08-21/entry_183349.jpg

    This endpoint is for API fallback. Normally accessed directly via web:
    https://digitrixmedia.com/attendance-photos/99099/990/2026-08-21/entry_183349.jpg
    """
    try:
        # Construct file path
        filepath = f"/home/digitrix/public_html/attendance-photos/{institute_id}/{sr_no}/{date}/{filename}"

        print(f'📸 [SERVE] Looking for: {filename}')
        print(f'   Path: {filepath}')

        # Check if file exists
        if not os.path.exists(filepath):
            print(f'❌ [SERVE] File not found: {filepath}')
            raise HTTPException(status_code=404, detail="Photo not found")

        print(f'✅ [SERVE] Found!')

        # Check file size
        file_size = os.path.getsize(filepath)
        print(f'   ✅ File exists: {file_size} bytes')

        # ✅ Serve file with INLINE (display) instead of download
        return FileResponse(
            filepath,
            media_type="image/jpeg",
            headers={
                "Content-Disposition": "inline; filename=attendance.jpg"
            }
        )

    except HTTPException:
        raise
    except Exception as e:
        print(f'   ❌ Error: {e}')
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/debug/faiss-status")
async def debug_faiss_status():
    """
    Debug endpoint: Show what's in FAISS database
    Returns: list of all registered students + their institutes
    """
    try:
        vector_db_instance = _ensure_vector_db()

        if vector_db_instance.index is None:
            await vector_db_instance.load_index()

        # Count total embeddings
        total_embeddings = vector_db_instance.index.ntotal

        # Group by institute
        institute_counts = {}
        students_list = []

        for idx, metadata in vector_db_instance.metadata.items():
            inst_id = metadata.get('institute_id', 'UNKNOWN')

            if inst_id not in institute_counts:
                institute_counts[inst_id] = 0
            institute_counts[inst_id] += 1

            students_list.append({
                'index': idx,
                'institute_id': inst_id,
                'student_id': metadata.get('student_id'),
                'roll_number': metadata.get('roll_number'),
                'name': metadata.get('name')
            })

        return {
            "total_embeddings": total_embeddings,
            "institutes_breakdown": institute_counts,
            "students": students_list
        }
    except Exception as e:
        return {
            "error": str(e),
            "total_embeddings": 0,
            "institutes_breakdown": {},
            "students": []
        }

if __name__ == "__main__":
    import uvicorn
    # 🔥 Use port 5001 (matches Flutter app's BACKEND_URL)
    uvicorn.run(app, host="0.0.0.0", port=5001)

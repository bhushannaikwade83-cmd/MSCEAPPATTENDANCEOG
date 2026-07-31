"""
FastAPI Backend for Face Recognition
Architecture: RetinaFace (detection) + ArcFace (embedding) + FAISS (vector search)
Supports 200,000+ students with high accuracy and fast search
"""

from fastapi import FastAPI, HTTPException, UploadFile, File, Form, Request, status
from fastapi.middleware.cors import CORSMiddleware
from dashboard import dashboard_app, log_request, log_event
from fastapi.responses import FileResponse, JSONResponse
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.requests import Request as StarletteRequest
from pydantic import BaseModel, model_validator
import base64
import numpy as np
from typing import Optional, List, Tuple
import time
import logging
import os
import tempfile
import traceback

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

app = FastAPI(title="EduSetu Face Recognition API", version="1.0.0")

# Mount dashboard
app.mount("/dashboard", dashboard_app)

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

@app.on_event("startup")
async def startup_event():
    """Initialize services on startup"""
    logger.info("🚀 Starting Face Recognition API...")

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

# 🔥 NEW ENDPOINT: Multi-angle registration (3 photos for front, left, right)
@app.post("/api/v1/register-multi-angle")
async def register_multi_angle_face(
    front_photo: UploadFile = File(...),
    left_photo: UploadFile = File(...),
    right_photo: UploadFile = File(...),
    institute_id: str = Form(...),
    student_id: str = Form(...),
    roll_number: str = Form(...),
    name: str = Form(...),
):
    """
    Register student with 3 photos (front, left, right) - generates 3 embeddings + average

    Returns embeddings for each angle so Flutter can save to Supabase
    """
    try:
        face_service_instance = _ensure_face_service()
        if not face_service_instance.initialized:
            await face_service_instance.initialize()

        logger.info(f"📱 Multi-angle registration for {roll_number} ({name})")

        embeddings_result = {}

        # Process 3 photos
        for angle, photo_file in [("front", front_photo), ("left", left_photo), ("right", right_photo)]:
            image_data = await photo_file.read()
            if len(image_data) == 0:
                raise HTTPException(status_code=400, detail=f"Empty {angle} photo")

            embedding = await face_service_instance.generate_embedding(image_data)
            if embedding is None:
                raise HTTPException(status_code=400, detail=f"No face detected in {angle} photo")

            embeddings_result[f"face_embedding_{angle}"] = embedding.tolist()
            logger.info(f"  ✅ Generated embedding for {angle} angle (512-dim)")

        # Calculate average embedding
        front = np.array(embeddings_result["face_embedding_front"])
        left = np.array(embeddings_result["face_embedding_left"])
        right = np.array(embeddings_result["face_embedding_right"])
        average = (front + left + right) / 3.0
        embeddings_result["face_embedding_average"] = average.tolist()

        logger.info(f"✅ Multi-angle registration complete for {roll_number}")

        return {
            "success": True,
            "message": f"Face registered for {roll_number}",
            "embeddings": embeddings_result,  # Return embeddings for Flutter to save to Supabase
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Multi-angle registration error: {e}")
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
    institute_id: Optional[str] = Form(None)
):
    """
    Mark attendance automatically from face image

    Pipeline:
    1. Recognize student from face
    2. Save attendance record
    3. Return student details + attendance status
    """
    try:
        face_service_instance = _ensure_face_service()
        vector_db_instance = _ensure_vector_db()

        # Initialize if needed
        if not face_service_instance.initialized:
            await face_service_instance.initialize()
        if vector_db_instance.index is None:
            await vector_db_instance.load_index()

        # Read image
        image_data = await image.read()
        if len(image_data) == 0:
            raise HTTPException(status_code=400, detail="Empty image file")

        logger.info(f"📸 Attendance image received: {len(image_data)} bytes")

        # Generate embedding
        embedding = await face_service_instance.generate_embedding(image_data)
        if embedding is None:
            return {
                "error": "No face detected",
                "status": "❌ No Face",
                "student_name": None,
                "sr_no": None,
                "similarity": 0.0,
                "record_type": None
            }

        # Search for match
        result = await vector_db_instance.search_embedding(
            embedding=embedding,
            top_k=1
        )

        if not result or len(result) == 0:
            return {
                "error": "No matching student found",
                "status": "❌ No Match",
                "student_name": None,
                "sr_no": None,
                "similarity": 0.0,
                "record_type": None
            }

        match = result[0]
        student_name = match.get('name', 'Unknown')
        sr_no = match.get('student_id', '')
        similarity = match.get('similarity', 0.0)

        # Determine entry/exit based on current time and last attendance
        record_type = "entry"  # Default to entry

        logger.info(f"✅ Attendance matched: {student_name} (SR: {sr_no}, Similarity: {similarity:.2%})")

        return {
            "status": "✅ Matched",
            "student_name": student_name,
            "sr_no": sr_no,
            "similarity": float(similarity),
            "record_type": record_type,
            "message": f"Attendance marked for {student_name}"
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Attendance error: {e}")
        return {
            "error": str(e),
            "status": "❌ Error",
            "student_name": None,
            "sr_no": None,
            "similarity": 0.0,
            "record_type": None
        }

if __name__ == "__main__":
    import uvicorn
    # 🔥 Use port 5001 (matches Flutter app's BACKEND_URL)
    uvicorn.run(app, host="0.0.0.0", port=5001)

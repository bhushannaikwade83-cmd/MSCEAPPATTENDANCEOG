"""
Face Recognition Service using RetinaFace (detection) + ArcFace (embedding) + FAISS (vector search)

Architecture:
1. RetinaFace: State-of-the-art face detection (high accuracy, handles various angles/lighting)
2. ArcFace: Deep face embedding model (512-dimensional vectors)
3. FAISS: Fast similarity search for large-scale face recognition

This combination provides:
- High accuracy face detection (RetinaFace)
- Robust face embeddings (ArcFace R100)
- Fast vector search (FAISS, handles 200k+ vectors in <50ms)
"""

import numpy as np
import cv2
import io
from PIL import Image
from typing import Optional, Tuple
import logging
import os
import time
import base64
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError

# Try to import InsightFace (provides RetinaFace detector + ArcFace embedding)
try:
    import insightface
    INSIGHTFACE_AVAILABLE = True
except ImportError:
    INSIGHTFACE_AVAILABLE = False
    logging.warning("⚠️ InsightFace not installed. Install with: pip install insightface onnxruntime")

logger = logging.getLogger(__name__)

class FaceRecognitionService:
    """
    Face Recognition Service using:
    - RetinaFace: Face detection
    - ArcFace: Face embedding generation (512-dim)
    - FAISS: Vector similarity search (handled by vector_db.py)
    """
    
    def __init__(self):
        self.app = None
        self.initialized = False
        self.model_name = 'buffalo_l'  # Best accuracy model
        # buffalo_l includes:
        # - RetinaFace detector (high accuracy face detection)
        # - ArcFace R100 embedding model (512-dimensional vectors)
        
    async def initialize(self):
        """
        Initialize RetinaFace detector + ArcFace embedding model
        
        The buffalo_l model from InsightFace includes:
        - RetinaFace: Face detection (handles various angles, lighting, occlusions)
        - ArcFace R100: Face embedding (512-dimensional vectors)
        """
        if not INSIGHTFACE_AVAILABLE:
            raise ImportError(
                "InsightFace is not installed. Please install it with: "
                "pip install insightface onnxruntime"
            )
        
        try:
            logger.info("🔄 Initializing RetinaFace (detection) + ArcFace (embedding)...")
            
            # Initialize InsightFace FaceAnalysis
            # This loads both RetinaFace detector and ArcFace embedding model
            # buffalo_l is the best model (ArcFace R100, 512-dim embeddings)
            # It will automatically download model files on first run
            self.app = insightface.app.FaceAnalysis(
                name=self.model_name,
                providers=['CPUExecutionProvider']  # Use CPU for Cloud Run compatibility
            )
            
            # Prepare model (ctx_id=-1 for CPU, 0 for GPU)
            # det_size=(640, 640) for RetinaFace detection accuracy
            logger.info("🔄 Preparing RetinaFace + ArcFace models (this may take 30-60 seconds on first run)...")
            self.app.prepare(ctx_id=-1, det_size=(640, 640))
            
            # Verify model is loaded correctly
            if self.app is None:
                raise RuntimeError("RetinaFace + ArcFace models failed to initialize")
            
            self.initialized = True
            logger.info(f"✅ RetinaFace (detection) + ArcFace (embedding) loaded successfully")
            logger.info(f"✅ Model: {self.model_name} (ArcFace R100, 512-dim embeddings)")
            logger.info("✅ Architecture: RetinaFace → ArcFace → FAISS")
            logger.info("✅ Face recognition service ready")
            
        except Exception as e:
            import traceback
            error_traceback = traceback.format_exc()
            logger.error(f"❌ Error initializing RetinaFace + ArcFace: {e}")
            logger.error(f"   Full traceback:\n{error_traceback}")
            logger.info("💡 Tip: Model will be downloaded automatically on first run")
            logger.info("💡 Tip: Ensure you have internet connection for first-time model download")
            raise RuntimeError(f"Failed to initialize RetinaFace + ArcFace models: {str(e)}") from e
        
    def _align_face(self, face: object, image_rgb: np.ndarray) -> Optional[np.ndarray]:
        """
        Step 1.5: Align face using InsightFace's official method

        Uses face.kps (5-point keypoints):
        - Left eye, Right eye, Nose, Left mouth, Right mouth

        This is the OFFICIAL InsightFace approach for ArcFace alignment.
        ✅ Not 106 landmarks - just 5 keypoints!
        ✅ Uses InsightFace's norm_crop() which ArcFace expects

        Args:
            face: Face object with kps (5-point keypoints)
            image_rgb: RGB image

        Returns:
            Aligned 112×112 face image, or None if alignment fails
        """
        try:
            from insightface.utils import face_align

            # ✅ USE face.kps (5-point keypoints), NOT face.landmark_2d_106!
            if not hasattr(face, 'kps') or face.kps is None:
                logger.error("❌ Face has no 5-point keypoints (kps)")
                return None

            # Debug: Check kps shape
            print(f"🔍 [DEBUG] face.kps shape: {face.kps.shape}")
            if face.kps.shape != (5, 2):
                logger.error(f"❌ Expected kps shape (5, 2), got {face.kps.shape}")
                return None

            # ✅ Use InsightFace's official alignment method
            # This is exactly what ArcFace ONNX model uses internally
            aligned_face = face_align.norm_crop(
                image_rgb,
                landmark=face.kps,  # 5-point keypoints
                image_size=112,
                mode='arcface'
            )

            print(f"✅ [ALIGN] Face aligned to 112×112 using InsightFace norm_crop()")
            print(f"   Shape: {aligned_face.shape}, dtype: {aligned_face.dtype}")
            return aligned_face

        except Exception as e:
            logger.error(f"❌ Face alignment error: {e}")
            print(f"❌ Face alignment FAILED - rejecting face")
            print(f"   Error details: {type(e).__name__}: {str(e)}")
            return None  # Reject - NO fallback to original!

    def _detect_face_retinaface(self, image_rgb: np.ndarray) -> Optional[object]:
        """
        Step 1: Detect face using RetinaFace detector

        Args:
            image_rgb: RGB image as numpy array

        Returns:
            Face object with bounding box, landmarks, and embedding, or None if no face detected
        """
        try:
            faces = self.app.get(image_rgb)

            if len(faces) == 0:
                return None

            if len(faces) > 1:
                faces = sorted(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]), reverse=True)

            return faces[0]
        except Exception as e:
            logger.error(f"❌ RetinaFace detection error: {e}")
            return None
    
    def _extract_embedding_arcface(self, face: object) -> Optional[np.ndarray]:
        """Extract 512-dimensional embedding using ArcFace (already computed by RetinaFace)"""
        try:
            embedding = face.embedding
            # L2 normalize embedding (required for cosine similarity in FAISS)
            embedding = embedding / np.linalg.norm(embedding)
            return embedding
        except Exception as e:
            logger.error(f"❌ ArcFace embedding extraction error: {e}")
            return None
    
    async def generate_embedding(self, image_data: bytes) -> Optional[np.ndarray]:
        """
        Generate 512-dimensional face embedding from image
        
        Pipeline:
        1. RetinaFace: Detect face in image
        2. ArcFace: Extract 512-dim embedding from detected face
        3. FAISS: Vector search (handled by vector_db.py)
        
        Args:
            image_data: Raw image bytes (JPEG/PNG)
            
        Returns:
            512-dimensional numpy array (L2-normalized embedding) or None if no face detected
        """
        if not self.initialized:
            await self.initialize()
        
        try:
            # 🔥 STEP 1: Validate image data
            if not isinstance(image_data, bytes):
                error_msg = f"Image data is not bytes: {type(image_data)}"
                logger.error(f"❌ {error_msg}")
                raise ValueError(error_msg)
            
            if len(image_data) == 0:
                error_msg = "Image data is empty"
                logger.error(f"❌ {error_msg}")
                raise ValueError(error_msg)
            
            logger.info(f"📦 Received image data: {len(image_data)} bytes")

            # Decode image using OpenCV
            np_arr = np.frombuffer(image_data, np.uint8)
            image = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

            if image is None:
                raise ValueError("Image decoding failed")

            # Convert BGR to RGB (InsightFace expects RGB)
            image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

            # Resize if too small
            height, width = image_rgb.shape[:2]
            if width < 160 or height < 160:
                image_rgb = cv2.resize(image_rgb, (640, 640))
            elif image_rgb.shape[0] < 320 or image_rgb.shape[1] < 320:
                image_rgb = cv2.resize(image_rgb, (640, 640))

            # RetinaFace Detection - NO rotation attempts for registration
            face = self._detect_face_retinaface(image_rgb)

            if face is None:
                error_msg = "RetinaFace: No face detected in image. Please ensure:\n" \
                           "• Face is clearly visible and fills 30-50% of frame\n" \
                           "• Good lighting (avoid backlight)\n" \
                           "• Looking directly at camera\n" \
                           "• Eyes open, clear view\n" \
                           "• Image is at least 160x160 pixels"
                logger.error(f"❌ {error_msg}")
                print("❌ RetinaFace: No face detected - check debug_received.jpg")
                raise ValueError(error_msg)

            # Face Alignment
            aligned_face = self._align_face(face, image_rgb)

            if aligned_face is None:
                raise ValueError("Face alignment failed")

            # Extract ArcFace Embedding (already computed by RetinaFace detection)
            embedding = self._extract_embedding_arcface(face)

            if embedding is None:
                raise ValueError("ArcFace: Failed to extract embedding")

            return embedding
            
        except Exception as e:
            import traceback
            error_msg = str(e) if str(e) else repr(e)
            error_type = type(e).__name__
            error_traceback = traceback.format_exc()
            
            # Ensure we have a meaningful error message
            if not error_msg or len(error_msg.strip()) == 0:
                error_msg = f"{error_type} occurred during face embedding generation"
            
            logger.error(f"❌ Error generating embedding:")
            logger.error(f"   Type: {error_type}")
            logger.error(f"   Message: {error_msg}")
            logger.error(f"   Traceback:\n{error_traceback}")
            
            # Re-raise with better context so main.py can handle it properly
            raise RuntimeError(f"RetinaFace + ArcFace pipeline failed: {error_msg}") from e

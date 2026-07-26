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
        
    def _detect_face_retinaface(self, image_rgb: np.ndarray) -> Optional[object]:
        """
        Step 1: Detect face using RetinaFace detector
        
        Args:
            image_rgb: RGB image as numpy array
            
        Returns:
            Face object with bounding box, landmarks, and embedding, or None if no face detected
        """
        try:
            # RetinaFace detection + ArcFace embedding in one call
            # InsightFace's get() method uses RetinaFace for detection
            faces = self.app.get(image_rgb)
            
            if len(faces) == 0:
                return None
            
            # Return the largest face (by bounding box area)
            if len(faces) > 1:
                logger.warning(f"⚠️ Multiple faces detected ({len(faces)}), using largest face")
                # Sort by bounding box area (largest first)
                faces = sorted(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]), reverse=True)
            
            return faces[0]
        except Exception as e:
            logger.error(f"❌ RetinaFace detection error: {e}")
            return None
    
    def _extract_embedding_arcface(self, face: object) -> Optional[np.ndarray]:
        """
        Step 2: Extract 512-dimensional embedding using ArcFace
        
        Args:
            face: Face object from RetinaFace detection (contains pre-computed ArcFace embedding)
            
        Returns:
            512-dimensional numpy array (L2-normalized embedding) or None
        """
        try:
            # ArcFace embedding is already computed during RetinaFace detection
            # InsightFace computes both detection and embedding together for efficiency
            embedding = face.embedding  # Already 512-dim from ArcFace R100
            
            # L2 normalize embedding (required for cosine similarity in FAISS)
            embedding = embedding / np.linalg.norm(embedding)
            
            logger.info(f"✅ ArcFace embedding extracted: shape={embedding.shape}, norm={np.linalg.norm(embedding):.4f}")
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
            
            # 🔥 STEP 2: Decode image using OpenCV (CORRECT METHOD)
            # This is the correct way to decode base64 image bytes
            np_arr = np.frombuffer(image_data, np.uint8)
            image = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
            
            if image is None:
                logger.warning("⚠️ OpenCV decode failed, trying PIL...")
                # Fallback to PIL if OpenCV fails
                try:
                    pil_image = Image.open(io.BytesIO(image_data))
                    # Convert PIL to OpenCV format (RGB -> BGR)
                    image = cv2.cvtColor(np.array(pil_image), cv2.COLOR_RGB2BGR)
                    if image is None:
                        error_msg = "Image decoding failed with both OpenCV and PIL"
                        logger.error(f"❌ {error_msg}")
                        raise ValueError(error_msg)
                except Exception as e:
                    error_msg = f"Image decoding failed: {str(e)}"
                    logger.error(f"❌ {error_msg}")
                    raise ValueError(error_msg) from e
            
            # 🔥 STEP 3: Debug prints BEFORE face detection
            print("=" * 50)
            print("🔍 DEBUG: Image received and decoded")
            print(f"Image type: {type(image)}")
            print(f"Image shape: {image.shape}")
            print(f"Image dtype: {image.dtype}")
            print(f"Image min/max: {image.min()}/{image.max()}")
            print("=" * 50)
            
            # 🔥 STEP 4: Save debug image
            try:
                import tempfile
                debug_dir = os.path.join(tempfile.gettempdir(), "debug_images")
                os.makedirs(debug_dir, exist_ok=True)
                debug_path = os.path.join(debug_dir, "debug_received.jpg")
                cv2.imwrite(debug_path, image)
                logger.info(f"💾 Debug image saved: {debug_path}")
                print(f"💾 Debug image saved: {debug_path}")
                print("   → Check if image is clear, face visible, and not sideways!")
            except Exception as e:
                logger.warning(f"⚠️ Could not save debug image: {e}")
            
            # 🔥 STEP 5: Check if image is too small
            height, width = image.shape[:2]
            print(f"📏 Image dimensions: {width}x{height}")
            
            if width < 160 or height < 160:
                logger.warning(f"⚠️ Image too small: {width}x{height} (minimum 160x160)")
                print(f"⚠️ Image too small: {width}x{height} - Resizing to 640x640")
                image = cv2.resize(image, (640, 640))
                print(f"✅ Resized to: {image.shape[1]}x{image.shape[0]}")
            
            # 🔥 STEP 6: Handle rotation (MOST COMMON FLUTTER ISSUE)
            original_image = image.copy()
            
            # 🔥 STEP 7: Convert BGR to RGB (InsightFace expects RGB)
            image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            print(f"✅ Converted BGR to RGB")
            
            # 🔥 STEP 8: Resize if too small
            if image_rgb.shape[0] < 320 or image_rgb.shape[1] < 320:
                print(f"⚠️ Image still small after initial resize: {image_rgb.shape}")
                image_rgb = cv2.resize(image_rgb, (640, 640))
                print(f"✅ Resized to: {image_rgb.shape}")
            
            # 🔥 STEP 9: RetinaFace Detection
            print("🔍 Step 1: RetinaFace face detection...")
            face = self._detect_face_retinaface(image_rgb)
            
            if face is None:
                logger.warning("⚠️ RetinaFace: No face detected with original orientation")
                print("⚠️ RetinaFace: No face detected - trying rotations (common Flutter camera issue)...")
                
                # Try rotations if no face detected
                rotations_to_try = [
                    (cv2.ROTATE_90_CLOCKWISE, "90° clockwise"),
                    (cv2.ROTATE_90_COUNTERCLOCKWISE, "90° counter-clockwise"),
                    (cv2.ROTATE_180, "180°")
                ]
                
                for rotation_code, rotation_name in rotations_to_try:
                    try:
                        print(f"🔄 RetinaFace: Trying rotation {rotation_name}...")
                        rotated_image = cv2.rotate(original_image, rotation_code)
                        rotated_rgb = cv2.cvtColor(rotated_image, cv2.COLOR_BGR2RGB)
                        
                        # Resize if needed
                        if rotated_rgb.shape[0] < 320 or rotated_rgb.shape[1] < 320:
                            rotated_rgb = cv2.resize(rotated_rgb, (640, 640))
                        
                        # Try RetinaFace detection with rotated image
                        face = self._detect_face_retinaface(rotated_rgb)
                        if face is not None:
                            logger.info(f"✅ RetinaFace: Face detected after {rotation_name} rotation")
                            print(f"✅ RetinaFace: Face detected after {rotation_name} rotation!")
                            image_rgb = rotated_rgb
                            break
                    except Exception as e:
                        logger.debug(f"⚠️ Rotation {rotation_name} failed: {e}")
                        continue
            
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
            
            # 🔥 STEP 10: ArcFace Embedding Extraction
            print("🔍 Step 2: ArcFace embedding extraction...")
            embedding = self._extract_embedding_arcface(face)
            
            if embedding is None:
                error_msg = "ArcFace: Failed to extract embedding from detected face"
                logger.error(f"❌ {error_msg}")
                raise ValueError(error_msg)
            
            logger.info("✅ Pipeline complete: RetinaFace → ArcFace → 512-dim embedding (L2-normalized)")
            print(f"✅ ArcFace embedding: shape={embedding.shape}, norm={np.linalg.norm(embedding):.4f}")
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

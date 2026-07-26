"""
Complete ArcFace Face Recognition Service using InsightFace
This is the improved version with full implementation
"""

import insightface
import numpy as np
import cv2
from typing import Optional
import logging

logger = logging.getLogger(__name__)

class FaceRecognitionService:
    """Service for generating face embeddings using ArcFace (InsightFace)"""
    
    def __init__(self):
        self.app = None
        self.initialized = False
        
    async def initialize(self):
        """Initialize ArcFace model"""
        try:
            # Initialize InsightFace with ArcFace model
            # This will automatically download model on first run
            self.app = insightface.app.FaceAnalysis(
                name='arcface_r100_v1',  # Best accuracy model
                providers=['CUDAExecutionProvider', 'CPUExecutionProvider']
            )
            
            # Prepare model (ctx_id=0 for GPU, -1 for CPU)
            self.app.prepare(ctx_id=0, det_size=(640, 640))
            
            self.initialized = True
            logger.info("✅ ArcFace model loaded successfully")
            
        except Exception as e:
            logger.error(f"❌ Error loading ArcFace model: {e}")
            logger.info("💡 Tip: Model will be downloaded automatically on first run")
            raise
    
    async def generate_embedding(self, image_data: bytes) -> Optional[np.ndarray]:
        """
        Generate 512-dimensional face embedding from image
        
        Args:
            image_data: Raw image bytes (JPEG/PNG)
            
        Returns:
            512-dimensional numpy array (embedding) or None if no face detected
        """
        if not self.initialized:
            await self.initialize()
        
        try:
            # Decode image from bytes
            nparr = np.frombuffer(image_data, np.uint8)
            image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if image is None:
                logger.warning("⚠️ Could not decode image")
                return None
            
            # Detect faces and extract embeddings
            faces = self.app.get(image)
            
            if len(faces) == 0:
                logger.warning("⚠️ No face detected in image")
                return None
            
            if len(faces) > 1:
                logger.warning(f"⚠️ Multiple faces detected ({len(faces)}), using first face")
            
            # Get embedding from first (largest) face
            face = faces[0]
            embedding = face.embedding  # 512-dim vector
            
            # L2 normalize embedding
            embedding = embedding / np.linalg.norm(embedding)
            
            logger.info(f"✅ Face embedding generated (512-dim, L2-normalized)")
            return embedding
            
        except Exception as e:
            logger.error(f"❌ Error generating embedding: {e}")
            return None
    
    def calculate_similarity(self, embedding1: np.ndarray, embedding2: np.ndarray) -> float:
        """
        Calculate cosine similarity between two embeddings
        
        Args:
            embedding1: First embedding (512-dim)
            embedding2: Second embedding (512-dim)
            
        Returns:
            Similarity score between 0 and 1 (1 = identical)
        """
        # Cosine similarity for L2-normalized vectors = dot product
        similarity = np.dot(embedding1, embedding2)
        return float(similarity.clip(0, 1))

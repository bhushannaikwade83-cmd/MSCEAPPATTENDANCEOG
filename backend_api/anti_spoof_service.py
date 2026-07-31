"""
AI Anti-Spoof Detection Service
FAST MODE: Simple liveness detection (no feature extraction)
"""

import cv2
import numpy as np
import logging
from typing import Dict
import os

logger = logging.getLogger(__name__)

class AntiSpoofService:
    """
    Fast anti-spoofing detection using image properties
    No heavy feature extraction - responds in < 1 second
    """

    initialized = False

    @classmethod
    async def initialize(cls):
        """Initialize anti-spoof service"""
        try:
            cls.initialized = True
            logger.info("✅ Fast Anti-Spoof Service initialized")
        except Exception as e:
            logger.error(f"❌ Failed to initialize: {e}")
            cls.initialized = False

    @classmethod
    def detect_spoof(cls, image_data: bytes) -> Dict:
        """
        FAST spoof detection using simple image analysis
        Returns: {'is_real': bool, 'confidence': float (0-1), 'label': str}
        """
        try:
            # Decode image
            nparr = np.frombuffer(image_data, np.uint8)
            image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

            if image is None:
                return {
                    'is_real': False,
                    'confidence': 1.0,
                    'score': 0.0,
                    'label': 'invalid',
                    'details': {'error': 'Failed to decode image'}
                }

            # Multi-check spoof detection
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

            # 1. Laplacian variance (edge sharpness)
            laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()

            # 2. Brightness check
            brightness = np.mean(gray)

            # 3. Color saturation (photos have different saturation than skin)
            hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
            saturation = hsv[:, :, 1]
            avg_saturation = np.mean(saturation)

            # 4. Texture via edges (real faces have specific edge distribution)
            edges = cv2.Canny(gray, 100, 200)
            edge_ratio = np.sum(edges > 0) / (gray.shape[0] * gray.shape[1])

            # Multi-factor decision - STRICT MODE
            # Real faces must pass ALL checks
            is_real = bool(
                (laplacian_var > 200) and  # High sharpness (stricter than 100)
                (50 < brightness < 200) and  # Normal lighting
                (80 < avg_saturation < 150) and  # Normal skin saturation
                (0.05 < edge_ratio < 0.20)  # Natural edge distribution
            )

            # Confidence = average of multiple factors (0-1)
            laplacian_score = min(1.0, laplacian_var / 500.0)
            saturation_score = 1.0 if (80 < avg_saturation < 150) else 0.0
            edge_score = 1.0 if (0.05 < edge_ratio < 0.20) else 0.0
            confidence = float((laplacian_score + saturation_score + edge_score) / 3.0)

            return {
                'is_real': is_real,
                'confidence': confidence,
                'score': confidence,
                'label': 'live' if is_real else 'spoof',
                'details': {
                    'laplacian_variance': float(laplacian_var),
                    'brightness': float(brightness),
                    'avg_saturation': float(avg_saturation),
                    'edge_ratio': float(edge_ratio),
                }
            }

        except Exception as e:
            logger.error(f"❌ Error in spoof detection: {e}")
            return {
                'is_real': True,
                'confidence': 0.5,
                'score': 0.5,
                'label': 'live',
                'details': {'error': str(e)}
            }

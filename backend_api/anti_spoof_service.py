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

            # Fast spoof detection using Laplacian variance (blur detection)
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

            # Laplacian variance - measures edge sharpness
            # Real faces have high variance, blurry photos have low variance
            laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()

            # Brightness check - too dark or too bright might indicate fake
            brightness = np.mean(gray)

            # Threshold-based decision
            # High Laplacian variance + normal brightness = REAL
            is_real = bool((laplacian_var > 100) and (50 < brightness < 200))

            # Confidence based on Laplacian variance
            confidence = float(min(1.0, laplacian_var / 500.0))

            return {
                'is_real': is_real,
                'confidence': confidence,
                'score': confidence,
                'label': 'live' if is_real else 'spoof',
                'details': {
                    'laplacian_variance': float(laplacian_var),
                    'brightness': float(brightness),
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

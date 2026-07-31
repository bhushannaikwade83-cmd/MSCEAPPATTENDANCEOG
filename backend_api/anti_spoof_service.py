"""
AI Anti-Spoof Detection Service
SIMPLIFIED: Laplacian variance only (fast & reliable)
"""

import cv2
import numpy as np
import logging
from typing import Dict
import os

logger = logging.getLogger(__name__)

class AntiSpoofService:
    """
    Fast anti-spoofing detection using Laplacian variance
    Real faces: high variance (lots of texture/detail)
    Photos: lower variance (smooth/flat)
    """

    initialized = False

    @classmethod
    async def initialize(cls):
        """Initialize anti-spoof service"""
        try:
            cls.initialized = True
            logger.info("✅ Anti-Spoof Service initialized")
        except Exception as e:
            logger.error(f"❌ Failed to initialize: {e}")
            cls.initialized = False

    @classmethod
    def detect_spoof(cls, image_data: bytes) -> Dict:
        """
        SIMPLE spoof detection: Laplacian variance
        High variance = Real face
        Low variance = Photo/screen
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
                }

            # Convert to grayscale
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

            # Laplacian variance - ONLY metric
            # Real faces: 150-500+ (high detail/texture)
            # Photos: 50-150 (smooth/flat)
            # Screens: 50-200 (artificial patterns)
            laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()

            # Simple threshold
            # Real if Laplacian > 80, Photo if < 80
            is_real = bool(laplacian_var > 80)

            # Confidence (0-1): how confident we are it's real
            # Higher Laplacian = more real
            confidence = min(1.0, laplacian_var / 300.0)

            return {
                'is_real': is_real,
                'confidence': float(confidence),
                'score': float(confidence),
                'label': 'live' if is_real else 'spoof',
                'details': {
                    'laplacian_variance': float(laplacian_var),
                }
            }

        except Exception as e:
            logger.error(f"❌ Error: {e}")
            return {
                'is_real': True,
                'confidence': 0.5,
                'score': 0.5,
                'label': 'live',
                'details': {'error': str(e)}
            }

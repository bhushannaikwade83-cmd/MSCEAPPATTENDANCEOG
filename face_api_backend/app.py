"""
Professional Face Recognition API Backend
Uses: InsightFace, FAISS, MiniFASNet
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import os
import numpy as np
import cv2
from io import BytesIO
import base64
import logging
import json

# Face Recognition Imports
import insightface
from minifacenet import MiniNet

# FAISS for duplicate detection
import faiss

# Logging setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# ============================================================================
# INITIALIZE AI MODELS
# ============================================================================

class FaceModelManager:
    """Manage all face recognition models"""

    def __init__(self):
        logger.info("🧠 Loading InsightFace model...")
        # InsightFace model - state-of-the-art face detection & embedding
        self.detector = insightface.app.FaceAnalysis(
            providers=['CUDAExecutionProvider', 'CPUExecutionProvider']
        )
        self.detector.prepare(ctx_id=0, det_size=(640, 640))

        logger.info("👁️ Loading MiniFASNet liveness model...")
        # MiniFASNet - lightweight liveness detection
        self.liveness_model = MiniNet()

        logger.info("🔍 Initializing FAISS index...")
        # FAISS index for duplicate detection
        self.embedding_dim = 512  # InsightFace embeddings are 512-dim
        self.faiss_index = faiss.IndexFlatL2(self.embedding_dim)
        self.student_registry = {}  # student_id -> embedding

        logger.info("✅ All models loaded successfully")

    def extract_embedding(self, photo_bytes: bytes):
        """
        Extract face embedding using InsightFace
        Returns: embedding (512-dim vector) or None if face not detected
        """
        try:
            # Decode image
            nparr = np.frombuffer(photo_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

            # Detect faces
            faces = self.detector.get(img)

            if not faces:
                logger.warning("❌ No face detected in image")
                return None

            # Get best (largest) face
            face = max(faces, key=lambda x: (x.bbox[2] - x.bbox[0]) * (x.bbox[3] - x.bbox[1]))

            # Extract embedding (512-dimensional vector)
            embedding = face.embedding

            # Normalize
            embedding = embedding / np.linalg.norm(embedding)

            logger.info(f"✅ Embedding extracted: {embedding.shape}")
            return embedding.tolist()

        except Exception as e:
            logger.error(f"❌ Embedding extraction error: {e}")
            return None

    def check_liveness(self, photo_bytes: bytes):
        """
        Check if photo is a real face (liveness detection)
        Using MiniFASNet
        Returns: liveness_score (0-1), confidence
        """
        try:
            # Decode image
            nparr = np.frombuffer(photo_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

            # Detect faces first
            faces = self.detector.get(img)

            if not faces:
                return {
                    'is_real': False,
                    'liveness_score': 0.0,
                    'reason': 'No face detected'
                }

            # Get best face
            face = max(faces, key=lambda x: (x.bbox[2] - x.bbox[0]) * (x.bbox[3] - x.bbox[1]))

            # Extract face region
            bbox = face.bbox.astype(int)
            x1, y1, x2, y2 = bbox
            face_img = img[y1:y2, x1:x2]

            # Resize to model input size (typically 224x224)
            face_img = cv2.resize(face_img, (224, 224))

            # Check liveness
            liveness_score = self.liveness_model.predict(face_img)

            # Threshold: > 0.5 = real face, < 0.5 = spoofed/fake
            is_real = liveness_score > 0.5

            logger.info(f"👁️ Liveness score: {liveness_score:.3f} - {'REAL' if is_real else 'SPOOF'}")

            return {
                'is_real': is_real,
                'liveness_score': float(liveness_score),
                'confidence': abs(liveness_score - 0.5) * 2  # 0-1 confidence
            }

        except Exception as e:
            logger.error(f"❌ Liveness check error: {e}")
            return {
                'is_real': False,
                'liveness_score': 0.0,
                'error': str(e)
            }

    def check_duplicate(self, embedding: list, student_id: str = None, threshold: float = 0.60):
        """
        Check if embedding matches existing students (duplicate detection)
        Using FAISS for fast similarity search
        Returns: duplicate info or None if new face
        """
        try:
            if len(self.student_registry) == 0:
                logger.info("📊 No existing embeddings in database")
                return None

            # Convert to numpy
            query_embedding = np.array([embedding]).astype('float32')

            # Search FAISS index
            distances, indices = self.faiss_index.search(query_embedding, k=5)

            # distances are L2 distances, convert to similarity
            # Lower distance = more similar
            # Convert to cosine similarity: 1 - (distance / 2)
            similarities = 1 - (distances[0] / 2)

            logger.info(f"🔍 Top 5 similarities: {similarities[:5]}")

            # Check if any match exceeds threshold
            for idx, similarity in zip(indices[0], similarities):
                if similarity >= threshold:
                    matched_student = list(self.student_registry.keys())[idx]
                    logger.warning(f"⚠️ DUPLICATE DETECTED: {matched_student} (similarity: {similarity:.3f})")
                    return {
                        'is_duplicate': True,
                        'matched_student': matched_student,
                        'similarity': float(similarity),
                        'threshold': threshold
                    }

            logger.info("✅ No duplicate found")
            return None

        except Exception as e:
            logger.error(f"❌ Duplicate check error: {e}")
            return None

    def register_student(self, student_id: str, embedding: list):
        """Register new student embedding"""
        try:
            self.student_registry[student_id] = embedding
            embedding_array = np.array([embedding]).astype('float32')
            self.faiss_index.add(embedding_array)
            logger.info(f"✅ Student registered: {student_id}")
        except Exception as e:
            logger.error(f"❌ Registration error: {e}")

# Initialize models
model_manager = FaceModelManager()

# ============================================================================
# API ENDPOINTS
# ============================================================================

@app.route('/health', methods=['GET'])
def health():
    """Health check"""
    return jsonify({
        'status': 'healthy',
        'service': 'Face Recognition API',
        'models': ['InsightFace', 'MiniFASNet', 'FAISS']
    })

@app.route('/api/v1/extract-embedding', methods=['POST'])
def extract_embedding_endpoint():
    """
    Extract face embedding from photo

    Request:
        - photo: base64 encoded image or binary

    Response:
        - embedding: 512-dimensional vector
        - success: bool
    """
    try:
        if 'photo' not in request.files and 'photo_base64' not in request.form:
            return jsonify({'error': 'No photo provided'}), 400

        # Get photo bytes
        if 'photo' in request.files:
            photo_bytes = request.files['photo'].read()
        else:
            photo_base64 = request.form['photo_base64']
            photo_bytes = base64.b64decode(photo_base64)

        # Extract embedding
        embedding = model_manager.extract_embedding(photo_bytes)

        if embedding is None:
            return jsonify({
                'success': False,
                'error': 'No face detected or extraction failed'
            }), 400

        return jsonify({
            'success': True,
            'embedding': embedding,
            'embedding_dim': len(embedding)
        })

    except Exception as e:
        logger.error(f"❌ API Error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/check-liveness', methods=['POST'])
def check_liveness_endpoint():
    """
    Check if face is real (liveness detection)

    Request:
        - photo: base64 encoded image or binary

    Response:
        - is_real: bool
        - liveness_score: float (0-1)
        - confidence: float (0-1)
    """
    try:
        if 'photo' not in request.files and 'photo_base64' not in request.form:
            return jsonify({'error': 'No photo provided'}), 400

        # Get photo bytes
        if 'photo' in request.files:
            photo_bytes = request.files['photo'].read()
        else:
            photo_base64 = request.form['photo_base64']
            photo_bytes = base64.b64decode(photo_base64)

        # Check liveness
        result = model_manager.check_liveness(photo_bytes)

        return jsonify({
            'success': True,
            **result
        })

    except Exception as e:
        logger.error(f"❌ API Error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/check-duplicate', methods=['POST'])
def check_duplicate_endpoint():
    """
    Check if embedding already exists (duplicate detection)

    Request:
        - embedding: list of 512 floats
        - student_id: optional, to exclude from check
        - threshold: optional, default 0.60

    Response:
        - is_duplicate: bool
        - matched_student: if duplicate
        - similarity: if duplicate
    """
    try:
        data = request.get_json()

        if 'embedding' not in data:
            return jsonify({'error': 'No embedding provided'}), 400

        embedding = data['embedding']
        student_id = data.get('student_id')
        threshold = data.get('threshold', 0.60)

        # Check duplicate
        result = model_manager.check_duplicate(embedding, student_id, threshold)

        return jsonify({
            'success': True,
            'is_duplicate': result is not None,
            'duplicate_info': result
        })

    except Exception as e:
        logger.error(f"❌ API Error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/register-student', methods=['POST'])
def register_student_endpoint():
    """
    Register a new student's embedding

    Request:
        - student_id: string
        - embedding: list of 512 floats

    Response:
        - success: bool
    """
    try:
        data = request.get_json()

        if 'student_id' not in data or 'embedding' not in data:
            return jsonify({'error': 'Missing student_id or embedding'}), 400

        student_id = data['student_id']
        embedding = data['embedding']

        # Register
        model_manager.register_student(student_id, embedding)

        return jsonify({
            'success': True,
            'student_id': student_id,
            'message': f'Student {student_id} registered'
        })

    except Exception as e:
        logger.error(f"❌ API Error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/match-faces', methods=['POST'])
def match_faces_endpoint():
    """
    Compare two embeddings for attendance matching

    Request:
        - embedding1: registration embedding
        - embedding2: attendance/face-match embedding
        - threshold: optional, default 0.50

    Response:
        - is_match: bool
        - similarity: float (0-1)
    """
    try:
        data = request.get_json()

        if 'embedding1' not in data or 'embedding2' not in data:
            return jsonify({'error': 'Missing embeddings'}), 400

        embedding1 = np.array(data['embedding1']).astype('float32')
        embedding2 = np.array(data['embedding2']).astype('float32')
        threshold = data.get('threshold', 0.50)

        # Normalize
        embedding1 = embedding1 / np.linalg.norm(embedding1)
        embedding2 = embedding2 / np.linalg.norm(embedding2)

        # Cosine similarity
        similarity = np.dot(embedding1, embedding2)
        is_match = similarity >= threshold

        logger.info(f"🔍 Match comparison: {similarity:.3f} - {'MATCH' if is_match else 'NO MATCH'}")

        return jsonify({
            'success': True,
            'is_match': is_match,
            'similarity': float(similarity),
            'threshold': threshold
        })

    except Exception as e:
        logger.error(f"❌ API Error: {e}")
        return jsonify({'error': str(e)}), 500

# ============================================================================
# ERROR HANDLERS
# ============================================================================

@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Endpoint not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({'error': 'Internal server error'}), 500

if __name__ == '__main__':
    logger.info("🚀 Starting Face Recognition API Server...")
    app.run(host='0.0.0.0', port=5000, debug=False)

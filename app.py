"""
FastAPI server for InsightFace face recognition.
Runs on Oracle Cloud Always Free with 24GB RAM.
"""

from fastapi import FastAPI, File, UploadFile, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import cv2
import numpy as np
import insightface
from pathlib import Path
import json
import logging
from typing import List, Dict, Tuple
import time
from datetime import datetime
import uvicorn

# Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="InsightFace Recognition Server")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global face recognition model
face_detector = None
face_recognizer = None
face_database = {}  # {person_id: [embeddings]}
db_path = Path("face_database.json")

DETECTION_THRESHOLD = 0.5
RECOGNITION_THRESHOLD = 0.6


def load_models():
    """Load InsightFace buffalo_l model (2GB)."""
    global face_detector, face_recognizer
    logger.info("Loading InsightFace buffalo_l model...")

    # buffalo_l is the recommended production model
    face_detector = insightface.app.FaceAnalysis(
        name='buffalo_l',
        providers=['CUDAExecutionProvider', 'CPUExecutionProvider']
    )
    face_detector.prepare(ctx_id=0, det_thresh=DETECTION_THRESHOLD)

    logger.info("Model loaded successfully")
    return face_detector


def load_database():
    """Load face embeddings from disk."""
    global face_database
    if db_path.exists():
        with open(db_path, 'r') as f:
            data = json.load(f)
            # Convert lists back to numpy arrays
            face_database = {
                person_id: [np.array(emb) for emb in embeddings]
                for person_id, embeddings in data.items()
            }
        logger.info(f"Loaded {len(face_database)} people from database")
    else:
        face_database = {}


def save_database():
    """Save face embeddings to disk."""
    data = {
        person_id: [emb.tolist() for emb in embeddings]
        for person_id, embeddings in face_database.items()
    }
    with open(db_path, 'w') as f:
        json.dump(data, f)


def extract_face_embedding(image_array: np.ndarray) -> Tuple[List[Dict], List[np.ndarray]]:
    """
    Extract face detections and embeddings from image.
    Returns: (faces_list, embeddings_list)
    """
    if face_detector is None:
        raise RuntimeError("Models not loaded")

    faces = face_detector.get(image_array)
    embeddings = [face.embedding for face in faces]

    faces_data = [
        {
            "bbox": face.bbox.tolist() if hasattr(face.bbox, 'tolist') else list(face.bbox),
            "confidence": float(face.det_score),
            "age": int(face.age) if hasattr(face, 'age') else None,
            "gender": face.gender if hasattr(face, 'gender') else None,
        }
        for face in faces
    ]

    return faces_data, embeddings


def find_matching_face(embedding: np.ndarray, threshold: float = RECOGNITION_THRESHOLD) -> Tuple[str, float]:
    """
    Find matching face in database.
    Returns: (person_id, similarity_score)
    """
    best_match = None
    best_score = 0

    for person_id, embeddings_list in face_database.items():
        for stored_emb in embeddings_list:
            # Cosine similarity
            similarity = np.dot(embedding, stored_emb) / (
                np.linalg.norm(embedding) * np.linalg.norm(stored_emb)
            )

            if similarity > best_score:
                best_score = similarity
                best_match = person_id

    if best_score >= threshold:
        return best_match, float(best_score)

    return None, best_score


@app.on_event("startup")
async def startup():
    """Load models on startup."""
    try:
        load_models()
        load_database()
        logger.info("Server startup complete")
    except Exception as e:
        logger.error(f"Startup error: {e}")
        raise


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {
        "status": "ok",
        "model_loaded": face_detector is not None,
        "people_in_db": len(face_database),
        "timestamp": datetime.now().isoformat()
    }


@app.post("/detect")
async def detect_faces(file: UploadFile = File(...)):
    """
    Detect faces in uploaded image.
    Returns: list of detections with bounding boxes and confidence scores.
    """
    try:
        contents = await file.read()
        nparr = np.frombuffer(contents, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if image is None:
            raise HTTPException(status_code=400, detail="Invalid image")

        faces_data, _ = extract_face_embedding(image)

        return {
            "faces_detected": len(faces_data),
            "faces": faces_data,
            "image_shape": list(image.shape)
        }

    except Exception as e:
        logger.error(f"Detection error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/recognize")
async def recognize_faces(file: UploadFile = File(...)):
    """
    Recognize faces in uploaded image against database.
    Returns: detections with person IDs and similarity scores.
    """
    try:
        contents = await file.read()
        nparr = np.frombuffer(contents, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if image is None:
            raise HTTPException(status_code=400, detail="Invalid image")

        faces_data, embeddings = extract_face_embedding(image)

        results = []
        for face_data, embedding in zip(faces_data, embeddings):
            person_id, similarity = find_matching_face(embedding)

            results.append({
                **face_data,
                "matched_person": person_id,
                "similarity": similarity
            })

        return {
            "faces_detected": len(results),
            "results": results
        }

    except Exception as e:
        logger.error(f"Recognition error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/register")
async def register_face(person_id: str, file: UploadFile = File(...)):
    """
    Register a face to database.
    Extracts embedding from image and stores it.
    """
    try:
        contents = await file.read()
        nparr = np.frombuffer(contents, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if image is None:
            raise HTTPException(status_code=400, detail="Invalid image")

        faces_data, embeddings = extract_face_embedding(image)

        if len(embeddings) == 0:
            raise HTTPException(status_code=400, detail="No face detected in image")

        if len(embeddings) > 1:
            raise HTTPException(status_code=400, detail="Multiple faces detected. Only one allowed per registration")

        # Use first (only) face
        embedding = embeddings[0]

        # Add to database
        if person_id not in face_database:
            face_database[person_id] = []

        face_database[person_id].append(embedding)
        save_database()

        return {
            "status": "registered",
            "person_id": person_id,
            "embeddings_count": len(face_database[person_id]),
            "total_people": len(face_database)
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Registration error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/database")
async def get_database_info():
    """Get database statistics."""
    stats = {
        "total_people": len(face_database),
        "people": {
            person_id: len(embeddings)
            for person_id, embeddings in face_database.items()
        }
    }
    return stats


@app.delete("/database/{person_id}")
async def delete_person(person_id: str):
    """Delete person from database."""
    if person_id not in face_database:
        raise HTTPException(status_code=404, detail="Person not found")

    del face_database[person_id]
    save_database()

    return {"status": "deleted", "person_id": person_id}


@app.post("/batch-recognize")
async def batch_recognize(file: UploadFile = File(...)):
    """
    Recognize multiple faces with detailed results.
    Useful for attendance systems.
    """
    try:
        contents = await file.read()
        nparr = np.frombuffer(contents, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if image is None:
            raise HTTPException(status_code=400, detail="Invalid image")

        faces_data, embeddings = extract_face_embedding(image)

        results = {
            "timestamp": datetime.now().isoformat(),
            "faces_detected": len(embeddings),
            "detections": []
        }

        for idx, (face_data, embedding) in enumerate(zip(faces_data, embeddings)):
            person_id, similarity = find_matching_face(embedding)

            results["detections"].append({
                "face_id": idx,
                **face_data,
                "matched_person": person_id,
                "similarity": float(similarity),
                "matched": person_id is not None
            })

        return results

    except Exception as e:
        logger.error(f"Batch recognition error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8000,
        workers=1  # Single worker for memory efficiency
    )

"""
Streamlit UI for InsightFace face recognition.
Deploy directly on Hugging Face Spaces.
"""

import streamlit as st
import cv2
import numpy as np
import insightface
from PIL import Image
import json
from pathlib import Path
from typing import Dict, List, Tuple
import pandas as pd
from datetime import datetime

# Page config
st.set_page_config(
    page_title="InsightFace Recognition",
    page_icon="👤",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Styling
st.markdown("""
    <style>
    .success { color: #00CC00; }
    .error { color: #FF0000; }
    .info { color: #0099FF; }
    </style>
""", unsafe_allow_html=True)

# Global state
if 'face_detector' not in st.session_state:
    st.session_state.face_detector = None
if 'face_database' not in st.session_state:
    st.session_state.face_database = {}

DB_PATH = "face_database.json"
DETECTION_THRESHOLD = 0.5
RECOGNITION_THRESHOLD = 0.6


@st.cache_resource
def load_model():
    """Load InsightFace model once"""
    with st.spinner("Loading face recognition model (buffalo_l)..."):
        face_detector = insightface.app.FaceAnalysis(
            name='buffalo_l',
            providers=['CPUExecutionProvider']
        )
        face_detector.prepare(ctx_id=0, det_thresh=DETECTION_THRESHOLD)
    return face_detector


def load_database():
    """Load face database from disk"""
    if Path(DB_PATH).exists():
        with open(DB_PATH, 'r') as f:
            data = json.load(f)
            return {
                person_id: [np.array(emb) for emb in embeddings]
                for person_id, embeddings in data.items()
            }
    return {}


def save_database(database):
    """Save database to disk"""
    data = {
        person_id: [emb.tolist() for emb in embeddings]
        for person_id, embeddings in database.items()
    }
    with open(DB_PATH, 'w') as f:
        json.dump(data, f)


def extract_faces(image_array: np.ndarray) -> Tuple[List[Dict], List[np.ndarray]]:
    """Extract faces and embeddings from image"""
    detector = load_model()
    faces = detector.get(image_array)

    embeddings = [face.embedding for face in faces]
    faces_data = [
        {
            "bbox": face.bbox.astype(int).tolist() if hasattr(face.bbox, 'astype') else list(face.bbox),
            "confidence": float(face.det_score),
            "age": int(face.age) if hasattr(face, 'age') else None,
            "gender": face.gender if hasattr(face, 'gender') else None,
        }
        for face in faces
    ]

    return faces_data, embeddings


def find_match(embedding: np.ndarray, database: Dict, threshold=RECOGNITION_THRESHOLD) -> Tuple[str, float]:
    """Find matching face in database"""
    best_match = None
    best_score = 0

    for person_id, embeddings_list in database.items():
        for stored_emb in embeddings_list:
            similarity = np.dot(embedding, stored_emb) / (
                np.linalg.norm(embedding) * np.linalg.norm(stored_emb)
            )
            if similarity > best_score:
                best_score = similarity
                best_match = person_id

    if best_score >= threshold:
        return best_match, float(best_score)

    return None, best_score


def draw_boxes(image: np.ndarray, faces_data: List[Dict], matches: List[Dict] = None) -> Image.Image:
    """Draw bounding boxes on image"""
    image_copy = image.copy()

    for idx, face_data in enumerate(faces_data):
        bbox = face_data['bbox']
        x1, y1, x2, y2 = int(bbox[0]), int(bbox[1]), int(bbox[2]), int(bbox[3])
        confidence = face_data['confidence']

        # Color based on match
        if matches and matches[idx]['matched']:
            color = (0, 255, 0)  # Green = matched
            label = f"{matches[idx]['matched_person']} ({matches[idx]['similarity']:.2f})"
        else:
            color = (0, 165, 255)  # Orange = unknown
            label = f"Unknown ({matches[idx]['similarity']:.2f})" if matches else "Face"

        # Draw box
        cv2.rectangle(image_copy, (x1, y1), (x2, y2), color, 2)

        # Put label
        cv2.putText(
            image_copy, label,
            (x1, y1 - 10),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5, color, 2
        )

    return Image.fromarray(cv2.cvtColor(image_copy, cv2.COLOR_BGR2RGB))


# Main app
st.title("👤 InsightFace Recognition System")
st.markdown("---")

# Sidebar
with st.sidebar:
    st.header("⚙️ Settings")
    mode = st.radio(
        "Select Mode",
        ["🔍 Detect Faces", "🎯 Recognize Faces", "📝 Register Face", "📊 Database Manager", "✓ Attendance"]
    )
    st.markdown("---")

    st.subheader("Model Info")
    col1, col2 = st.columns(2)
    st.session_state.face_database = load_database()

    with col1:
        st.metric("People in DB", len(st.session_state.face_database))
    with col2:
        total_faces = sum(len(e) for e in st.session_state.face_database.values())
        st.metric("Total Faces", total_faces)


# Mode: Detect Faces
if mode == "🔍 Detect Faces":
    st.header("Detect Faces in Image")

    uploaded_file = st.file_uploader("Upload image", type=['jpg', 'jpeg', 'png'])

    if uploaded_file:
        image = Image.open(uploaded_file)
        image_array = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)

        with st.spinner("Detecting faces..."):
            faces_data, _ = extract_faces(image_array)

        col1, col2 = st.columns([1, 1])

        with col1:
            st.subheader("Original Image")
            st.image(image)

        with col2:
            st.subheader("Detection Results")
            st.success(f"✓ Found {len(faces_data)} face(s)")

            if faces_data:
                annotated = draw_boxes(image_array, faces_data)
                st.image(annotated, caption="Detected Faces")

                st.subheader("Details")
                for i, face in enumerate(faces_data):
                    with st.expander(f"Face {i+1}"):
                        col_a, col_b = st.columns(2)
                        with col_a:
                            st.write(f"**Confidence:** {face['confidence']:.2%}")
                            st.write(f"**Age:** {face['age']}")
                        with col_b:
                            st.write(f"**Gender:** {face['gender']}")


# Mode: Recognize Faces
elif mode == "🎯 Recognize Faces":
    st.header("Recognize Faces Against Database")

    if len(st.session_state.face_database) == 0:
        st.warning("⚠️ Database is empty. Register faces first!")
    else:
        uploaded_file = st.file_uploader("Upload image", type=['jpg', 'jpeg', 'png'])

        if uploaded_file:
            image = Image.open(uploaded_file)
            image_array = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)

            with st.spinner("Recognizing faces..."):
                faces_data, embeddings = extract_faces(image_array)

                results = []
                for face_data, embedding in zip(faces_data, embeddings):
                    person_id, similarity = find_match(embedding, st.session_state.face_database)
                    results.append({
                        'face_data': face_data,
                        'matched_person': person_id,
                        'similarity': similarity,
                        'matched': person_id is not None
                    })

            col1, col2 = st.columns([1, 1])

            with col1:
                st.subheader("Image with Results")
                annotated = draw_boxes(image_array, [r['face_data'] for r in results], results)
                st.image(annotated)

            with col2:
                st.subheader("Recognition Results")

                matched = [r for r in results if r['matched']]
                unmatched = [r for r in results if not r['matched']]

                st.info(f"✓ Matched: {len(matched)}")
                st.warning(f"? Unknown: {len(unmatched)}")

                if matched:
                    st.subheader("Matched Faces")
                    for r in matched:
                        col_x, col_y = st.columns([2, 1])
                        with col_x:
                            st.write(f"**{r['matched_person']}**")
                        with col_y:
                            st.metric("Similarity", f"{r['similarity']:.2%}")

                if unmatched:
                    st.subheader("Unknown Faces")
                    for i, r in enumerate(unmatched):
                        st.write(f"Face {i+1}: {r['similarity']:.2%} similarity (not registered)")


# Mode: Register Face
elif mode == "📝 Register Face":
    st.header("Register Face to Database")

    col1, col2 = st.columns([1, 1])

    with col1:
        person_id = st.text_input("Person ID (e.g., student_001):", placeholder="student_001")
    with col2:
        uploaded_file = st.file_uploader("Upload face photo", type=['jpg', 'jpeg', 'png'])

    if st.button("Register", type="primary", use_container_width=True):
        if not person_id:
            st.error("❌ Please enter Person ID")
        elif not uploaded_file:
            st.error("❌ Please upload an image")
        else:
            image = Image.open(uploaded_file)
            image_array = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)

            with st.spinner("Processing..."):
                faces_data, embeddings = extract_faces(image_array)

            if len(embeddings) == 0:
                st.error("❌ No face detected in image")
            elif len(embeddings) > 1:
                st.error("❌ Multiple faces detected. Please use image with single face.")
            else:
                embedding = embeddings[0]

                if person_id not in st.session_state.face_database:
                    st.session_state.face_database[person_id] = []

                st.session_state.face_database[person_id].append(embedding)
                save_database(st.session_state.face_database)

                st.success(f"✓ Registered {person_id}!")
                st.balloons()
                st.write(f"Total embeddings: {len(st.session_state.face_database[person_id])}")


# Mode: Database Manager
elif mode == "📊 Database Manager":
    st.header("Database Management")

    if len(st.session_state.face_database) == 0:
        st.info("Database is empty")
    else:
        # Display statistics
        col1, col2, col3 = st.columns(3)
        with col1:
            st.metric("Total People", len(st.session_state.face_database))
        with col2:
            total_faces = sum(len(e) for e in st.session_state.face_database.values())
            st.metric("Total Faces", total_faces)
        with col3:
            avg_faces = total_faces / len(st.session_state.face_database)
            st.metric("Avg per Person", f"{avg_faces:.1f}")

        st.markdown("---")

        # Display database
        st.subheader("People in Database")
        db_data = [
            {"Person ID": pid, "Face Count": len(embeddings)}
            for pid, embeddings in st.session_state.face_database.items()
        ]
        st.dataframe(pd.DataFrame(db_data), use_container_width=True)

        st.markdown("---")

        # Delete person
        st.subheader("Delete Person")
        person_to_delete = st.selectbox(
            "Select person to delete:",
            list(st.session_state.face_database.keys())
        )

        if st.button("Delete", type="secondary"):
            del st.session_state.face_database[person_to_delete]
            save_database(st.session_state.face_database)
            st.success(f"✓ Deleted {person_to_delete}")
            st.rerun()

        st.markdown("---")

        # Download/backup
        st.subheader("Backup Database")
        db_json = json.dumps({
            person_id: [emb.tolist() for emb in embeddings]
            for person_id, embeddings in st.session_state.face_database.items()
        }, indent=2)

        st.download_button(
            label="Download Database",
            data=db_json,
            file_name=f"face_database_{datetime.now().strftime('%Y%m%d')}.json",
            mime="application/json"
        )


# Mode: Attendance
elif mode == "✓ Attendance":
    st.header("Attendance Marking")

    if len(st.session_state.face_database) == 0:
        st.warning("⚠️ Database is empty. Register students first!")
    else:
        uploaded_file = st.file_uploader("Upload classroom photo", type=['jpg', 'jpeg', 'png'])

        if uploaded_file:
            image = Image.open(uploaded_file)
            image_array = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)

            with st.spinner("Processing attendance..."):
                faces_data, embeddings = extract_faces(image_array)

                results = []
                for face_data, embedding in zip(faces_data, embeddings):
                    person_id, similarity = find_match(embedding, st.session_state.face_database)
                    results.append({
                        'face_data': face_data,
                        'matched_person': person_id,
                        'similarity': similarity,
                        'matched': person_id is not None
                    })

            col1, col2 = st.columns([1, 1])

            with col1:
                st.subheader("Processed Image")
                annotated = draw_boxes(image_array, [r['face_data'] for r in results], results)
                st.image(annotated)

            with col2:
                st.subheader("Attendance Report")

                present = [r for r in results if r['matched']]
                absent = list(st.session_state.face_database.keys())

                for person in present:
                    absent.remove(person['matched_person'])

                col_p, col_a = st.columns(2)
                with col_p:
                    st.success(f"✓ Present: {len(present)}")
                with col_a:
                    st.error(f"✗ Absent: {len(absent)}")

                st.markdown("---")

                st.subheader("Present Students")
                for person in present:
                    st.write(f"✓ {person['matched_person']} ({person['similarity']:.1%})")

                if absent:
                    st.subheader("Absent Students")
                    for student in absent:
                        st.write(f"✗ {student}")

                # Save attendance
                attendance_report = {
                    'timestamp': datetime.now().isoformat(),
                    'present': [p['matched_person'] for p in present],
                    'absent': absent,
                    'total': len(st.session_state.face_database)
                }

                st.download_button(
                    label="Download Attendance Report",
                    data=json.dumps(attendance_report, indent=2),
                    file_name=f"attendance_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json",
                    mime="application/json"
                )

st.markdown("---")
st.caption("InsightFace Recognition System | Powered by Streamlit")

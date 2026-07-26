"""
Example client for InsightFace API.
Integrate this with your attendance system.
"""

import requests
import json
from pathlib import Path
from typing import Dict, List, Optional, Tuple


class InsightFaceApiClient:
    """Client for InsightFace recognition API"""

    def __init__(self, api_url: str = "http://localhost:8000"):
        """
        Initialize client.

        Args:
            api_url: Base URL of InsightFace API (e.g., http://YOUR_ORACLE_VM_IP:8000)
        """
        self.api_url = api_url.rstrip('/')
        self.session = requests.Session()
        self._verify_connection()

    def _verify_connection(self) -> None:
        """Verify API is accessible"""
        try:
            response = self.session.get(f"{self.api_url}/health", timeout=5)
            response.raise_for_status()
            print(f"✓ Connected to API at {self.api_url}")
        except Exception as e:
            raise ConnectionError(f"Cannot connect to API at {self.api_url}: {e}")

    def detect_faces(self, image_path: str) -> Dict:
        """
        Detect faces in image.

        Args:
            image_path: Path to image file

        Returns:
            {
                'faces_detected': int,
                'faces': [{'bbox': [...], 'confidence': float, 'age': int, 'gender': str}],
                'image_shape': [height, width, channels]
            }
        """
        with open(image_path, 'rb') as f:
            response = self.session.post(
                f"{self.api_url}/detect",
                files={'file': f}
            )
        response.raise_for_status()
        return response.json()

    def recognize_faces(self, image_path: str) -> Dict:
        """
        Recognize faces against database.

        Args:
            image_path: Path to image file

        Returns:
            {
                'faces_detected': int,
                'results': [{
                    'bbox': [...],
                    'confidence': float,
                    'matched_person': str or None,
                    'similarity': float
                }]
            }
        """
        with open(image_path, 'rb') as f:
            response = self.session.post(
                f"{self.api_url}/recognize",
                files={'file': f}
            )
        response.raise_for_status()
        return response.json()

    def batch_recognize(self, image_path: str) -> Dict:
        """
        Recognize multiple faces with detailed results (for attendance).

        Args:
            image_path: Path to image file

        Returns:
            {
                'timestamp': str,
                'faces_detected': int,
                'detections': [{
                    'face_id': int,
                    'bbox': [...],
                    'confidence': float,
                    'matched_person': str or None,
                    'similarity': float,
                    'matched': bool
                }]
            }
        """
        with open(image_path, 'rb') as f:
            response = self.session.post(
                f"{self.api_url}/batch-recognize",
                files={'file': f}
            )
        response.raise_for_status()
        return response.json()

    def register_face(self, person_id: str, image_path: str) -> Dict:
        """
        Register face to database.
        Can call multiple times with different photos of same person
        to improve recognition accuracy.

        Args:
            person_id: Unique ID for person (e.g., "student_001")
            image_path: Path to image file

        Returns:
            {
                'status': 'registered',
                'person_id': str,
                'embeddings_count': int,
                'total_people': int
            }
        """
        with open(image_path, 'rb') as f:
            response = self.session.post(
                f"{self.api_url}/register",
                params={'person_id': person_id},
                files={'file': f}
            )
        response.raise_for_status()
        return response.json()

    def get_database_info(self) -> Dict:
        """
        Get database statistics.

        Returns:
            {
                'total_people': int,
                'people': {'person_id': embedding_count, ...}
            }
        """
        response = self.session.get(f"{self.api_url}/database")
        response.raise_for_status()
        return response.json()

    def delete_person(self, person_id: str) -> Dict:
        """Delete person from database"""
        response = self.session.delete(f"{self.api_url}/database/{person_id}")
        response.raise_for_status()
        return response.json()

    def get_health(self) -> Dict:
        """Get server health status"""
        response = self.session.get(f"{self.api_url}/health")
        response.raise_for_status()
        return response.json()


# ===================== USAGE EXAMPLES =====================

def example_register_students():
    """Example: Register student faces"""
    client = InsightFaceApiClient("http://YOUR_ORACLE_VM_IP:8000")

    # Register multiple students
    students = {
        "student_001": "photos/john_doe.jpg",
        "student_002": "photos/jane_smith.jpg",
        "student_003": "photos/bob_johnson.jpg",
    }

    for student_id, photo_path in students.items():
        try:
            result = client.register_face(student_id, photo_path)
            print(f"✓ Registered {student_id}: {result['embeddings_count']} embedding(s)")
        except Exception as e:
            print(f"✗ Failed to register {student_id}: {e}")


def example_attendance_system():
    """Example: Attendance marking from classroom photo"""
    client = InsightFaceApiClient("http://YOUR_ORACLE_VM_IP:8000")

    # Scan classroom photo
    classroom_photo = "classroom_photo.jpg"
    result = client.batch_recognize(classroom_photo)

    print(f"\n=== Attendance Report ===")
    print(f"Timestamp: {result['timestamp']}")
    print(f"Faces detected: {result['faces_detected']}\n")

    present = []
    unknown = []

    for detection in result['detections']:
        if detection['matched']:
            present.append({
                'student_id': detection['matched_person'],
                'confidence': detection['confidence'],
                'similarity': detection['similarity']
            })
            print(f"✓ {detection['matched_person']} (similarity: {detection['similarity']:.2f})")
        else:
            unknown.append(detection)
            print(f"? Unknown face (similarity: {detection['similarity']:.2f})")

    # Save attendance
    attendance_report = {
        'timestamp': result['timestamp'],
        'present': present,
        'unknown_count': len(unknown),
        'total_faces': result['faces_detected']
    }

    with open('attendance.json', 'w') as f:
        json.dump(attendance_report, f, indent=2)

    print(f"\n✓ Attendance saved to attendance.json")


def example_face_detection():
    """Example: Just detect faces (no matching)"""
    client = InsightFaceApiClient("http://YOUR_ORACLE_VM_IP:8000")

    result = client.detect_faces("photo.jpg")
    print(f"\nDetected {result['faces_detected']} face(s)")

    for i, face in enumerate(result['faces']):
        print(f"\nFace {i+1}:")
        print(f"  Bounding box: {face['bbox']}")
        print(f"  Confidence: {face['confidence']:.2f}")
        print(f"  Age: {face['age']}")
        print(f"  Gender: {face['gender']}")


def example_database_management():
    """Example: Manage database"""
    client = InsightFaceApiClient("http://YOUR_ORACLE_VM_IP:8000")

    # Get stats
    info = client.get_database_info()
    print(f"\nDatabase contains {info['total_people']} people:")
    for person_id, count in info['people'].items():
        print(f"  {person_id}: {count} embedding(s)")

    # Delete someone
    # client.delete_person("student_001")
    # print("Deleted student_001")


def example_server_health():
    """Example: Check server status"""
    client = InsightFaceApiClient("http://YOUR_ORACLE_VM_IP:8000")

    health = client.get_health()
    print(f"Server Status:")
    print(f"  Status: {health['status']}")
    print(f"  Model loaded: {health['model_loaded']}")
    print(f"  People in DB: {health['people_in_db']}")


if __name__ == "__main__":
    # Run examples
    try:
        print("Testing InsightFace API Client\n")

        # Check server
        example_server_health()

        # Uncomment examples to run:
        # example_register_students()
        # example_face_detection()
        # example_attendance_system()
        # example_database_management()

    except Exception as e:
        print(f"Error: {e}")

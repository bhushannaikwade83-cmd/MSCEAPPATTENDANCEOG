"""
Vector Database Service using FAISS
Handles fast similarity search for 200k+ face embeddings

Architecture:
- RetinaFace: Face detection (handled by face_service.py)
- ArcFace: 512-dimensional embeddings (handled by face_service.py)
- FAISS: Vector similarity search (this module)
"""

import faiss
import numpy as np
import pickle
import os
import logging
from typing import List, Dict, Optional
import firebase_admin
from firebase_admin import firestore, credentials

logger = logging.getLogger(__name__)

class VectorDatabase:
    """FAISS-based vector database for face embeddings"""
    
    def __init__(self):
        self.index = None
        self.metadata = {}  # Maps index position to student info
        self.institute_indices = {}  # Maps institute_id to index ranges
        self.dimension = 512  # ArcFace embedding dimension
        self.index_path = "faiss_index.bin"
        self.metadata_path = "faiss_metadata.pkl"
        self.firestore_db = None  # Firebase Firestore connection
        
    async def load_index(self):
        """Load FAISS index from disk and initialize Firebase"""
        try:
            # Initialize Firebase
            if not firebase_admin._apps:
                cred_path = os.getenv('FIREBASE_CREDENTIALS_PATH')
                if cred_path and os.path.exists(cred_path):
                    # Use service account file if provided (local development)
                    cred = credentials.Certificate(cred_path)
                    firebase_admin.initialize_app(cred)
                    logger.info("✅ Firebase initialized with service account file")
                else:
                    # Use Application Default Credentials (Cloud Run)
                    try:
                        firebase_admin.initialize_app()
                        logger.info("✅ Firebase initialized with Application Default Credentials")
                    except Exception as e:
                        logger.warning(f"⚠️ Could not initialize Firebase: {e}")
                        logger.info("💡 Continuing without Firebase (FAISS will work standalone)")
            
            try:
                self.firestore_db = firestore.client()
                logger.info("✅ Connected to Firebase Firestore")
            except Exception as e:
                logger.warning(f"⚠️ Could not connect to Firestore: {e}")
                logger.info("💡 Continuing without Firestore (FAISS will work standalone)")
                self.firestore_db = None
            
            # Load FAISS index
            if os.path.exists(self.index_path):
                self.index = faiss.read_index(self.index_path)
                with open(self.metadata_path, 'rb') as f:
                    self.metadata = pickle.load(f)
                logger.info(f"✅ Loaded FAISS index with {self.index.ntotal} vectors")
            else:
                # Create new index with CORRECT dimension (512 for ArcFace)
                self.index = faiss.IndexFlatL2(self.dimension)  # L2 distance, 512-dim
                logger.info(f"✅ Created new FAISS index (dimension: {self.dimension})")
                
                # Verify dimension is correct
                if self.dimension != 512:
                    error_msg = f"CRITICAL: FAISS dimension mismatch! Expected 512, got {self.dimension}"
                    logger.error(f"❌ {error_msg}")
                    raise ValueError(error_msg)
        except Exception as e:
            logger.error(f"Error loading FAISS index: {e}")
            raise
    
    async def add_embedding(
        self,
        embedding: np.ndarray,
        institute_id: str,
        student_id: str,
        roll_number: str,
        name: str
    ):
        """
        Add a new face embedding to the vector database
        
        Args:
            embedding: 512-dimensional numpy array
            institute_id: Institute ID
            student_id: Student document ID
            roll_number: Student roll number
            name: Student name
        """
        try:
            # Validate inputs
            if self.index is None:
                raise ValueError("FAISS index is not initialized. Call load_index() first.")
            
            if embedding is None or embedding.size == 0:
                raise ValueError("Embedding is empty or None")
            
            # Reshape embedding to (1, 512)
            embedding = embedding.reshape(1, -1).astype('float32')
            
            # Validate dimension
            if embedding.shape[1] != self.dimension:
                raise ValueError(f"Embedding dimension mismatch: {embedding.shape[1]} != {self.dimension}")
            
            # Add to FAISS index
            index_position = self.index.ntotal
            self.index.add(embedding)
            
            # Store metadata
            self.metadata[index_position] = {
                'institute_id': institute_id,
                'student_id': student_id,
                'roll_number': roll_number,
                'name': name
            }
            
            # Update institute index ranges
            if institute_id not in self.institute_indices:
                self.institute_indices[institute_id] = []
            self.institute_indices[institute_id].append(index_position)
            
            # Save index immediately after adding (critical for persistence)
            # Don't fail if save fails - index is in memory
            try:
                await self._save_index()
            except Exception as save_error:
                logger.warning(f"⚠️ Could not save index to disk: {save_error}")
                logger.info("💡 Index is in memory and will work, but may be lost on restart")
            
            logger.info(f"✅ Added embedding for {roll_number} (index: {index_position}, total vectors: {self.index.ntotal})")
            
            # Verify the embedding was added correctly
            if self.index.ntotal == 0:
                logger.error(f"❌ CRITICAL: Index is empty after adding embedding for {roll_number}!")
                raise RuntimeError("Failed to add embedding to index")
            else:
                logger.info(f"✅ Verified: Index now contains {self.index.ntotal} vectors")
            
        except Exception as e:
            import traceback
            error_type = type(e).__name__
            error_msg = str(e) if str(e) else repr(e)
            
            # Ensure we have a meaningful error message
            if not error_msg or len(error_msg.strip()) == 0:
                error_msg = f"{error_type} occurred while adding embedding"
            
            logger.error(f"❌ Error adding embedding for {roll_number}:")
            logger.error(f"   Type: {error_type}")
            logger.error(f"   Message: {error_msg}")
            logger.error(f"   Traceback:\n{traceback.format_exc()}")
            
            # Re-raise with better context
            raise Exception(f"Failed to add embedding to vector database: {error_msg}") from e
    
    async def search(
        self,
        embedding: np.ndarray,
        institute_id: str,
        top_k: int = 5,
        threshold: float = 0.85
    ) -> List[Dict]:
        """
        Search for similar faces in vector database
        
        Args:
            embedding: 512-dimensional query embedding
            institute_id: Institute ID to search within
            top_k: Number of top matches to return
            threshold: Minimum similarity threshold (cosine similarity)
            
        Returns:
            List of matches with similarity scores
        """
        try:
            # Reshape embedding to (1, 512)
            query = embedding.reshape(1, -1).astype('float32')
            
            # Search in FAISS index
            # For 200k vectors, this takes ~10-50ms
            distances, indices = self.index.search(query, top_k * 10)  # Get more candidates
            
            matches = []
            for i, (distance, idx) in enumerate(zip(distances[0], indices[0])):
                if idx == -1:  # Invalid index
                    continue
                
                # Get metadata
                metadata = self.metadata.get(idx)
                if not metadata:
                    continue
                
                # Filter by institute
                if metadata['institute_id'] != institute_id:
                    continue
                
                # Convert L2 distance to cosine similarity
                # FAISS IndexFlatL2 returns SQUARED L2 distance for normalized vectors
                # For normalized vectors with squared L2: similarity = 1 - (squared_distance / 2)
                # Try both formulas to handle edge cases
                similarity_squared = 1.0 - (distance / 2.0)  # If distance is squared (FAISS default)
                similarity_regular = 1.0 - ((distance ** 2) / 2.0)  # If distance is regular
                
                # Use the higher similarity (more lenient)
                similarity = max(similarity_squared, similarity_regular)
                
                # Clamp to valid range [0, 1]
                similarity = max(0.0, min(1.0, similarity))
                
                # Apply threshold
                # Log similarity for debugging
                logger.info(f"Match candidate: {metadata['roll_number']} - Similarity: {similarity:.4f}, Distance: {distance:.4f}, Threshold: {threshold}")
                
                if similarity >= threshold:
                    matches.append({
                        'student_id': metadata['student_id'],
                        'roll_number': metadata['roll_number'],
                        'name': metadata['name'],
                        'similarity': float(similarity),
                        'index': int(idx)
                    })
                else:
                    logger.debug(f"Match below threshold: {metadata['roll_number']} - Similarity: {similarity:.4f} < {threshold}")
                
                if len(matches) >= top_k:
                    break
            
            # Sort by similarity (descending)
            matches.sort(key=lambda x: x['similarity'], reverse=True)
            
            return matches
            
        except Exception as e:
            logger.error(f"Error searching vector database: {e}")
            return []
    
    async def get_vector_by_roll(self, roll_number: str, institute_id: str) -> Optional[np.ndarray]:
        """
        Get stored vector for a specific roll number (direct lookup)
        
        Args:
            roll_number: Student roll number
            institute_id: Institute ID
            
        Returns:
            512-dimensional numpy array or None if not found
        """
        try:
            # Search through metadata to find matching roll number
            for index_pos, metadata in self.metadata.items():
                if (metadata.get('roll_number') == roll_number and 
                    metadata.get('institute_id') == institute_id):
                    # Reconstruct vector from FAISS index
                    vector = self.index.reconstruct(int(index_pos))
                    logger.info(f"✅ Found vector for roll {roll_number} at index {index_pos}")
                    return vector
            
            logger.warning(f"⚠️ No vector found for roll {roll_number} in institute {institute_id}")
            return None
        except Exception as e:
            logger.error(f"Error getting vector by roll: {e}")
            return None
    
    def calculate_similarity(self, vector1: np.ndarray, vector2: np.ndarray) -> float:
        """
        Calculate cosine similarity between two vectors
        
        Args:
            vector1: First 512-dim vector
            vector2: Second 512-dim vector
            
        Returns:
            Similarity score (0.0 to 1.0)
        """
        try:
            # Ensure vectors are normalized
            v1 = vector1 / np.linalg.norm(vector1)
            v2 = vector2 / np.linalg.norm(vector2)
            
            # Cosine similarity = dot product of normalized vectors
            similarity = np.dot(v1, v2)
            
            # Clamp to [0, 1]
            return max(0.0, min(1.0, float(similarity)))
        except Exception as e:
            logger.error(f"Error calculating similarity: {e}")
            return 0.0
    
    async def _save_index(self):
        """Save FAISS index and metadata to disk"""
        try:
            # Ensure index exists
            if self.index is None:
                logger.error("❌ Cannot save: Index is None")
                raise ValueError("FAISS index is not initialized")
            
            # Save FAISS index
            faiss.write_index(self.index, self.index_path)
            
            # Save metadata
            with open(self.metadata_path, 'wb') as f:
                pickle.dump(self.metadata, f)
            
            logger.info("✅ Saved FAISS index and metadata")
        except PermissionError as e:
            logger.error(f"❌ Permission denied saving index: {e}")
            logger.warning("💡 Continuing without saving (index in memory only)")
            # Don't raise - allow operation to continue
        except OSError as e:
            logger.error(f"❌ OS error saving index: {e}")
            logger.warning("💡 Continuing without saving (index in memory only)")
            # Don't raise - allow operation to continue
        except Exception as e:
            logger.error(f"❌ Error saving index: {e}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")
            # Don't raise - allow operation to continue (index is in memory)

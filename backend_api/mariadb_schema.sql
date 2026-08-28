-- ============================================
-- MSCE Attendance System - MariaDB Schema
-- Replaces Supabase with self-hosted MariaDB
-- ============================================

-- Create database
CREATE DATABASE IF NOT EXISTS attendance CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE attendance;

-- ============================================
-- STUDENTS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS students (
    id VARCHAR(36) PRIMARY KEY COMMENT 'UUID',
    sr_no VARCHAR(50) NOT NULL COMMENT 'Student Roll Number',
    institute_id VARCHAR(50) NOT NULL COMMENT 'Institute ID',
    fname VARCHAR(100) NOT NULL COMMENT 'First Name',
    lname VARCHAR(100) COMMENT 'Last Name',
    mname VARCHAR(100) COMMENT 'Middle Name',

    -- Subjects (up to 8)
    sub1 VARCHAR(100),
    sub2 VARCHAR(100),
    sub3 VARCHAR(100),
    sub4 VARCHAR(100),
    sub5 VARCHAR(100),
    sub6 VARCHAR(100),
    sub7 VARCHAR(100),
    sub8 VARCHAR(100),

    -- Admin info
    form_serial_no VARCHAR(50),
    mother_nm VARCHAR(100),
    ctcd VARCHAR(50),
    identy_no VARCHAR(50),

    -- Face Recognition Data
    face_photo_url VARCHAR(500),
    face_embedding_front LONGBLOB COMMENT 'JSON array of 512 floats',
    face_embedding_left LONGBLOB COMMENT 'JSON array of 512 floats',
    face_embedding_right LONGBLOB COMMENT 'JSON array of 512 floats',
    face_registered_at TIMESTAMP NULL,
    face_registration_status VARCHAR(50) DEFAULT 'not_registered' COMMENT 'registered, not_registered, failed',
    is_face_real BOOLEAN DEFAULT FALSE,
    face_photo_change_count INT DEFAULT 0,
    face_photo_change_disabled BOOLEAN DEFAULT FALSE,

    -- Status
    status VARCHAR(50) DEFAULT 'active' COMMENT 'active, inactive, left',

    -- Timestamps
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    -- Indexes for fast queries (CRITICAL for performance)
    INDEX idx_institute_sr (institute_id, sr_no),
    INDEX idx_institute_status (institute_id, face_registration_status),
    INDEX idx_institute_active (institute_id, status),
    INDEX idx_registered (face_registration_status),
    UNIQUE KEY unique_institute_sr (institute_id, sr_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Student records with face recognition data';

-- ============================================
-- ATTENDANCE TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS attendance (
    id VARCHAR(36) PRIMARY KEY COMMENT 'UUID',
    sr_no VARCHAR(50) NOT NULL,
    institute_id VARCHAR(50) NOT NULL,
    record_type VARCHAR(20) NOT NULL COMMENT 'entry or exit',
    similarity DECIMAL(5, 4) COMMENT 'Face match confidence (0-1)',
    photo_url VARCHAR(500) COMMENT 'URL to captured photo',
    marked_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Indexes for fast queries
    INDEX idx_institute_date (institute_id, DATE(marked_time)),
    INDEX idx_institute_sr_date (institute_id, sr_no, DATE(marked_time)),
    INDEX idx_marked_time (marked_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Daily attendance records';

-- ============================================
-- INSTITUTES TABLE (optional, for reference)
-- ============================================
CREATE TABLE IF NOT EXISTS institutes (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    location VARCHAR(200),
    admin_name VARCHAR(100),
    admin_email VARCHAR(100),
    admin_phone VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Institute information';

-- ============================================
-- OPTIMIZE SETTINGS
-- ============================================

-- Set these in MySQL for better performance:
-- SET GLOBAL max_connections = 500;
-- SET GLOBAL max_allowed_packet = 256M;
-- SET GLOBAL query_cache_type = 1;
-- SET GLOBAL query_cache_size = 64M;

-- ============================================
-- SAMPLE DATA (for testing)
-- ============================================

-- Insert test institute
INSERT IGNORE INTO institutes (id, name, location, admin_name, admin_email)
VALUES ('99099', 'Test Institute', 'Mumbai', 'Admin Test', 'admin@test.com');

-- Insert test student (without face embeddings)
INSERT IGNORE INTO students (
    id, sr_no, institute_id, fname, lname,
    form_serial_no, status, face_registration_status
) VALUES (
    '12345678-1234-1234-1234-123456789012',
    'TEST001',
    '99099',
    'Test',
    'Student',
    '001',
    'active',
    'not_registered'
);

-- ============================================
-- VERIFY SETUP
-- ============================================

-- Run these to verify:
-- SELECT * FROM students WHERE institute_id = '99099';
-- SELECT * FROM attendance WHERE institute_id = '99099';
-- SHOW INDEXES FROM students;
-- SHOW INDEXES FROM attendance;

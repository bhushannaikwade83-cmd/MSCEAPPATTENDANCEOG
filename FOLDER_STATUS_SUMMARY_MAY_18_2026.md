# MSCE Attendance App - Folder Status Summary
**Date:** May 18, 2026  
**Branch:** main (up to date with origin/main)

---

## 📊 Project Overview

This is a **Flutter/Dart cross-platform attendance application** for MSCE (Multi-institute Student Biometric Attendance System) with face recognition, GPS validation, and admin portals.

### Technology Stack
- **Frontend:** Flutter (Dart) - iOS, Android, Web, macOS, Linux, Windows
- **Backend:** Supabase (PostgreSQL) + Custom Python/Node APIs
- **Face Recognition:** TensorFlow Lite, MediaPipe, InsightFace API
- **Storage:** Firebase/B2 Cloud Storage
- **Email/SMS:** Brevo (formerly Sendinblue)

---

## 📁 Folder Structure Analysis

### Main Directories
```
├── lib/                     (187 Dart files - Flutter app code)
├── backend_api/             (Python/Node backend services)
├── face_api_backend/        (Face recognition API)
├── supabase/                (Database & migrations)
├── android/                 (Android native code)
├── ios/                     (iOS native code)
├── web/                     (Web platform)
├── windows/                 (Windows platform)
├── macos/                   (macOS platform)
├── linux/                   (Linux platform)
├── assets/                  (Images, fonts, resources)
├── database/                (Database schemas)
├── docs/                    (Documentation)
├── website/                 (Marketing website)
└── scripts/                 (75+ utility scripts)
```

---

## 🔧 Git Status Summary

### Modified Files (Core Application)
**Configuration Files:**
- `pubspec.yaml` - Flutter dependencies
- `pubspec.lock` - Dependency lock file
- `app_config.env` - App configuration
- `android/app/src/main/AndroidManifest.xml` - Android manifest

**Core Configuration:**
- `lib/config/admin_portal_url.dart`
- `lib/config/supabase_env.dart`

**Core Logic Files (Modified):**
- `lib/core/attendance_auto_close_policy.dart`
- `lib/core/face_matching_thresholds.dart`
- `lib/core/gps_attendance_constants.dart`
- `lib/core/student_face_embedding_utils.dart`
- `lib/core/time_parse.dart`
- `lib/core/root_navigator.dart`
- `lib/main.dart`

**Screen Files (Modified - 20+ screens):**
- `admin_home_screen.dart`
- `attendance_screen.dart`
- `attendance_reports_screen.dart`
- `student_management_screen.dart`
- `teacher_attendance_screen.dart`
- `simplified_attendance_screen.dart`
- `single_photo_face_registration_screen.dart`
- `video_face_registration_screen.dart`
- `login_screen.dart` & more...

**Service Files (Modified - 15+ services):**
- `face_recognition_service.dart`
- `auth_service.dart`
- `attendance_report_service.dart`
- `photo_verification_service.dart`
- `security_ops_service.dart`
- `anti_spoof_service.dart`
- `liveness_detection_service.dart`
- And 8+ more...

**Widget Files (Modified):**
- `face_scanner_widget.dart`
- `secure_network_image.dart`
- `session_monitor.dart`
- `modern_bottom_nav_bar.dart`
- `quick_stats_widget.dart`

### Deleted Files (Cleanup - 185+ files)
Most deleted files were **temporary documentation and SQL scripts** including:
- Installation guides (`INSTALLATION_*.md`)
- Debug guides (`DEBUGGING_*.md`, `TROUBLESHOOTING_*.md`)
- Feature guides (`FEATURE_*.md`)
- Implementation checklists
- SQL migration helpers
- Documentation files (135+ .md files deleted)

### Untracked/New Files (NEW - 40+ files)

**Dart Files:**
- `lib/core/attendance_hours_db_reader.dart`
- `lib/core/camera_lens_utils.dart`
- `lib/core/streaming_blink_detector.dart`
- `lib/models/date_range_filter.dart`
- `lib/presentation/screens/attendance_camera_screen.dart`
- `lib/presentation/screens/media_pipe_face_camera_screen.dart`
- `lib/presentation/screens/pin_setup_screen.dart`
- `lib/presentation/screens/instructions_window.dart`
- `lib/presentation/screens/institute_report_screen.dart`
- 12+ new service files (liveness, anti-spoof, depth analysis, etc.)
- 8+ new widget files

**Database Migrations (NEW):**
- `supabase/migrations/047_fix_profiles_institute_fk.sql`
- `supabase/migrations/048_fix_all_institute_fks.sql`
- `supabase/migrations/049-062_*.sql` (14+ migrations)
- Database cleanup & verification scripts

**Documentation & Reference:**
- `MSCE_Attendance_Security_Specification.docx`
- `FINAL_CHECKLIST_MAY_8_2026.txt`
- `FILES_LOCATION_REFERENCE_MAY_8_2026.txt`
- Flowchart diagrams (JPEG, PNG, SVG)
- Reference guides

---

## 📈 Code Statistics

| Category | Count |
|----------|-------|
| **Dart Files** | 187 |
| **SQL Files** | 110 |
| **Database Migrations** | 61 |
| **Python/Scripts** | 75+ |
| **Documentation Files** | 20+ |
| **Config Files** | 15+ |

---

## 🚀 Key Features & Status

### Implemented Features ✅
1. **Face Recognition System**
   - Single photo registration
   - Multi-angle registration
   - Video-based registration
   - Real-time face matching (45-55% similarity band)
   - Liveness detection (MediaPipe, ML Kit, TensorFlow Lite)

2. **Attendance Marking**
   - Entry/Exit photo capture
   - GPS validation (distance checking)
   - Time-based auto-close policy
   - Offline support
   - Batch attendance reports

3. **Security Features**
   - Anti-spoofing (moire patterns, screen reflection, photo-of-photo detection)
   - Biometric lock
   - PIN-based session management
   - Depth analysis
   - Liveness verification

4. **Admin Portal**
   - Institute management
   - Student management
   - Attendance reports with date filters
   - Admin registration & approval
   - Staff login & teacher attendance

5. **Multi-Platform Support**
   - Android & iOS (Mobile)
   - Web platform
   - macOS, Windows, Linux (Desktop)

---

## ⚠️ Recent Changes & Work In Progress

### Database Layer
- Fixed foreign key relationships (FK constraints)
- Added new institute validation
- Migration system (47+ migrations completed, 14+ new ones)
- Dummy test data setup
- Institute admin approval automation

### Application Layer
- **Camera System:** MediaPipe face camera implementation
- **Attendance Hours:** Database persistence for calculated hours
- **PIN Management:** Midnight logout policy, session manager
- **Face Verification:** Enhanced with liveness & anti-spoof
- **Report Filtering:** Date range selector widget
- **Distance Checking:** Visual overlay for GPS validation

### Configuration Changes
- Attendance auto-close policy adjustments
- Face matching threshold updates (45-55% band as noted)
- GPS constants for distance validation
- Admin portal URL configuration
- Supabase environment setup

---

## 🔍 Current Git State

**Branch:** main  
**Status:** Up to date with origin/main  
**Changes to Commit:** 185+ deletions, 60+ modifications, 40+ new files

### Outstanding Work
- [ ] Review & commit all modified files
- [ ] Add new migration files to version control
- [ ] Verify all new services work correctly
- [ ] Update documentation (some was deleted)
- [ ] Testing on all platforms (iOS, Android, Web, Desktop)
- [ ] Performance testing with new services

---

## 📋 Action Items

### Immediate (High Priority)
1. **Git Management**
   - Decide on 185 deleted documentation files (intentional cleanup?)
   - Commit modified core application files
   - Stage new database migrations

2. **Code Review**
   - Review new face detection services
   - Verify GPS distance checking logic
   - Test liveness detection on real devices

3. **Database**
   - Run new migrations on production DB
   - Verify foreign key relationships
   - Test institute admin auto-approval

### Testing
- [ ] Face registration (single, multi-angle, video)
- [ ] Attendance marking with GPS
- [ ] Anti-spoofing detection
- [ ] Liveness verification
- [ ] Report generation
- [ ] Cross-platform compatibility

### Documentation
- [ ] Update README with latest features
- [ ] Document new services & widgets
- [ ] Create API documentation
- [ ] Update installation guide

---

## 📞 Quick Reference

**Main Entry Point:** `lib/main.dart`  
**Database Config:** `lib/config/supabase_env.dart`  
**Face Service:** `lib/services/face_recognition_service.dart`  
**Attendance Logic:** `lib/services/inline_student_attendance_service.dart`  
**Security:** `lib/services/security_ops_service.dart`  

**Database Migrations:** `supabase/migrations/`  
**Backend API:** `backend_api/` & `face_api_backend/`  
**Scripts:** `scripts/` (75+ utility & maintenance scripts)

---

**Status:** Project is active with recent significant changes. Ready for testing and deployment.

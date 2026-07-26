# Flutter App Structure Breakdown

## lib/ Directory Organization

### 🔧 lib/config/ - Configuration Files
- `admin_portal_url.dart` - Admin dashboard URL configuration
- `supabase_env.dart` - Supabase client setup & credentials

### 📱 lib/core/ - Core Business Logic
**Attendance Logic:**
- `attendance_auto_close_policy.dart` - Automatic attendance closing
- `time_parse.dart` - Time parsing utilities
- `attendance_hours_db_reader.dart` - Reading hours from database

**Face Recognition:**
- `face_matching_thresholds.dart` - 45-55% similarity band configuration
- `student_face_embedding_utils.dart` - Face embedding calculations
- `streaming_blink_detector.dart` - Real-time blink detection
- `camera_lens_utils.dart` - Camera lens handling

**Location & GPS:**
- `gps_attendance_constants.dart` - GPS distance/accuracy settings

**Navigation:**
- `root_navigator.dart` - Navigation management

**Startup:**
- `main.dart` - App entry point

### 📊 lib/data/ - Data Layer
- Database models
- API responses
- Local storage management

### 🎨 lib/presentation/ - UI Layer

**Screens (30+ screens):**

*Admin Screens:*
- `admin_home_screen.dart` - Admin dashboard
- `institute_admin_registration_screen.dart` - Admin onboarding
- `institute_registration_screen.dart` - Institute setup
- `coder_dashboard_screen.dart` - Developer tools

*Attendance Screens:*
- `attendance_screen.dart` - Primary attendance marking
- `simplified_attendance_screen.dart` - Simple UI variant
- `attendance_camera_screen.dart` - Camera interface
- `media_pipe_face_camera_screen.dart` - MediaPipe detection
- `teacher_attendance_screen.dart` - Teacher view

*Registration Screens:*
- `single_photo_face_registration_screen.dart` - Single photo enrollment
- `multi_angle_face_registration_screen.dart` - Multiple angle enrollment
- `video_face_registration_screen.dart` - Video-based enrollment
- `student_face_registration_wrapper.dart` - Registration coordinator

*Report Screens:*
- `attendance_reports_screen.dart` - Attendance analytics
- `modern_attendance_report_screen.dart` - Modern UI reports
- `institute_report_screen.dart` - Institute-wide reports

*Management Screens:*
- `student_management_screen.dart` - Student CRUD
- `student_photos_screen.dart` - Photo gallery
- `institute_search_screen.dart` - Institute lookup
- `add_student_screen.dart` - Student enrollment

*Authentication:*
- `login_screen.dart` - User login
- `attendance_staff_login_screen.dart` - Staff login
- `biometric_lock_screen.dart` - Biometric unlock

*Other:*
- `app_permissions_screen.dart` - Permissions request
- `onboarding_screen.dart` - First-time setup
- `main_navigation_screen.dart` - Bottom navigation
- `pin_setup_screen.dart` - PIN configuration
- `instructions_window.dart` - Help/instructions

**Widgets (15+ reusable components):**
- `face_scanner_widget.dart` - Face detection UI
- `secure_network_image.dart` - Secure image loading
- `session_monitor.dart` - Session tracking
- `modern_bottom_nav_bar.dart` - Navigation bar
- `quick_stats_widget.dart` - Statistics display
- `date_range_selector.dart` - Date filtering
- `distance_check_overlay.dart` - GPS validation UI
- `manual_face_confirmation_dialog.dart` - Face approval dialog
- `google_search_bar.dart` - Search functionality
- `responsive_text_widget.dart` - Responsive typography
- `institute_report_table.dart` - Report display
- `student_report_table.dart` - Student report table

### 🔐 lib/services/ - Business Logic Services (30+ services)

**Face Recognition & Biometrics:**
- `face_recognition_service.dart` - Primary face matching
- `insightface_api_service.dart` - InsightFace API integration
- `liveness_detection_service.dart` - Liveness verification
- `ml_kit_liveness_service.dart` - ML Kit liveness
- `anti_spoof_service.dart` - Spoofing prevention
- `photo_of_photo_detection_service.dart` - Print attack detection
- `moire_pattern_detection_service.dart` - Moire pattern detection
- `screen_reflection_detection_service.dart` - Screen reflection detection
- `depth_analysis_service.dart` - 3D depth analysis

**Attendance:**
- `inline_student_attendance_service.dart` - Main attendance logic
- `attendance_report_service.dart` - Report generation
- `filtered_attendance_report_service.dart` - Filtered reports
- `stale_attendance_reconciliation_service.dart` - Data cleanup

**Authentication:**
- `auth_service.dart` - User authentication
- `pin_session_manager.dart` - PIN sessions
- `pin_midnight_logout_service.dart` - Auto logout at midnight

**Location & GPS:**
- `gps_fence_sample.dart` - GPS geofencing
- `distance_check_service.dart` - Distance validation
- `location_monitor_service.dart` - Location tracking

**Storage & Files:**
- `storage_service.dart` - File storage
- `b2b_storage_service.dart` - B2 cloud storage
- `photo_compression_service.dart` - Image compression
- `photo_verification_service.dart` - Photo validation
- `pdf_export_service.dart` - PDF generation

**System & Security:**
- `app_permissions_service.dart` - Permission handling
- `security_ops_service.dart` - Security operations
- `institute_status_service.dart` - Institute status
- `institute_notification_service.dart` - Notifications

**ML & AI:**
- `tflite_interpreter_native.dart` - TensorFlow Lite (native)
- `tflite_interpreter_stub.dart` - TensorFlow Lite (stub)

**Other:**
- `face_debug_service.dart` - Debugging face recognition
- `test_data_service.dart` - Test data generation
- `shared_stats_service.dart` - Statistics caching

### 🎯 lib/models/ - Data Models
- `date_range_filter.dart` - Date range filtering

### 🛠 lib/utils/ - Utility Functions
- Helper functions
- Formatters
- Validators

### 📚 lib/l10n/ - Localization
- Multi-language support
- Translation files

### 📦 lib/widgets/ - Deprecated/Legacy Widgets
(Most moved to presentation/widgets)

---

## File Statistics by Directory

| Directory | Count | Purpose |
|-----------|-------|---------|
| lib/config/ | 2 | Configuration setup |
| lib/core/ | 8 | Core business logic |
| lib/data/ | Multiple | Data models & APIs |
| lib/presentation/screens/ | 30+ | UI screens |
| lib/presentation/widgets/ | 12+ | Reusable UI components |
| lib/services/ | 30+ | Business logic services |
| lib/models/ | Multiple | Data structures |
| lib/utils/ | Multiple | Helper functions |
| lib/l10n/ | Multiple | Translations |
| **Total** | **187 Dart files** | Complete Flutter app |

---

## Dependency Management

- **pubspec.yaml** - Dependencies declaration
- **pubspec.lock** - Locked versions for reproducibility

### Key Dependencies
- `flutter` - UI framework
- `supabase_flutter` - Database & auth
- `firebase_storage` - File storage
- `google_ml_kit` - ML Kit integration
- `tflite_flutter` - TensorFlow Lite
- `mediapipe` - Face detection
- `geolocator` - GPS/location
- `pdf` - PDF generation
- `image` - Image processing

---

## Build Targets

- **Android** - android/
- **iOS** - ios/
- **Web** - web/
- **macOS** - macos/
- **Windows** - windows/
- **Linux** - linux/

All built from single source: **lib/main.dart**

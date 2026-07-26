/// Centralized validation service for input sanitization and validation
class ValidationService {
  // Email validation regex
  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  // Phone validation regex (Indian format)
  static final RegExp _phoneRegex = RegExp(r'^[6-9]\d{9}$');

  // Roll number validation (alphanumeric, max 20 chars)
  static final RegExp _rollNumberRegex = RegExp(r'^[A-Za-z0-9_-]{1,20}$');

  // Name validation (letters, spaces, dots, max 100 chars)
  static final RegExp _nameRegex = RegExp(r'^[a-zA-Z\s\.]{1,100}$');

  /// First / middle / last name on student registration (all required).
  static String? validateRequiredNamePart(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required';
    }
    final t = value.trim();
    if (t.length > 80) {
      return '$label is too long (max 80 characters)';
    }
    if (!_nameRegex.hasMatch(t)) {
      return '$label: use letters, spaces, or dots only';
    }
    return null;
  }

  // Institute ID validation (alphanumeric, max 50 chars)
  static final RegExp _instituteIdRegex = RegExp(r'^[A-Za-z0-9_-]{1,50}$');

  static String? validateEmail(String? email) {
    if (email == null || email.isEmpty) {
      return 'Email is required';
    }
    
    // Trim whitespace
    email = email.trim();
    
    if (email.length > 254) {
      return 'Email is too long (max 254 characters)';
    }
    
    if (!_emailRegex.hasMatch(email)) {
      return 'Please enter a valid email address';
    }
    
    return null;
  }

  /// Validate password strength
  static String? validatePassword(String? password, {bool isRegistration = false}) {
    if (password == null || password.isEmpty) {
      return 'Password is required';
    }

    if (password.length < 8) {
      return 'Password must be at least 8 characters long';
    }

    if (password.length > 128) {
      return 'Password is too long (max 128 characters)';
    }

    if (isRegistration) {
      // Strong password requirements for registration
      bool hasUpperCase = password.contains(RegExp(r'[A-Z]'));
      bool hasLowerCase = password.contains(RegExp(r'[a-z]'));
      bool hasDigit = password.contains(RegExp(r'[0-9]'));
      bool hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

      if (!hasUpperCase) {
        return 'Password must contain at least one uppercase letter';
      }
      if (!hasLowerCase) {
        return 'Password must contain at least one lowercase letter';
      }
      if (!hasDigit) {
        return 'Password must contain at least one number';
      }
      if (!hasSpecialChar) {
        return 'Password must contain at least one special character (!@#\$%^&*)';
      }
    }

    // Check for common weak passwords
    List<String> commonPasswords = [
      'password',
      'password123',
      '12345678',
      '87654321',
      '11111111',
      'qwerty',
      'abc123',
    ];
    if (commonPasswords.contains(password.toLowerCase())) {
      return 'This password is too common. Please choose a stronger password.';
    }

    return null;
  }

  /// Validate name
  static String? validateName(String? name) {
    if (name == null || name.isEmpty) {
      return 'Name is required';
    }

    name = sanitizeInput(name);

    if (name.length < 2) {
      return 'Name must be at least 2 characters long';
    }

    if (name.length > 100) {
      return 'Name is too long (max 100 characters)';
    }

    if (!_nameRegex.hasMatch(name)) {
      return 'Name can only contain letters, spaces, and dots';
    }

    return null;
  }

  /// Validate roll number
  static String? validateRollNumber(String? rollNumber) {
    if (rollNumber == null || rollNumber.isEmpty) {
      return 'Roll number is required';
    }

    rollNumber = rollNumber.trim();

    if (rollNumber.length > 20) {
      return 'Roll number is too long (max 20 characters)';
    }

    if (!_rollNumberRegex.hasMatch(rollNumber)) {
      return 'Roll number can only contain letters, numbers, hyphens, and underscores';
    }

    return null;
  }

  /// Validate institute ID
  static String? validateInstituteId(String? instituteId) {
    if (instituteId == null || instituteId.isEmpty) {
      return 'Institute ID is required';
    }

    instituteId = instituteId.trim();

    if (instituteId.length > 50) {
      return 'Institute ID is too long (max 50 characters)';
    }

    if (!_instituteIdRegex.hasMatch(instituteId)) {
      return 'Institute ID can only contain letters, numbers, hyphens, and underscores';
    }

    return null;
  }

  /// Validate subject label for uploads and forms.
  ///
  /// Allows Unicode names (e.g. Marathi). Only path-injection characters are blocked.
  /// [B2BStorageService.generatePhotoPath] normalizes the string for the object key.
  static String? validateSubject(String? subject) {
    if (subject == null || subject.isEmpty) {
      return 'Subject is required';
    }

    subject = sanitizeInput(subject);
    if (subject.isEmpty) {
      return 'Subject is required';
    }

    const maxLen = 120;
    if (subject.length > maxLen) {
      return 'Subject name is too long (max $maxLen characters)';
    }

    if (subject.contains('/') || subject.contains('\\')) {
      return 'Subject name cannot contain slashes';
    }
    if (subject.contains('..')) {
      return 'Subject name cannot contain ..';
    }

    return null;
  }

  /// Validate phone number
  static String? validatePhone(String? phone) {
    if (phone == null || phone.isEmpty) {
      return 'Phone number is required';
    }

    // Remove spaces, dashes, parentheses
    phone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    if (phone.length != 10) {
      return 'Phone number must be 10 digits';
    }

    if (!_phoneRegex.hasMatch(phone)) {
      return 'Please enter a valid 10-digit phone number';
    }

    return null;
  }

  /// Sanitize input to prevent XSS and injection attacks
  static String sanitizeInput(String input) {
    if (input.isEmpty) return input;

    // Trim whitespace
    input = input.trim();

    // Remove null bytes
    input = input.replaceAll('\x00', '');

    // Remove control characters except newlines and tabs
    input = input.replaceAll(RegExp(r'[\x00-\x08\x0B-\x0C\x0E-\x1F]'), '');

    // Limit length to prevent DoS
    if (input.length > 1000) {
      input = input.substring(0, 1000);
    }

    return input;
  }

  /// Validate latitude
  static String? validateLatitude(double? latitude) {
    if (latitude == null) {
      return 'Latitude is required';
    }
    if (latitude < -90 || latitude > 90) {
      return 'Latitude must be between -90 and 90';
    }
    return null;
  }

  /// Validate longitude
  static String? validateLongitude(double? longitude) {
    if (longitude == null) {
      return 'Longitude is required';
    }
    if (longitude < -180 || longitude > 180) {
      return 'Longitude must be between -180 and 180';
    }
    return null;
  }

  /// Validate radius (in meters)
  static String? validateRadius(double? radius) {
    if (radius == null) {
      return 'Radius is required';
    }
    if (radius < 10 || radius > 10000) {
      return 'Radius must be between 10 and 10000 meters';
    }
    return null;
  }

  /// Validate file size (in bytes)
  /// Supports both KB and MB limits
  static String? validateFileSize(int fileSizeBytes, {int? maxSizeKB, int? maxSizeMB}) {
    int maxSizeBytes;
    String sizeUnit;
    
    if (maxSizeKB != null) {
      maxSizeBytes = maxSizeKB * 1024; // Convert KB to bytes
      sizeUnit = '$maxSizeKB KB';
    } else {
      final mb = maxSizeMB ?? 5; // Default 5MB if not specified
      maxSizeBytes = mb * 1024 * 1024; // Convert MB to bytes
      sizeUnit = '$mb MB';
    }
    
    if (fileSizeBytes > maxSizeBytes) {
      return 'File size must be less than $sizeUnit (current: ${(fileSizeBytes / 1024).toStringAsFixed(1)} KB)';
    }
    return null;
  }

  /// Validate image file extension
  static String? validateImageFile(String? filename) {
    if (filename == null || filename.isEmpty) {
      return 'Filename is required';
    }

    final validExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];
    final extension = filename.toLowerCase().substring(filename.lastIndexOf('.'));

    if (!validExtensions.contains(extension)) {
      return 'Invalid image format. Allowed: ${validExtensions.join(", ")}';
    }

    return null;
  }

  /// Validate URL
  static String? validateUrl(String? url) {
    if (url == null || url.isEmpty) {
      return 'URL is required';
    }

    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
        return 'URL must start with http:// or https://';
      }
      return null;
    } catch (e) {
      return 'Invalid URL format';
    }
  }

  /// Validate date range
  static String? validateDateRange(DateTime? startDate, DateTime? endDate) {
    if (startDate == null || endDate == null) {
      return 'Both start and end dates are required';
    }

    if (endDate.isBefore(startDate)) {
      return 'End date must be after start date';
    }

    final difference = endDate.difference(startDate).inDays;
    if (difference > 365) {
      return 'Date range cannot exceed 365 days';
    }

    return null;
  }

  /// Check if string contains potentially dangerous content
  static bool containsDangerousContent(String input) {
    // Check for SQL injection patterns
    final sqlPatterns = [
      r"(\b(SELECT|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|EXEC|EXECUTE)\b)",
      r"(--|/\*|\*/|;|')",
    ];

    // Check for XSS patterns
    final xssPatterns = [
      r"<script",
      r"javascript:",
      r"onerror=",
      r"onload=",
      r"onclick=",
    ];

    final lowerInput = input.toLowerCase();

    for (var pattern in sqlPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(lowerInput)) {
        return true;
      }
    }

    for (var pattern in xssPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(lowerInput)) {
        return true;
      }
    }

    return false;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/utils/responsive.dart';
import '../../core/institute_id_display.dart';
import '../../core/theme/app_theme.dart';
import '../../services/institute_setup_service.dart';
import '../../services/error_handler.dart';
import '../../services/validation_service.dart';

/// Super Admin Institute Management Screen
/// 
/// Allows super admin to create new institutes with automatic setup:
/// - Institute document
/// - Default admin user
/// - All subcollections
/// - Storage structure
class SuperAdminInstituteScreen extends StatefulWidget {
  static const routeName = '/super-admin-institutes';
  const SuperAdminInstituteScreen({super.key});

  @override
  State<SuperAdminInstituteScreen> createState() => _SuperAdminInstituteScreenState();
}

class _SuperAdminInstituteScreenState extends State<SuperAdminInstituteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _instituteIdController = TextEditingController();
  final _instituteCodeController = TextEditingController();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _districtController = TextEditingController();
  final _stateController = TextEditingController();
  final _countryController = TextEditingController();
  final _mobileController = TextEditingController();
  
  // Admin user fields
  final _adminNameController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _adminPasswordController = TextEditingController();
  final _adminMobileController = TextEditingController();

  final InstituteSetupService _setupService = InstituteSetupService();
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  @override
  void dispose() {
    _instituteIdController.dispose();
    _instituteCodeController.dispose();
    _nameController.dispose();
    _locationController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _stateController.dispose();
    _countryController.dispose();
    _mobileController.dispose();
    _adminNameController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    _adminMobileController.dispose();
    super.dispose();
  }

  Future<void> _createInstitute() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await _setupService.setupInstitute(
        instituteId: _instituteIdController.text.trim(),
        name: _nameController.text.trim(),
        instituteCode: _instituteCodeController.text.trim().isEmpty 
            ? null 
            : _instituteCodeController.text.trim(),
        location: _locationController.text.trim().isEmpty 
            ? null 
            : _locationController.text.trim(),
        address: _addressController.text.trim().isEmpty 
            ? null 
            : _addressController.text.trim(),
        city: _cityController.text.trim().isEmpty 
            ? null 
            : _cityController.text.trim(),
        district: _districtController.text.trim().isEmpty 
            ? null 
            : _districtController.text.trim(),
        state: _stateController.text.trim().isEmpty 
            ? null 
            : _stateController.text.trim(),
        country: _countryController.text.trim().isEmpty 
            ? 'India' 
            : _countryController.text.trim(),
        mobileNo: _mobileController.text.trim().isEmpty 
            ? null 
            : _mobileController.text.trim(),
        adminName: _adminNameController.text.trim(),
        adminEmail: _adminEmailController.text.trim(),
        adminPassword: _adminPasswordController.text,
        adminMobile: _adminMobileController.text.trim(),
      );

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (result['success'] == true) {
        _showSuccessDialog(result);
        _clearForm();
      } else {
        _showError(result['message'] ?? 'Failed to create institute');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      final errorResult = ErrorHandler.formatErrorForUI(e, context: 'createInstitute');
      _showError(errorResult['message']);
    }
  }

  void _clearForm() {
    _formKey.currentState?.reset();
    _instituteIdController.clear();
    _instituteCodeController.clear();
    _nameController.clear();
    _locationController.clear();
    _addressController.clear();
    _cityController.clear();
    _districtController.clear();
    _stateController.clear();
    _countryController.clear();
    _mobileController.clear();
    _adminNameController.clear();
    _adminEmailController.clear();
    _adminPasswordController.clear();
    _adminMobileController.clear();
  }

  void _showSuccessDialog(Map<String, dynamic> result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppTheme.primaryGreen, size: 28),
            SizedBox(width: 12),
            Text('Institute Created Successfully'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Institute ID: ${formatInstituteIdForDisplay(result['instituteId']?.toString() ?? '')}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text('Admin Credentials:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primaryGreen),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Email: ${result['adminEmail']}'),
                    const SizedBox(height: 4),
                    Text('Password: ${result['adminPassword']}'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '⚠️ Please save these credentials securely. They will not be shown again.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textGray,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text: 'Email: ${result['adminEmail']}\nPassword: ${result['adminPassword']}',
              ));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Credentials copied to clipboard')),
              );
            },
            child: const Text('Copy Credentials'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.accentRed,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Create New Institute'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Institute Information Section
              _buildSectionHeader('Institute Information'),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _instituteIdController,
                decoration: const InputDecoration(
                  labelText: 'Institute ID *',
                  hintText: 'e.g., inst001',
                  prefixIcon: Icon(Icons.business),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Institute ID is required';
                  }
                  if (value.length > 50) {
                    return 'Institute ID must be less than 50 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _instituteCodeController,
                decoration: const InputDecoration(
                  labelText: 'Institute Code (Optional)',
                  hintText: 'e.g., MSCE001',
                  prefixIcon: Icon(Icons.qr_code),
                ),
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Institute Name *',
                  hintText: 'e.g., MSCE Pune',
                  prefixIcon: Icon(Icons.school),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Institute name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  hintText: 'e.g., Pune',
                  prefixIcon: Icon(Icons.location_on),
                ),
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  hintText: 'Full address',
                  prefixIcon: Icon(Icons.home),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cityController,
                      decoration: const InputDecoration(
                        labelText: 'City',
                        prefixIcon: Icon(Icons.location_city),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _stateController,
                      decoration: const InputDecoration(
                        labelText: 'State',
                        prefixIcon: Icon(Icons.map),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _districtController,
                      decoration: const InputDecoration(
                        labelText: 'District',
                        prefixIcon: Icon(Icons.map),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _countryController,
                      decoration: const InputDecoration(
                        labelText: 'Country',
                        prefixIcon: Icon(Icons.public),
                      ),
                      initialValue: 'India',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _mobileController,
                decoration: const InputDecoration(
                  labelText: 'Contact Number',
                  hintText: '10-digit mobile number',
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
                maxLength: 10,
              ),
              
              const SizedBox(height: 32),
              
              // Admin User Section
              _buildSectionHeader('Default Admin User'),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _adminNameController,
                decoration: const InputDecoration(
                  labelText: 'Admin Name *',
                  hintText: 'Full name',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Admin name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _adminEmailController,
                decoration: const InputDecoration(
                  labelText: 'Admin Email *',
                  hintText: 'admin@institute.com',
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
                textCapitalization: TextCapitalization.none,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Admin email is required';
                  }
                  if (!value.contains('@')) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _adminPasswordController,
                decoration: InputDecoration(
                  labelText: 'Admin Password *',
                  hintText: 'Strong password (see requirements)',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() => _isPasswordVisible = !_isPasswordVisible);
                    },
                  ),
                ),
                obscureText: !_isPasswordVisible,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Admin password is required';
                  }
                  return ValidationService.validatePassword(value, isRegistration: true);
                },
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _adminMobileController,
                decoration: const InputDecoration(
                  labelText: 'Admin Mobile *',
                  hintText: '10-digit mobile number',
                  prefixIcon: Icon(Icons.phone_android),
                ),
                keyboardType: TextInputType.phone,
                maxLength: 10,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Admin mobile is required';
                  }
                  if (value.length != 10) {
                    return 'Mobile number must be 10 digits';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 32),
              
              // Create Button
              ElevatedButton(
                onPressed: _isLoading ? null : _createInstitute,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Create Institute',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: AppTheme.primaryGreen),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }
}

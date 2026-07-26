# App Store Resubmission Checklist

## Before You Resubmit

Complete ALL items on this checklist. Apple will reject again if any are missing.

---

## Part A: Account & Legal (Complete First)

### Account Type
- [ ] Contact Apple: Request account conversion to "Organization"
- [ ] Provide GCC TBC as legal organization name
- [ ] Provide tax ID if available
- [ ] Wait for approval (3-5 days)
- [ ] Verify account now shows "Organization"

### Seller Name
- [ ] Log into App Store Connect
- [ ] Go to "App Information" → "General Information"
- [ ] Update "Seller Name" to: **"GCC TBC"** (or full legal name)
- [ ] Save changes

### Distribution Method
- [ ] Choose ONE:
  - [ ] Option A: Submit "Unlisted App Distribution" request
    - Wait for Apple approval (7-14 days)
  - [ ] Option B: Use Apple Business Manager
    - Setup organizational account first
  - [ ] Option C: Switch to "Public" (only if truly public app - NOT recommended)

---

## Part B: Privacy & Data (Required for Biometric Apps)

### Privacy Policy
- [ ] Create or update Privacy Policy document
- [ ] Must clearly state:
  - [ ] "App uses face recognition/biometric data"
  - [ ] "Face images processed on-device only"
  - [ ] "Face embeddings stored encrypted"
  - [ ] "No biometric data shared with third parties"
  - [ ] "User can delete their data"
  - [ ] "Data retention period" (e.g., "Deleted after 1 year")
  - [ ] "Contact us" information

### In-App Privacy Link
- [ ] Add to app Settings or Help menu:
  ```
  Settings → Privacy Policy
  [Link to GCC TBC privacy policy or website]
  ```
- [ ] Privacy policy must be accessible from app
- [ ] Link must be easy to find

### Privacy Policy Location
Choose one:
- [ ] [ ] Hosted on GCC TBC website: `https://gcc-tbc.edu/privacy`
- [ ] [ ] In app as text/PDF
- [ ] [ ] Link in app to external privacy policy

### Data Practices Declaration (Important!)
In App Store Connect:
1. Go to "App Privacy"
2. Declare privacy practices:
   - [ ] "We collect: Device ID, User ID, Face data"
   - [ ] "We do NOT: Share with third parties"
   - [ ] "We DO: Encrypt data, Allow deletion"
3. Save declarations

---

## Part C: App Content & Description

### App Description (Update in App Store Connect)

Make it clear this is institutional:

**Current** (Generic):
```
Attendance marking app with face recognition
```

**Updated** (Institutional):
```
Attendance marking system for GCC TBC institution. 
Uses face recognition to mark attendance for registered 
students and staff. Designed for use by educational institutions.
```

### App Keywords
- [ ] Add: "attendance", "school", "face recognition"
- [ ] Add: "educational", "institution"

### Support URL
- [ ] Add contact email for GCC TBC technical support
- [ ] Example: support@gcc-tbc.edu

### Category
- [ ] Set to: "Education" (not "Productivity")

### Age Rating
- [ ] Complete Age Rating Questionnaire:
  - [ ] "Does app collect biometric data?" → YES
  - [ ] "Does app have user accounts?" → YES
  - [ ] All other defaults OK
- [ ] Should get: 4+ or 12+ rating

---

## Part D: Screenshots & Artwork

### Update Screenshots to Show Institutional Context

**Screenshot 1**: Home screen
- [ ] Should show: App name, institution context
- [ ] Caption: "GCC TBC Attendance System"

**Screenshot 2**: Registration
- [ ] Should show: Face capture, green box
- [ ] Caption: "Register student face"

**Screenshot 3**: Attendance
- [ ] Should show: Attendance marking
- [ ] Caption: "Mark attendance at 3 ft distance"

**Screenshot 4**: Settings/Privacy
- [ ] Should show: Privacy policy link
- [ ] Caption: "Privacy settings and data management"

### App Icon
- [ ] Should be professional (not test/debug version)
- [ ] Should include institution branding if possible
- [ ] Should NOT say "DEBUG" or "TEST"

### Preview Video (Optional)
- [ ] Create 30-second demo showing:
  - User registration
  - Attendance marking
  - Real-world use at school
- [ ] Helps with approval

---

## Part E: Code & Build Preparation

### Debug Flags
- [ ] [ ] Remove or set `isDebuggable = false` in build.gradle
- [ ] [ ] Remove any `debugPrint()` statements (or keep them, harmless)
- [ ] [ ] Disable any debug UI overlays
- [ ] [ ] Ensure "Release Mode" symbols present

**Verify in `android/app/build.gradle.kts`:**
```kotlin
buildTypes {
    release {
        isDebuggable = false  // ← Must be false
    }
}
```

### Test Flight Testing (Recommended)
- [ ] Build and upload to TestFlight first
- [ ] Test with actual iOS device (not simulator)
- [ ] Verify:
  - [ ] App launches without crashes
  - [ ] Camera permission works
  - [ ] Face recognition works
  - [ ] No errors in logs
  - [ ] Privacy policy link works

### Permissions
Verify in `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>We need camera access to capture face images for attendance marking</string>

<key>NSFaceIDUsageDescription</key>
<string>Face recognition is used to verify student identity for attendance marking</string>
```

Both should be present and explain WHY the permission is needed.

---

## Part F: Version & Build Numbers

### Update Build Number
- [ ] Current version: 1.0.0 (7)
- [ ] New version: **1.0.1** or **1.1.0**
- [ ] Reason: Fixes for App Store guidelines

**In `pubspec.yaml`:**
```yaml
version: 1.0.1+8  # Increased build number
```

### Version Notes (for Apple Reviewer)
In App Store Connect, add notes:
```
Version 1.0.1 - Guideline Compliance Updates:

✓ Migrated account to organization type (GCC TBC)
✓ Updated seller name to organization
✓ Added comprehensive privacy policy
✓ Implemented unlisted app distribution
✓ Added in-app privacy settings
✓ Clarified institutional use case in description

This app is designed exclusively for GCC TBC institution 
and has been updated to comply with App Store requirements 
for apps handling biometric data.

Contact: [technical contact name and email]
```

---

## Part G: Authorization & Documentation

### Prepare Authorization Letter

Create document: `GCC_TBC_Authorization.pdf`

**Content:**
```
TO: Apple App Store Review Team

RE: Authorization for Attendance Application Submission

This is to certify that [Your Name] is authorized to submit 
and maintain the "GCC TBC Attendance" application on behalf 
of GCC TBC institution.

The application uses face recognition technology exclusively 
for attendance marking for our institution's students and staff.

Organization: GCC TBC
Authorized by: [Principal/Director name]
Position: [Position]
Email: [organization email]
Date: [Today's date]

Signature: ________________________________

---

PRIVACY COMMITMENT:

GCC TBC commits to:
- Storing biometric data encrypted and on-device only
- Not sharing data with third parties
- Allowing users to delete their data
- Following all applicable privacy laws
- Maintaining data security standards
```

### Save & Have Ready
- [ ] Save as PDF: `GCC_TBC_Authorization.pdf`
- [ ] Keep copy for your records
- [ ] Be ready to upload or reference in submission notes

---

## Part H: Final Checks (Day of Submission)

### 24 Hours Before Submission
- [ ] Test app on real iOS device
- [ ] Verify no crashes
- [ ] Verify camera works
- [ ] Verify privacy policy accessible
- [ ] Check internet connection (app may need it)

### Submission Checklist
- [ ] Account type: Organization ✓
- [ ] Seller name: GCC TBC ✓
- [ ] Privacy policy: Complete ✓
- [ ] App description: Updated ✓
- [ ] Screenshots: Updated ✓
- [ ] Permissions: Justified ✓
- [ ] Build number: Incremented ✓
- [ ] Distribution: Unlisted (if applicable) ✓
- [ ] Authorization: Ready ✓

### In App Store Connect Before Submitting
- [ ] Navigate to: Version Details → Summary
- [ ] Verify all information correct
- [ ] Review Section: Click on each field to confirm
- [ ] Click: "Submit for Review"
- [ ] Paste authorization letter in "Notes" section

---

## Part I: Submission Notes to Include

In the "Review Notes" section of App Store Connect:

```
SUBMISSION NOTES - READ CAREFULLY:

Subject: Institutional Attendance System with Biometric Data

This is an attendance marking application for GCC TBC institution.

ORGANIZATIONAL DETAILS:
- Organization: GCC TBC
- Account type: Organization
- Account holder authorized by: [Principal/Director]
- Authorization: GCC_TBC_Authorization.pdf (attached)

BIOMETRIC DATA HANDLING:
- Face biometric data is captured on-device only
- All embeddings stored encrypted in app
- No data shared with third parties
- No data sent to cloud servers
- Users can delete their data
- Privacy policy: [URL or in-app accessible]

DATA RETENTION:
- Biometric embeddings: 1 year (then auto-deleted)
- Photos: Deleted immediately after processing
- Attendance records: Maintained for school year

USAGE:
- Intended for educational staff and students
- Used only within GCC TBC institution
- Complies with student privacy laws

CONTACT FOR VERIFICATION:
Name: [Your name]
Email: [Your email]
Organization: [GCC TBC contact info]

Thank you for your thorough review.
```

---

## Part J: After Submission

### What to Expect
- [ ] Receive confirmation Apple received submission
- [ ] Review typically takes 24-48 hours
- [ ] Apple may ask clarifying questions (respond quickly)
- [ ] If approved: Available on App Store (or unlisted)
- [ ] If rejected: Will receive detailed rejection with next steps

### If Rejected Again
1. Read rejection carefully
2. Fix specific issue mentioned
3. Increment version number again
4. Resubmit (no need to wait)

### If Approved
1. Download app from App Store
2. Test full end-to-end
3. Create distribution link (for institutional users)
4. Roll out to GCC TBC

---

## Estimated Timeline

| Task | Duration | Notes |
|------|----------|-------|
| Account conversion | 3-5 days | Contact Apple immediately |
| Privacy policy creation | 1-2 days | Can do while waiting for account |
| App store content update | 1-2 days | Screenshots, description, etc. |
| Unlisted request (if needed) | 7-14 days | Submit after account ready |
| Final build & testing | 1 day | TestFlight first recommended |
| Submission to review | 24-48 hours | For first review attempt |
| **Total** | **2-4 weeks** | Depends on unlisted approval |

---

## Common Mistakes to Avoid

❌ Submitting before account type changed (Auto-reject)  
❌ Omitting privacy policy or data handling info (Rejection)  
❌ Keeping app as "public" distribution (Rejection)  
❌ Not explaining institutional use (Rejection)  
❌ Leaving debug builds/flags in (May reject)  
❌ No way to contact developer (Suspicious)  
❌ Ambiguous app purpose (Confuses reviewers)  

✅ Do explain institutional use case clearly  
✅ Do provide complete privacy information  
✅ Do use organization account  
✅ Do include authorization documentation  
✅ Do test thoroughly before submitting  

---

## Support Resources

- **Apple Developer Support**: [developer.apple.com/contact](https://developer.apple.com/contact)
  - Use when: Account issues, technical questions, appeals

- **App Store Review Guidelines**: [developer.apple.com/app-store/review](https://developer.apple.com/app-store/review)
  - Use when: Unsure if something violates guidelines

- **App Store Connect Help**: [help.apple.com/app-store-connect](https://help.apple.com/app-store-connect)
  - Use when: Technical questions about submission process

---

**Status**: Ready to execute  
**Complexity**: Medium  
**Time Required**: 2-4 weeks (mostly waiting for approvals)  
**Next Action**: Contact Apple Developer Support about account conversion

---

## Questions?

If stuck on any step:
1. Check the APP_STORE_REJECTION_GUIDE.md for more details
2. Contact Apple Developer Support
3. Reference submission ID: `63e0d60d-fc0c-4488-b061-842783e2889b`

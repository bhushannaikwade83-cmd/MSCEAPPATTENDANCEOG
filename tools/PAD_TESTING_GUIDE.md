# PAD Testing & Debugging Guide

## Purpose
Determine if your device's anti-spoofing model is working with the new high thresholds (0.85), or if you need to switch to an alternative model.

## Quick Diagnostic Test

### Setup
1. Run your app with the updated thresholds (0.85)
2. Enable debug output (already in code via `debugPrint`)
3. Check logcat/device logs

### Test Cases

#### Test 1: Real Face (YOU)
**Procedure:**
1. Go to registration or attendance
2. Face the camera naturally
3. Capture photo with green box
4. Check logs for output

**Expected Output:**
```
📸 PAD: isReal=true conf=0.35 — PAD: 35% LIVE (threshold=0.85)
```

**✅ PASS**: Score < 0.60  
**❌ FAIL**: Score > 0.70

---

#### Test 2: Printed Photo
**Procedure:**
1. Print your photo on paper (or display on screen)
2. Hold it in front of camera
3. Capture (should show red box if stream detection works)
4. Check logs

**Expected Output:**
```
📸 PAD: isReal=false conf=0.88 — PAD: 88% ATTACK (threshold=0.85)
```

**✅ PASS**: Score > 0.80 AND blocked  
**❌ FAIL**: Score < 0.70 (not detected as fake)

---

#### Test 3: Phone Screen Replay
**Procedure:**
1. Play video of face on phone/laptop screen
2. Capture video playing on screen
3. Check logs

**Expected Output:**
```
📸 PAD: isReal=false conf=0.82 — PAD: 82% ATTACK (threshold=0.85)
```

**✅ PASS**: Score > 0.75 AND blocked  
**❌ FAIL**: Score < 0.70 (not detected)

---

#### Test 4: Family Member (Different Face)
**Procedure:**
1. Someone with similar features captures attendance
2. Check both PAD score and face match score
3. Should pass PAD but might fail face match

**Expected Output:**
```
📸 PAD: isReal=true conf=0.42 — PAD: 42% LIVE (threshold=0.85)
```

**✅ PASS**: Score < 0.65 (not blocked as fake)  
**❌ FAIL**: Score > 0.75 (wrongly marked fake)

---

## Interpreting Results

### Scenario 1: All Tests PASS ✅
**Conclusion**: Current model works!  
**Action**: Keep 0.85 threshold. Your device is good.

---

### Scenario 2: Real face blocked (Test 1 FAIL)
**Conclusion**: Model too aggressive for your device.  
**Action**: Raise threshold to 0.90 (more lenient)

**Code change:**
```dart
static const double liveThreshold = 0.90;
static const double _faceAntiSpoofAttackThreshold = 0.90;
```

---

### Scenario 3: Fake photos not detected (Test 2 FAIL)
**Conclusion**: Model doesn't discriminate well on your device.  
**Action**: Try alternative model from CVPR2019 repo.

**Steps:**
1. Clone https://github.com/syaringan357/Android-MobileFaceNet-MTCNN-FaceAntiSpoofing
2. Extract `FaceAntiSpoofing.tflite` from `app/src/main/assets/`
3. Replace your current model
4. Re-run Test 2

---

### Scenario 4: Mixed results
**Conclusion**: Model works but device-specific tuning needed.  
**Action**: Adjust threshold based on your data.

**Scoring Scale:**
- Real face: 0.1-0.6 (most common: 0.2-0.4)
- Fake photo: 0.75-0.95 (most common: 0.80-0.90)
- Video replay: 0.70-0.90 (most common: 0.75-0.85)

**Decision:**
- If real=0.5, fake=0.85 → threshold=0.70 works
- If real=0.6, fake=0.87 → threshold=0.75 works
- If real=0.4, fake=0.92 → threshold=0.65 works

---

## Logging Your Device Data

### Add this to `anti_spoof_service.dart` for detailed logging:

```dart
static Future<AntiSpoofResult> checkSpoof(String photoPath) async {
  try {
    // ... existing code ...
    
    final result = switch (_backend) {
      _AntiSpoofBackend.faceAntiSpoofing256 => () {
          final patch = _faceAntiSpoofPatchFromImage(decoded, faceBox) ??
              _rgbPatchFullFrame(decoded, _faceAntiSpoofSize);
          if (patch == null) {
            return AntiSpoofResult(
              isReal: false,
              confidence: 0.0,
              reason: 'Could not prepare face patch',
            );
          }
          return _runFaceAntiSpoofInference(patch);
        }(),
      // ... other backends ...
    };

    // 📊 DETAILED DEBUG LOG FOR TESTING
    if (kDebugMode) {
      debugPrint(
        '═══════════════════════════════════════════════════════\n'
        '📊 PAD DETAILED TEST RESULT:\n'
        '  Model: $_backend\n'
        '  isReal: ${result.isReal}\n'
        '  Confidence: ${(result.confidence * 100).toStringAsFixed(2)}%\n'
        '  Block threshold: 0.85\n'
        '  Will BLOCK: ${!result.isReal && result.confidence > 0.85}\n'
        '  Reason: ${result.reason}\n'
        '═══════════════════════════════════════════════════════',
      );
    }

    return result;
  } catch (e) {
    // ... existing error handling ...
  }
}
```

---

## Collecting Device Data

**Create a test spreadsheet** (Test1_RealFace.png, Test2_PrintedPhoto.png, etc.):

| Test | File | Score | Expected | Pass? | Device | Date |
|------|------|-------|----------|-------|--------|------|
| 1 | RealFace_front.jpg | 0.38 | <0.60 | ✅ | Samsung A12 | 2026-06-02 |
| 2 | PrintPhoto_center.jpg | 0.87 | >0.80 | ✅ | Samsung A12 | 2026-06-02 |
| 3 | VideoReplay_screen.jpg | 0.82 | >0.75 | ✅ | Samsung A12 | 2026-06-02 |
| 4 | Brother_face.jpg | 0.42 | <0.65 | ✅ | Samsung A12 | 2026-06-02 |

This data helps you:
- Prove PAD works on your device
- Choose optimal threshold
- Decide if model swap needed
- Document production performance

---

## Next Steps Based on Results

### ✅ All Tests Pass
```
👍 Current model works. Keep 0.85 threshold.
Estimated accuracy: 95%+ on printed photos
Ship with confidence.
```

### ⚠️ Real Faces Blocked
```
⚠️ Threshold too strict. Change to 0.90.
If still fails, need model investigation.
Check: lighting conditions, camera focus, face angle
```

### ❌ Fakes Not Detected
```
❌ Model doesn't work on your device.
Next steps:
1. Try syaringan357's FaceAntiSpoofing.tflite
2. If still fails, convert CVPR2019 model
3. Worst case: implement rule-based PAD
```

---

## Troubleshooting

**Q: All scores are 0.0?**  
A: Model not loaded. Check:
- `pubspec.yaml` has `assets/models/face_anti_spoofing.tflite`
- Model file exists in assets folder (not .gitignore'd)
- Run: `flutter clean && flutter pub get`

**Q: Scores always 0.5?**  
A: Model fallback triggered. Check:
- Model loads successfully (check logs)
- Interpreter created properly
- Input tensor shape matches [1, 256, 256, 3]

**Q: Scores seem random?**  
A: Input image too small or face not visible. Check:
- Face takes up at least 20% of image
- Photo in-focus (not blurry)
- Sufficient lighting

---

## Files to Update with Testing Code

1. `lib/services/anti_spoof_service.dart` - Add detailed logging
2. `lib/screens/attendance_camera_screen.dart` - Show PAD score on screen
3. Create `lib/screens/pad_debug_screen.dart` - Dedicated testing UI

---

## Questions to Answer

After testing, answer these:
1. What's your real face score range on your device?
2. What's your fake photo score range?
3. What's your video replay score range?
4. What threshold works best (0.75, 0.80, 0.85, 0.90)?
5. What device model are you testing on?

Share these answers if you need help tuning further!

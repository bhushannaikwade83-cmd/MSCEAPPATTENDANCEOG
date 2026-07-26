# Anti-spoof TFLite models

## Why you saw `Failed to load anti-spoof model: Bad state: failed precondition`

`anti_spoof_model.tflite` is a **MiniFAS** file converted with **Google AI Edge** (`ai_edge_torch`). On many devices—especially **iOS** with `TensorFlowLiteSwift 2.12`—that graph cannot allocate tensors in `tflite_flutter`.

The app now tries **`face_anti_spoofing.tflite` first** (256×256 tree model, standard `TFLITE_BUILTINS`, from the [MobileFaceNet + FaceAntiSpoofing](https://github.com/syaringan357/Android-MobileFaceNet-MTCNN-FaceAntiSpoofing) Android project). If that loads, you should see:

```
✅ Anti-spoof loaded (_AntiSpoofBackend.faceAntiSpoofing256) from assets/models/face_anti_spoofing.tflite — input=[1, 256, 256, 3] ...
```

If both models fail, the app still uses LCD grid + photo-of-photo heuristics.

## Bundled files (app size)

| Asset | Role |
|-------|------|
| `assets/models/face_anti_spoofing.tflite` | **Only PAD model** — capture-time live check (~4 MB) |
| `assets/models/mobilefacenet.tflite` | Face match embeddings (~5 MB) |

`anti_spoof_model.tflite` (MiniFAS) was **removed** — it failed on iOS and added ~6 MB without benefit.

## Optional: replace MiniFAS with a mobile-compatible build

Use [Silent-Face-Anti-Spoofing-TFLite](https://github.com/feni-katharotiya/Silent-Face-Anti-Spoofing-TFLite) (Python 3.10/3.11) and convert with **only** `TFLITE_BUILTINS` (no `SELECT_TF_OPS`). Overwrite `anti_spoof_model.tflite`, then:

```dart
await AntiSpoofService.retryInitialize();
```

Full restart required (`flutter run`, not hot reload).

## Android note

`android/app/build.gradle.kts` includes `litert-api:1.4.1` for `tflite_flutter` 0.12.x.

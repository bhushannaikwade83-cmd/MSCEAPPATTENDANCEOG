import 'dart:convert';

import 'production_face_recognition_constants.dart';

/// MobileFaceNet output size used by this app (see `mobilefacenet.tflite`).
const int kMobileFaceNetEmbeddingDimensions = 192;

/// ArcFace buffalo_l output size (InsightFace API / backend).
const int kArcFaceEmbeddingDimensions =
    ProductionFaceRecognitionConstants.arcFaceEmbeddingDimensions;

bool _listIsNnEmbedding(dynamic emb) {
  if (emb is! List || emb.length < kMobileFaceNetEmbeddingDimensions) return false;
  return emb.any((v) => v is num && v.toDouble().abs() > 1e-6);
}

/// Validates an in-memory vector before PATCH to Supabase.
bool registrationEmbeddingVectorValid(List<double> embedding) =>
    _listIsNnEmbedding(embedding);

/// Shared rule: student row has a usable neural embedding for attendance.
bool studentHasNonEmptyFaceEmbedding(dynamic faceEmbeddingField) {
  if (faceEmbeddingField == null) return false;

  // Handle direct List storage
  if (faceEmbeddingField is List) {
    return faceEmbeddingField.isNotEmpty;
  }

  if (faceEmbeddingField is String) {
    try {
      final decoded = jsonDecode(faceEmbeddingField);
      return studentHasNonEmptyFaceEmbedding(decoded);
    } catch (_) {
      return false;
    }
  }

  // Handle Map storage (with 'embedding' or 'faceTemplates' keys)
  if (faceEmbeddingField is! Map) return false;
  final m = Map<String, dynamic>.from(faceEmbeddingField);

  final emb = m['embedding'];
  if (emb is List && emb.isNotEmpty) return true;

  final templates = m['faceTemplates'];
  if (templates is List) {
    for (final t in templates) {
      if (t is Map) {
        final e = t['embedding'];
        if (e is List && e.isNotEmpty) return true;
      }
    }
  }
  return false;
}

/// Strict gate before/after persistence: detected model vector present and plausible.
bool registrationFaceEmbeddingFieldValid(dynamic faceEmbeddingField) {
  if (faceEmbeddingField is! Map) return false;
  final m = Map<String, dynamic>.from(faceEmbeddingField);
  if (_listIsNnEmbedding(m['embedding'])) return true;
  final templates = m['faceTemplates'];
  if (templates is List) {
    for (final t in templates) {
      if (t is Map) {
        final e = t['embedding'];
        if (_listIsNnEmbedding(e)) return true;
      }
    }
  }
  return false;
}

List<double> _coerceEmbeddingList(dynamic raw) {
  if (raw is! List || raw.isEmpty) return const [];
  return raw.map((e) => (e as num).toDouble()).toList();
}

/// All stored embedding vectors for one student (single + multi-sample templates).
List<List<double>> parseAllEmbeddingsFromField(dynamic faceEmbeddingField) {
  if (faceEmbeddingField == null) return const [];

  if (faceEmbeddingField is List) {
    final v = _coerceEmbeddingList(faceEmbeddingField);
    return v.isEmpty ? const [] : [v];
  }

  if (faceEmbeddingField is String) {
    try {
      return parseAllEmbeddingsFromField(jsonDecode(faceEmbeddingField));
    } catch (_) {
      return const [];
    }
  }

  if (faceEmbeddingField is! Map) return const [];
  final m = Map<String, dynamic>.from(faceEmbeddingField);
  final out = <List<double>>[];

  final primary = _coerceEmbeddingList(m['embedding']);
  if (primary.isNotEmpty) out.add(primary);

  final templates = m['faceTemplates'];
  if (templates is List) {
    for (final t in templates) {
      if (t is Map) {
        final e = _coerceEmbeddingList(t['embedding']);
        if (e.isNotEmpty) out.add(e);
      } else if (t is List) {
        final e = _coerceEmbeddingList(t);
        if (e.isNotEmpty) out.add(e);
      }
    }
  }

  return out;
}

/// Append one embedding sample to an existing enrollment payload (5–10 samples).
Map<String, dynamic> appendFaceTemplateToPayload(
  dynamic existingField,
  List<double> embedding, {
  String model = ProductionFaceRecognitionConstants.modelMobileFaceNet,
  String? pose,
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  final sample = <String, dynamic>{
    'embedding': embedding,
    'model': model,
    'captured_at': now,
  };
  if (pose != null && pose.isNotEmpty) {
    sample['pose'] = pose;
  }

  if (existingField == null) {
    return {
      'embedding': embedding,
      'faceTemplates': [sample],
      'version': 3,
      'model': model,
      'updated_at': now,
    };
  }

  Map<String, dynamic> base;
  if (existingField is Map) {
    base = Map<String, dynamic>.from(existingField);
  } else if (existingField is String) {
    try {
      final decoded = jsonDecode(existingField);
      base = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      base = <String, dynamic>{};
    }
  } else {
    base = <String, dynamic>{};
  }

  final templates = <Map<String, dynamic>>[];
  final existingTemplates = base['faceTemplates'];
  if (existingTemplates is List) {
    for (final t in existingTemplates) {
      if (t is Map) templates.add(Map<String, dynamic>.from(t));
    }
  }
  templates.add(sample);

  while (templates.length >
      ProductionFaceRecognitionConstants.enrollmentMaxSamples) {
    templates.removeAt(0);
  }

  base['faceTemplates'] = templates;
  if (base['embedding'] == null && embedding.isNotEmpty) {
    base['embedding'] = embedding;
  }
  base['version'] = 3;
  base['model'] = model;
  base['updated_at'] = now;
  return base;
}

/// Replace enrollment with exactly 3 angle templates (front / left / right).
Map<String, dynamic> buildTripleAngleEnrollmentPayload(
  List<({List<double> embedding, String pose})> samples,
) {
  assert(samples.isNotEmpty);
  final now = DateTime.now().toUtc().toIso8601String();
  final templates = samples
      .map(
        (s) => {
          'embedding': s.embedding,
          'pose': s.pose,
          'model': ProductionFaceRecognitionConstants.modelMobileFaceNet,
          'captured_at': now,
        },
      )
      .toList();
  return {
    'embedding': samples.first.embedding,
    'faceTemplates': templates,
    'version': 3,
    'model': ProductionFaceRecognitionConstants.modelMobileFaceNet,
    'updated_at': now,
  };
}

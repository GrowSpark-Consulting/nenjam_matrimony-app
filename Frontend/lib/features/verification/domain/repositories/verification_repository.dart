import 'dart:io';

import '../models/verification_document.dart';

/// Pure abstract Dart interface for document-backed verification (income,
/// asset, government ID/Aadhaar, NRI). Concrete implementation lives in
/// `data/`. Mobile and email verification are NOT part of this contract —
/// they're reflections of the existing Firebase auth session
/// ([AuthUser.phoneVerified]/[AuthUser.emailVerified]), not documents a user
/// submits for review.
abstract interface class VerificationRepository {
  /// `GET /verification/status` — every document type's current status.
  Future<Map<VerificationDocumentType, VerificationDocumentRecord>> getStatuses();

  /// `POST /verification/documents` (multipart) — submits [file] as evidence
  /// for [type]. Returns the backend's freshly created record, which is
  /// always `PENDING` (or whatever the backend decides) — never
  /// client-declared `VERIFIED`.
  Future<VerificationDocumentRecord> submitDocument({
    required VerificationDocumentType type,
    required File file,
    void Function(int sent, int total)? onProgress,
  });
}

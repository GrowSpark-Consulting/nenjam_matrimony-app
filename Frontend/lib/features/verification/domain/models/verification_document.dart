/// Generic, extensible document-verification types. Each maps to one
/// upload-based verification card on the registration wizard's
/// Verification step. Adding a new document-backed verification type means
/// adding one enum value + one wire-format mapping here — everything else
/// (repository, provider, card UI) is generic over [VerificationDocumentType].
enum VerificationDocumentType {
  income,
  asset,
  aadhaar,
  nri;

  /// Backend wire format (matches the Nest `SubmitDocumentDto.type` the
  /// verification module is expected to accept once implemented).
  String get wireValue => switch (this) {
        VerificationDocumentType.income => 'INCOME',
        VerificationDocumentType.asset => 'ASSET',
        VerificationDocumentType.aadhaar => 'AADHAAR',
        VerificationDocumentType.nri => 'NRI',
      };

  static VerificationDocumentType? fromWire(String? value) =>
      switch (value?.toUpperCase()) {
        'INCOME' => VerificationDocumentType.income,
        'ASSET' => VerificationDocumentType.asset,
        'AADHAAR' => VerificationDocumentType.aadhaar,
        'NRI' => VerificationDocumentType.nri,
        _ => null,
      };
}

/// Backend-driven submission status. [uploading] and [failed] are
/// client-local only (an in-flight request / a network or upload error) and
/// never come back from the server — the server's source of truth is only
/// ever `NOT_SUBMITTED | PENDING | VERIFIED | REJECTED`. The frontend can
/// never self-declare [verified]; that value only ever arrives via
/// [VerificationDocumentRecord.fromJson].
enum VerificationSubmissionStatus {
  notSubmitted,
  uploading,
  pending,
  verified,
  rejected,
  failed;

  static VerificationSubmissionStatus fromWire(String? value) =>
      switch (value?.toUpperCase()) {
        'PENDING' => VerificationSubmissionStatus.pending,
        'VERIFIED' => VerificationSubmissionStatus.verified,
        'REJECTED' => VerificationSubmissionStatus.rejected,
        _ => VerificationSubmissionStatus.notSubmitted,
      };
}

/// One verification type's current status, as reported by (or pending
/// confirmation from) the backend.
class VerificationDocumentRecord {
  final VerificationDocumentType type;
  final VerificationSubmissionStatus status;
  final String? rejectionReason;
  final DateTime? submittedAt;

  const VerificationDocumentRecord({
    required this.type,
    this.status = VerificationSubmissionStatus.notSubmitted,
    this.rejectionReason,
    this.submittedAt,
  });

  bool get isVerified => status == VerificationSubmissionStatus.verified;
  bool get isBusy => status == VerificationSubmissionStatus.uploading;

  VerificationDocumentRecord copyWith({
    VerificationSubmissionStatus? status,
    String? rejectionReason,
    bool clearRejectionReason = false,
    DateTime? submittedAt,
  }) {
    return VerificationDocumentRecord(
      type: type,
      status: status ?? this.status,
      rejectionReason:
          clearRejectionReason ? null : (rejectionReason ?? this.rejectionReason),
      submittedAt: submittedAt ?? this.submittedAt,
    );
  }

  factory VerificationDocumentRecord.fromJson(Map<String, dynamic> json) {
    final type = VerificationDocumentType.fromWire(json['type'] as String?);
    return VerificationDocumentRecord(
      type: type ?? VerificationDocumentType.income,
      status: VerificationSubmissionStatus.fromWire(json['status'] as String?),
      rejectionReason: json['rejectionReason'] as String?,
      submittedAt: switch (json['submittedAt']) {
        final String s => DateTime.tryParse(s),
        _ => null,
      },
    );
  }
}

/// Nenjam Matrimony — Generic API Response Wrapper
///
/// Standardized response structure that wraps all API responses
/// for consistent error handling and data parsing.
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  final ApiError? error;
  final PaginationMeta? pagination;

  const ApiResponse({
    required this.success,
    this.data,
    this.message,
    this.error,
    this.pagination,
  });

  /// Factory for successful responses.
  factory ApiResponse.success({
    T? data,
    String? message,
    PaginationMeta? pagination,
  }) =>
      ApiResponse(
        success: true,
        data: data,
        message: message,
        pagination: pagination,
      );

  /// Factory for error responses.
  factory ApiResponse.failure({
    String? message,
    ApiError? error,
  }) =>
      ApiResponse(
        success: false,
        message: message,
        error: error,
      );

  /// Parse from JSON with a data parser function.
  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic json)? dataParser,
  ) {
    return ApiResponse(
      success: json['success'] as bool? ?? false,
      data: json['data'] != null && dataParser != null
          ? dataParser(json['data'])
          : null,
      message: json['message'] as String?,
      error: json['error'] != null
          ? ApiError.fromJson(json['error'] as Map<String, dynamic>)
          : null,
      pagination: json['pagination'] != null
          ? PaginationMeta.fromJson(
              json['pagination'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  bool get hasData => success && data != null;
  bool get hasError => !success || error != null;
}

/// API error details.
class ApiError {
  final int? code;
  final String message;
  final Map<String, List<String>>? validationErrors;

  const ApiError({
    this.code,
    required this.message,
    this.validationErrors,
  });

  factory ApiError.fromJson(Map<String, dynamic> json) => ApiError(
        code: json['code'] as int?,
        message: json['message'] as String? ?? 'Unknown error',
        validationErrors: json['errors'] != null
            ? (json['errors'] as Map<String, dynamic>).map(
                (key, value) => MapEntry(
                  key,
                  (value as List<dynamic>).cast<String>(),
                ),
              )
            : null,
      );
}

/// Pagination metadata for list endpoints.
class PaginationMeta {
  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;

  const PaginationMeta({
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
  });

  factory PaginationMeta.fromJson(Map<String, dynamic> json) =>
      PaginationMeta(
        currentPage: json['current_page'] as int? ?? 1,
        lastPage: json['last_page'] as int? ?? 1,
        perPage: json['per_page'] as int? ?? 20,
        total: json['total'] as int? ?? 0,
      );

  bool get hasNextPage => currentPage < lastPage;
  bool get hasPreviousPage => currentPage > 1;
}

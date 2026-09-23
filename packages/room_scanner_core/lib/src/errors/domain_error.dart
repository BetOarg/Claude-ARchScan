enum DomainErrorCode {
  invalidMeasurement,
  invalidExportGeometry,
}

/// Typed domain failure that preserves ArgumentError compatibility at API
/// boundaries while exposing a stable machine-readable error code.
class DomainError extends ArgumentError {
  final DomainErrorCode code;

  DomainError(this.code, String message) : super(message);
}

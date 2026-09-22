import 'package:room_scanner_core/room_scanner_core.dart';

import '../l10n/generated/app_localizations.dart';

String validationErrorMessage(
  ValidationResult result,
  AppLocalizations l10n, {
  required String fallback,
}) {
  switch (result.errorCode) {
    case ValidationErrorCode.tooCloseToPreviousPoint:
      return l10n.validationTooCloseToPreviousPoint;
    case ValidationErrorCode.duplicatePoint:
      return l10n.validationDuplicatePoint;
    case ValidationErrorCode.selfIntersection:
      return l10n.validationSelfIntersection;
    case ValidationErrorCode.insufficientCorners:
      return l10n.validationInsufficientCorners;
    case ValidationErrorCode.insufficientArea:
      return l10n.validationInsufficientArea;
    case ValidationErrorCode.invalidGeometry:
      return l10n.validationInvalidGeometry;
    case null:
      return fallback;
  }
}

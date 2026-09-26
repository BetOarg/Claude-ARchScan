/// Public entry point for the Scanner feature.
///
/// This is the first compatibility seam of the Feature-first migration.
/// Concrete implementations remain in the existing scanner tree until each
/// responsibility has been migrated and verified independently.
library;

export '../../scanner/adapters/ar_scanner_adapter.dart';
export '../../scanner/adapters/basic_scanner_adapter.dart';
export '../../scanner/engine/scanner_adapter.dart';
export '../../scanner/engine/scanner_engine.dart';
export '../../scanner/engine/scanner_mode_resolver.dart';
export '../../scanner/factories/scanner_factory.dart';
export '../../scanner/models/scanner_mode.dart';
export '../../scanner/models/scanner_point.dart';
export '../../scanner/models/scanner_sensor_state.dart';
export '../../scanner/navigation/scanner_launch_request.dart';

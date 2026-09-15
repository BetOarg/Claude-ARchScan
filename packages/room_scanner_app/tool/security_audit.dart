import 'dart:io';

void main() {
  final root = _findRepositoryRoot();
  final errors = <String>[];

  _scanForSecrets(root, errors);
  _verifyPermissions(root, errors);
  _verifyBranding(root, errors);

  for (final error in errors) {
    stderr.writeln('ERROR: $error');
  }

  if (errors.isNotEmpty) {
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Auditoría de secretos, permisos, almacenamiento local y marca completada.',
  );
}

Directory _findRepositoryRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    if (Directory('${directory.path}/packages').existsSync() &&
        Directory('${directory.path}/.github').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('No se encontró la raíz del repositorio.');
    }
    directory = parent;
  }
}

void _scanForSecrets(Directory root, List<String> errors) {
  const ignoredSegments = {
    '.git',
    '.dart_tool',
    'build',
    'Pods',
    '.symlinks',
  };
  const textExtensions = {
    '.dart',
    '.yaml',
    '.yml',
    '.json',
    '.md',
    '.txt',
    '.xml',
    '.plist',
    '.xcconfig',
    '.gradle',
    '.kt',
    '.swift',
    '.ts',
    '.sql',
    '.properties',
    '.arb',
    '.xcprivacy',
    '.pbxproj',
    '.html',
    '.sh',
  };
  const forbiddenBinaryExtensions = {
    '.jks',
    '.keystore',
    '.p12',
    '.p8',
    '.mobileprovision',
    '.b64',
  };
  final patterns = <MapEntry<String, RegExp>>[
    MapEntry(
      'clave privada',
      RegExp(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    ),
    MapEntry(
      'token de GitHub',
      RegExp(r'gh[pousr]_[A-Za-z0-9]{20,}'),
    ),
    MapEntry(
      'clave de acceso AWS',
      RegExp(r'AKIA[0-9A-Z]{16}'),
    ),
    MapEntry(
      'JWT incorporado',
      RegExp(r'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}'),
    ),
  ];

  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;

    final relative = entity.path
        .substring(root.path.length + 1)
        .replaceAll('\\', '/');
    final segments = relative.split('/');
    if (segments.any(ignoredSegments.contains)) continue;

    final lower = relative.toLowerCase();
    final extension = lower.contains('.')
        ? lower.substring(lower.lastIndexOf('.'))
        : '';

    if (forbiddenBinaryExtensions.contains(extension)) {
      const allowedTestKey =
          '.github/signing/room-scanner-test.keystore.b64';
      if (relative != allowedTestKey) {
        errors.add('Archivo sensible versionado: $relative.');
      }
      continue;
    }

    if (relative.endsWith('.env') ||
        (relative.contains('.env.') &&
            !relative.endsWith('.example'))) {
      errors.add('Archivo de entorno real versionado: $relative.');
      continue;
    }

    if (!textExtensions.contains(extension)) continue;

    String content;
    try {
      content = entity.readAsStringSync();
    } on FileSystemException {
      continue;
    }

    for (final pattern in patterns) {
      if (pattern.value.hasMatch(content)) {
        errors.add(
          'Posible ${pattern.key} incorporada en $relative.',
        );
      }
    }
  }
}

void _verifyPermissions(Directory root, List<String> errors) {
  final manifest = File(
    '${root.path}/packages/room_scanner_app/android/app/src/main/'
    'AndroidManifest.xml',
  ).readAsStringSync();
  if (!manifest.contains(
    '<uses-permission android:name="android.permission.CAMERA" />',
  )) {
    errors.add('Falta el permiso funcional de cámara en Android.');
  }
  for (final permission in [
    'android.permission.RECORD_AUDIO',
    'android.permission.INTERNET',
  ]) {
    final removalPattern = RegExp(
      '<uses-permission\\s+android:name="$permission"\\s+'
      'tools:node="remove"\\s*/>',
      multiLine: true,
    );
    if (!removalPattern.hasMatch(manifest)) {
      errors.add(
        '$permission debe eliminarse explícitamente del manifiesto fusionado.',
      );
    }
  }

  if (!manifest.contains(
        'android.hardware.camera" android:required="false"',
      ) ||
      !manifest.contains(
        'android.hardware.camera.ar" android:required="false"',
      )) {
    errors.add('Las capacidades de cámara/AR deben ser opcionales.');
  }

  final infoPlist = File(
    '${root.path}/packages/room_scanner_app/ios/Runner/Info.plist',
  ).readAsStringSync();
  if (!infoPlist.contains('<key>NSCameraUsageDescription</key>')) {
    errors.add('Falta NSCameraUsageDescription en iOS.');
  }
  for (final forbidden in [
    'NSLocationWhenInUseUsageDescription',
    'NSLocationAlwaysUsageDescription',
    'NSUserTrackingUsageDescription',
  ]) {
    if (infoPlist.contains(forbidden)) {
      errors.add('Permiso iOS no esperado: $forbidden.');
    }
  }

  final privacyManifest = File(
    '${root.path}/packages/room_scanner_app/ios/Runner/'
    'PrivacyInfo.xcprivacy',
  ).readAsStringSync();
  if (!privacyManifest.contains(
    '<key>NSPrivacyTracking</key>\n\t<false/>',
  )) {
    errors.add('PrivacyInfo.xcprivacy debe declarar tracking desactivado.');
  }
}

void _verifyBranding(Directory root, List<String> errors) {
  for (final locale in ['app_es.arb', 'app_en.arb']) {
    final file = File(
      '${root.path}/packages/room_scanner_app/lib/l10n/$locale',
    );
    final content = file.readAsStringSync();
    if (!content.contains('"appTitle": "ARchScan"')) {
      errors.add('$locale no utiliza ARchScan como título.');
    }
    if (content.contains('Claude Room Scanner')) {
      errors.add('$locale contiene la marca anterior.');
    }
  }
}

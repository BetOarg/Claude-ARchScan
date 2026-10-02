import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/l10n/generated/app_localizations.dart';
import 'package:room_scanner_ar/main.dart';
import 'package:room_scanner_ar/providers/measurement_settings_provider.dart';
import 'package:room_scanner_ar/widgets/room_completion_dialog.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required Size size,
    required Locale locale,
    double textScale = 1.3,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          );
        },
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showRoomCompletionDialog(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'el diálogo se adapta a pantalla angosta en español',
    (tester) async {
      await pumpDialog(
        tester,
        size: const Size(320, 568),
        locale: const Locale('es'),
      );

      expect(find.text('Espacio guardado'), findsOneWidget);
      expect(find.text('Agregar otro espacio'), findsOneWidget);
      expect(find.text('Ver plano completo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'el diálogo se adapta a orientación horizontal en inglés',
    (tester) async {
      await pumpDialog(
        tester,
        size: const Size(568, 320),
        locale: const Locale('en'),
      );

      expect(find.text('Space saved'), findsOneWidget);
      expect(find.text('Add another space'), findsOneWidget);
      expect(find.text('View full floor plan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'el diálogo conserva sus acciones con texto al 200 por ciento',
    (tester) async {
      await pumpDialog(
        tester,
        size: const Size(320, 568),
        locale: const Locale('es'),
        textScale: 2.0,
      );

      expect(find.text('Espacio guardado'), findsOneWidget);
      expect(find.text('Agregar otro espacio'), findsOneWidget);
      expect(find.text('Ver plano completo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'muestra una interfaz desde el primer cuadro durante el inicio',
    (tester) async {
      final initialization =
          Completer<MeasurementSettingsProvider>();

      await tester.pumpWidget(
        RoomScannerBootstrap(
          initializer: () => initialization.future,
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('ARchScan'), findsOneWidget);
      expect(find.text('Starting ARchScan…'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Completa el tiempo mínimo del splash sin resolver el inicializador.
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'ofrece un reintento seguro cuando falla el inicio',
    (tester) async {
      var attempts = 0;

      await tester.pumpWidget(
        RoomScannerBootstrap(
          initializer: () async {
            attempts++;
            throw StateError('temporary startup failure');
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('The application could not start'), findsOneWidget);
      expect(find.text('Retry startup'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Retry startup'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(find.text('The application could not start'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

import 'l10n/generated/app_localizations.dart';
import 'providers/floor_plan_provider.dart';
import 'providers/measurement_settings_provider.dart';
import 'providers/project_provider.dart';
import 'providers/scanner_provider.dart';
import 'screens/dashboard_screen.dart';
import 'features/scanner/scanner_feature.dart';
import 'widgets/archscan_logo.dart';

typedef RoomScannerInitializer =
    Future<MeasurementSettingsProvider> Function();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureScannerComposition();
  runApp(const RoomScannerBootstrap());
}

/// Muestra una interfaz Flutter desde el primer cuadro mientras se preparan
/// los servicios que antes bloqueaban [runApp].
class RoomScannerBootstrap extends StatefulWidget {
  final RoomScannerInitializer? initializer;

  const RoomScannerBootstrap({
    super.key,
    this.initializer,
  });

  @override
  State<RoomScannerBootstrap> createState() =>
      _RoomScannerBootstrapState();
}

class _RoomScannerBootstrapState
    extends State<RoomScannerBootstrap> {
  static const _minimumSplashDuration = Duration(milliseconds: 900);

  late Future<MeasurementSettingsProvider> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _beginInitialization();
  }

  Future<MeasurementSettingsProvider> _beginInitialization() {
    final initialization =
        _initializeWithMinimumSplash();

    // El reintento puede completar antes de que FutureBuilder reconstruya
    // y se suscriba a la nueva operación. Se registra inmediatamente un
    // manejador sin consumir el resultado que seguirá mostrando la interfaz.
    initialization.ignore();
    return initialization;
  }

  Future<MeasurementSettingsProvider> _initializeWithMinimumSplash() async {
    final services = Future<MeasurementSettingsProvider>.sync(_initialize);
    final minimumDisplay = Future<void>.delayed(_minimumSplashDuration);

    await Future.wait<void>([
      services.then<void>((_) {}),
      minimumDisplay,
    ]);
    return services;
  }

  Future<MeasurementSettingsProvider> _initialize() {
    return widget.initializer?.call() ?? _initializeProductionServices();
  }

  Future<MeasurementSettingsProvider>
      _initializeProductionServices() async {
    final measurementSettingsProvider =
        MeasurementSettingsProvider();
    await measurementSettingsProvider.load();
    return measurementSettingsProvider;
  }

  void _retry() {
    final initialization = _beginInitialization();

    setState(() {
      _initialization = initialization;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MeasurementSettingsProvider>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return _buildReadyApplication(snapshot.data!);
        }

        return _buildBootstrapApplication(
          failed: snapshot.hasError,
        );
      },
    );
  }

  Widget _buildBootstrapApplication({
    required bool failed,
  }) {
    return MaterialApp(
      onGenerateTitle: (context) =>
          AppLocalizations.of(context)!.appTitle,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: _applicationTheme(),
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context)!;

          return Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (failed)
                          const Icon(
                            Icons.error_outline,
                            size: 72,
                            color: Colors.orangeAccent,
                          )
                        else
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const ArchScanLogo(size: 180),
                              const SizedBox(height: 18),
                              Text(
                                'ARchScan',
                                style: Theme.of(context)
                                    .textTheme
                                    .displaySmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -1.2,
                                    ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 24),
                        if (failed) ...[
                          Text(
                            l10n.applicationInitializationFailed,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.applicationInitializationFailedDetails,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _retry,
                            icon: const Icon(Icons.refresh),
                            label: Text(l10n.retryApplicationStart),
                          ),
                        ] else ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 20),
                          Text(
                            l10n.initializingApplication,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReadyApplication(
    MeasurementSettingsProvider measurementSettingsProvider,
  ) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProjectProvider()),
        ChangeNotifierProvider.value(
          value: measurementSettingsProvider,
        ),
        ChangeNotifierProxyProvider<
            MeasurementSettingsProvider,
            ScannerProvider>(
          create: (_) => ScannerProvider(),
          update: (
            _,
            settingsProvider,
            scannerProvider,
          ) {
            final provider =
                scannerProvider ?? ScannerProvider();
            provider.measurementSystem = settingsProvider.system;
            return provider;
          },
        ),
        ChangeNotifierProxyProvider2<
            ProjectProvider,
            MeasurementSettingsProvider,
            FloorPlanProvider>(
          create: (_) => FloorPlanProvider(),
          update: (
            _,
            projectProvider,
            settingsProvider,
            floorPlanProvider,
          ) {
            final provider =
                floorPlanProvider ?? FloorPlanProvider();
            provider.measurementSystem = settingsProvider.system;
            provider.persister = ({
              required String uuid,
              required String name,
              required List<RoomModel> rooms,
            }) =>
                projectProvider.saveCurrentProject(
              uuid: uuid,
              name: name,
              rooms: rooms,
            );
            return provider;
          },
        ),
      ],
      child: RoomScannerApp(),
    );
  }
}

class RoomScannerApp extends StatelessWidget {
  const RoomScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) =>
          AppLocalizations.of(context)!.appTitle,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: _applicationTheme(),
      home: const DashboardScreen(),
    );
  }
}

ThemeData _applicationTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF10C7BE),
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
    fontFamily: 'Manrope',
  );
}

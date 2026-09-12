import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers/project_provider.dart';
import '../providers/floor_plan_provider.dart';
import '../providers/scanner_provider.dart';

class PrivacyAccountScreen extends StatefulWidget {
  const PrivacyAccountScreen({super.key});

  @override
  State<PrivacyAccountScreen> createState() =>
      _PrivacyAccountScreenState();
}

class _PrivacyAccountScreenState extends State<PrivacyAccountScreen> {
  bool _isDeleting = false;

  Future<void> _deleteLocalProjects() async {
    final localizations = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.deleteLocalDataConfirmationTitle),
        content: Text(localizations.deleteLocalDataConfirmationMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(localizations.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(localizations.deleteLocalDataPermanently),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await context.read<ProjectProvider>().deleteAllLocalProjects();
      if (!mounted) return;
      context.read<FloorPlanProvider>().clearProject();
      context.read<ScannerProvider>().loadRooms(const []);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.localDataDeleted)),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.fileSaveFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(localizations.privacyAndData)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _PrivacySection(
              icon: Icons.privacy_tip_outlined,
              title: localizations.privacyOverview,
              description: localizations.privacyOverviewLocalDescription,
            ),
            _PrivacySection(
              icon: Icons.phone_android_outlined,
              title: localizations.localDataTitle,
              description: localizations.localOnlyDataDescription,
            ),
            _PrivacySection(
              icon: Icons.camera_alt_outlined,
              title: localizations.cameraAndSensorsTitle,
              description: localizations.cameraAndSensorsDescription,
            ),
            _PrivacySection(
              icon: Icons.file_present_outlined,
              title: localizations.exportsAndSharingTitle,
              description: localizations.exportsAndSharingDescription,
            ),
            _PrivacySection(
              icon: Icons.visibility_off_outlined,
              title: localizations.trackingTitle,
              description: localizations.trackingDescription,
            ),
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      localizations.deleteLocalDataTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(localizations.deleteLocalDataDescription),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isDeleting ? null : _deleteLocalProjects,
                      icon: _isDeleting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_forever_outlined),
                      label: Text(
                        _isDeleting
                            ? localizations.deletingLocalData
                            : localizations.deleteAllLocalData,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _PrivacySection({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(description),
        ),
      ),
    );
  }
}

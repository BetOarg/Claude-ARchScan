import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers/project_provider.dart';
import '../providers/floor_plan_provider.dart';
import '../providers/scanner_provider.dart';
import '../services/ar_check_service.dart';
import '../widgets/archscan_logo.dart';
import 'floor_plan_viewer_screen.dart';
import 'privacy_account_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProjectProvider>().init();
    });
  }

  void _showNewProjectDialog(
    BuildContext context,
  ) {
    final localizations = AppLocalizations.of(context)!;
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          localizations.newProject,
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: localizations.projectNameExample,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(localizations.cancel),
          ),
          ElevatedButton(
            onPressed: () => _createProject(
              ctx,
              controller.text.trim(),
            ),
            child: Text(localizations.create),
          ),
        ],
      ),
    );
  }

  Future<void> _createProject(
    BuildContext dialogContext,
    String name,
  ) async {
    if (name.isEmpty) {
      return;
    }

    Navigator.pop(dialogContext);

    final uuid = DateTime.now().millisecondsSinceEpoch.toString();

    await context.read<ProjectProvider>().saveCurrentProject(
      uuid: uuid,
      name: name,
      rooms: const [],
    );

    if (!mounted) {
      return;
    }

    context.read<FloorPlanProvider>().loadProject(
      uuid: uuid,
      name: name,
      rooms: const [],
    );

    context.read<ScannerProvider>().loadRooms(const []);

    await ArCheckService.abrirEscanerConValidacion(
      context,
      projectUuid: uuid,
      projectName: name,
    );
  }

  Future<void> _openProject(
    IsarProject project,
  ) async {
    final provider = context.read<ProjectProvider>();

    final rooms = await provider.selectProject(
      project,
    );

    if (!mounted) {
      return;
    }

    context.read<FloorPlanProvider>().loadProject(
          uuid: project.uuid,
          name: project.name,
          rooms: rooms,
        );

    context.read<ScannerProvider>().loadRooms(rooms);

    await ArCheckService.abrirEscanerConValidacion(
      context,
      projectUuid: project.uuid,
      projectName: project.name,
    );
  }

  Future<void> _viewFloorPlan(
    IsarProject project,
  ) async {
    final provider = context.read<ProjectProvider>();

    final rooms = await provider.selectProject(
      project,
    );

    if (!mounted) {
      return;
    }

    context.read<FloorPlanProvider>().loadProject(
          uuid: project.uuid,
          name: project.name,
          rooms: rooms,
        );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const FloorPlanViewerScreen(),
      ),
    );
  }

  Future<void> _openPrivacyAndAccount() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PrivacyAccountScreen(),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final provider = context.watch<ProjectProvider>();

    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: const ArchScanLogo(
          size: 34,
          showWordmark: true,
        ),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.privacy_tip_outlined,
            ),
            tooltip: localizations.privacyAndAccount,
            onPressed: _openPrivacyAndAccount,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(
                  Icons.phone_android_outlined,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Text(
                    localizations.localProjectsStoredOnDevice,
                    style: const TextStyle(
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: provider.isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : provider.projects.isEmpty
                    ? _buildEmptyState()
                    : _buildProjectList(
                        provider,
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewProjectDialog(
          context,
        ),
        icon: const Icon(Icons.add),
        label: Text(
          localizations.newScan,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final localizations = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const ArchScanLogo(size: 88),
          const SizedBox(
            height: 16,
          ),
          Text(
            localizations.noSavedProjects,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          Text(
            localizations.pressNewScanToStart,
          ),
        ],
      ),
    );
  }

  Widget _buildProjectList(
    ProjectProvider provider,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.projects.length,
      itemBuilder: (context, index) {
        final localizations = AppLocalizations.of(context)!;
        final project = provider.projects[index];

        return Card(
          margin: const EdgeInsets.only(
            bottom: 12,
          ),
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(
                Icons.meeting_room,
              ),
            ),
            title: Text(
              project.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              localizations.projectUpdated(
                '${project.updatedAt.day}/'
                '${project.updatedAt.month}/'
                '${project.updatedAt.year}',
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.map_outlined,
                  ),
                  tooltip: localizations.viewFloorPlan,
                  onPressed: () => _viewFloorPlan(
                    project,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                  ),
                  tooltip: localizations.delete,
                  onPressed: () async {
                    await provider.deleteProject(
                      project.uuid,
                    );
                  },
                ),
              ],
            ),
            onTap: () => _openProject(
              project,
            ),
          ),
        );
      },
    );
  }
}

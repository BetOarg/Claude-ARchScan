import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers/project_provider.dart';
import '../providers/floor_plan_provider.dart';
import '../providers/scanner_provider.dart';
import '../services/ar_check_service.dart';
import '../services/import_export_service.dart';
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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await context.read<ProjectProvider>().init();
      } catch (_) {
        if (mounted) {
          _showOperationError();
        }
      }
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

    try {
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

      if (mounted) {
        await context.read<ProjectProvider>().loadProjects();
      }
    } catch (_) {
      if (mounted) {
        _showOperationError();
      }
    }
  }

  void _showOperationError() {
    final localizations = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(localizations.unknownError),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<bool> _confirmDeleteProject(ProjectRecord project) async {
    final localizations = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.deleteProjectConfirmationTitle),
        content: Text(
          localizations.deleteProjectConfirmationMessage(project.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(localizations.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(localizations.delete),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _renameProject(ProjectRecord project) async {
    final localizations = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: project.name);

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.rename),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: localizations.projectNameExample,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(
            dialogContext,
            value.trim(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(localizations.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text.trim(),
            ),
            child: Text(localizations.rename),
          ),
        ],
      ),
    );

    controller.dispose();

    if (!mounted || name == null || name.trim().isEmpty) {
      return;
    }

    try {
      await context.read<ProjectProvider>().renameProject(
        uuid: project.uuid,
        name: name,
      );
    } catch (_) {
      if (mounted) {
        _showOperationError();
      }
    }
  }

  Future<void> _openProject(
    ProjectRecord project,
  ) async {
    final provider = context.read<ProjectProvider>();

    try {
      final rooms = await provider.selectProject(project);

      if (!mounted) return;

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

      if (mounted) {
        await provider.loadProjects();
      }
    } catch (_) {
      if (mounted) _showOperationError();
    }
  }

  Future<void> _viewFloorPlan(
    ProjectRecord project,
  ) async {
    final provider = context.read<ProjectProvider>();

    try {
      final rooms = await provider.selectProject(project);

      if (!mounted) return;

      context.read<FloorPlanProvider>().loadProject(
        uuid: project.uuid,
        name: project.name,
        rooms: rooms,
      );

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const FloorPlanViewerScreen(),
        ),
      );
    } catch (_) {
      if (mounted) _showOperationError();
    }
  }

  Future<void> _openPrivacyAndAccount() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PrivacyAccountScreen(),
      ),
    );
  }

  Future<void> _importProjectFromHome() async {
    final localizations = AppLocalizations.of(context)!;
    final floorPlanProvider = context.read<FloorPlanProvider>();
    final uuid = DateTime.now().microsecondsSinceEpoch.toString();

    JsonImportResult result;
    try {
      result = await ImportExportService.importProject(
        floorPlanProvider,
        newProjectUuid: uuid,
        confirmReplacement: () async => true,
      );
    } catch (_) {
      if (mounted) _showOperationError();
      return;
    }

    if (!mounted || result == JsonImportResult.cancelled) {
      return;
    }

    if (result == JsonImportResult.imported) {
      try {
        await context.read<ProjectProvider>().loadProjects();
      } catch (_) {
        if (mounted) {
          _showOperationError();
        }
        return;
      }
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == JsonImportResult.imported
              ? localizations.planImportedSuccessfully
              : localizations.planImportCancelledOrInvalid,
        ),
      ),
    );
  }

  Future<void> _exportProjectFromHome() async {
    final provider = context.read<ProjectProvider>();
    if (provider.projects.isEmpty) return;

    final project = await showDialog<ProjectRecord>(
      context: context,
      builder: (dialogContext) {
        final localizations = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(localizations.exportProject),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: provider.projects.length,
              itemBuilder: (context, index) {
                final project = provider.projects[index];
                return ListTile(
                  leading: const Icon(Icons.map_outlined),
                  title: Text(
                    project.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(dialogContext, project),
                );
              },
            ),
          ),
        );
      },
    );

    if (!mounted || project == null) return;

    try {
      final rooms = await provider.selectProject(project);
      if (!mounted) return;

      context.read<FloorPlanProvider>().loadProject(
        uuid: project.uuid,
        name: project.name,
        rooms: rooms,
      );
      context.read<ScannerProvider>().loadRooms(rooms);

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const FloorPlanViewerScreen(
            openExportOnLoad: true,
          ),
        ),
      );
    } catch (_) {
      if (mounted) _showOperationError();
    }
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
          PopupMenuButton<_DashboardFileAction>(
            tooltip: localizations.moreOptions,
            icon: const Icon(Icons.folder_open_outlined),
            onSelected: (action) {
              switch (action) {
                case _DashboardFileAction.importProject:
                  _importProjectFromHome();
                  break;
                case _DashboardFileAction.exportProject:
                  _exportProjectFromHome();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _DashboardFileAction.importProject,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.file_upload_outlined),
                  title: Text(localizations.importProject),
                ),
              ),
              PopupMenuItem(
                value: _DashboardFileAction.exportProject,
                enabled: provider.projects.isNotEmpty,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.file_download_outlined),
                  title: Text(localizations.exportProject),
                ),
              ),
            ],
          ),
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
                PopupMenuButton<_ProjectAction>(
                  tooltip: localizations.actions,
                  onSelected: (action) async {
                    switch (action) {
                      case _ProjectAction.rename:
                        await _renameProject(project);
                        break;
                      case _ProjectAction.delete:
                        if (await _confirmDeleteProject(project)) {
                          try {
                            await provider.deleteProject(project.uuid);
                          } catch (_) {
                            if (mounted) _showOperationError();
                          }
                        }
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _ProjectAction.rename,
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.edit_outlined),
                        title: Text(localizations.rename),
                      ),
                    ),
                    PopupMenuItem(
                      value: _ProjectAction.delete,
                      child: ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        title: Text(localizations.delete),
                      ),
                    ),
                  ],
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


enum _ProjectAction { rename, delete }

enum _DashboardFileAction {
  importProject,
  exportProject,
}

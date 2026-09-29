import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

import '../services/scan_draft_service.dart';

class ProjectProvider with ChangeNotifier {
  final ProjectRepository _repository = DriftProjectRepository();

  List<ProjectRecord> _projects = [];
  ProjectRecord? _currentProject;
  bool _isLoading = false;
  Future<void> _mutations = Future<void>.value();
  final Set<String> _deletedIds = <String>{};

  Future<void> _serialize(Future<void> Function() action) {
    final result = _mutations.then((_) => action());
    _mutations = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  List<ProjectRecord> get projects => _projects;
  ProjectRecord? get currentProject => _currentProject;
  bool get isLoading => _isLoading;

  Future<void> init() async {
    _setLoading(true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      await _repository.init(directoryPath: dir.path);
      await loadProjects();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadProjects() async {
    _projects = await _repository.getAllProjects();
    notifyListeners();
  }

  Future<void> saveCurrentProject({
    required String uuid,
    required String name,
    required List<RoomModel> rooms,
  }) async {
    return _serialize(() async {
      _setLoading(true);
      try {
        if (_deletedIds.contains(uuid)) {
          throw StateError('Project was deleted.');
        }
        await _repository.saveProject(
          uuid: uuid,
          name: name,
          rooms: rooms,
        );
        await loadProjects();
      } finally {
        _setLoading(false);
      }
    });
  }

  Future<List<RoomModel>> selectProject(ProjectRecord project) async {
    final rooms = await _repository.getRoomsForProject(project.uuid);
    _currentProject = project;
    notifyListeners();
    return rooms;
  }

  Future<void> renameProject({
    required String uuid,
    required String name,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return;

    return _serialize(() async {
      _setLoading(true);
      try {
        if (_deletedIds.contains(uuid)) {
          throw StateError('Project was deleted.');
        }

        final rooms = await _repository.getRoomsForProject(uuid);
        await _repository.saveProject(
          uuid: uuid,
          name: trimmedName,
          rooms: rooms,
        );

        await loadProjects();

        for (final project in _projects) {
          if (project.uuid == uuid) {
            _currentProject = project;
            break;
          }
        }
        notifyListeners();
      } finally {
        _setLoading(false);
      }
    });
  }

  Future<void> deleteProject(String uuid) async {
    _deletedIds.add(uuid);
    return _serialize(() async {
      _setLoading(true);
      try {
        await _repository.deleteProject(uuid);
        await const ScanDraftService().clear(
          uuid,
          permanentlyDeleted: true,
        );
        if (_currentProject?.uuid == uuid) {
          _currentProject = null;
        }
        await loadProjects();
      } finally {
        _setLoading(false);
      }
    });
  }

  Future<void> deleteAllLocalProjects() async {
    _deletedIds.addAll(_projects.map((project) => project.uuid));
    return _serialize(() async {
      _setLoading(true);
      try {
        final projectIds = _projects
            .map((project) => project.uuid)
            .toList(growable: false);

        for (final projectId in projectIds) {
          await _repository.deleteProject(projectId);
        }

        for (final projectId in projectIds) {
          await const ScanDraftService().clear(
            projectId,
            permanentlyDeleted: true,
          );
        }
        await const ScanDraftService().clearAll();

        _projects = [];
        _currentProject = null;
      } finally {
        _setLoading(false);
      }
    });
  }

  @override
  void dispose() {
    final repository = _repository;
    if (repository is DriftProjectRepository) {
      unawaited(repository.dispose());
    }
    super.dispose();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}

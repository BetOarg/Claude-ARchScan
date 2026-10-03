import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

import '../services/scan_draft_service.dart';

class ProjectProvider with ChangeNotifier {
  ProjectProvider({ProjectRepository? repository})
      : _repository = repository ?? DriftProjectRepository();

  final ProjectRepository _repository;

  List<ProjectRecord> _projects = [];
  ProjectRecord? _currentProject;
  bool _isLoading = false;
  int _loadingOperations = 0;
  int _loadGeneration = 0;
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
    final generation = ++_loadGeneration;
    final projects = await _repository.getAllProjects();
    if (generation != _loadGeneration) return;
    _projects = projects;

    final currentUuid = _currentProject?.uuid;
    if (currentUuid != null) {
      ProjectRecord? refreshedCurrentProject;
      for (final project in projects) {
        if (project.uuid == currentUuid) {
          refreshedCurrentProject = project;
          break;
        }
      }
      _currentProject = refreshedCurrentProject;
    }

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

    ProjectRecord selectedProject = project;
    for (final candidate in _projects) {
      if (candidate.uuid == project.uuid) {
        selectedProject = candidate;
        break;
      }
    }

    _currentProject = selectedProject;
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
      } finally {
        _setLoading(false);
      }
    });
  }

  Future<void> deleteProject(String uuid) async {
    _deletedIds.add(uuid);
    return _serialize(() async {
      _setLoading(true);
      var repositoryDeleted = false;
      try {
        await _repository.deleteProject(uuid);
        repositoryDeleted = true;
        await const ScanDraftService().clear(
          uuid,
          permanentlyDeleted: true,
        );
        if (_currentProject?.uuid == uuid) {
          _currentProject = null;
        }
        await loadProjects();
      } finally {
        if (!repositoryDeleted) {
          _deletedIds.remove(uuid);
        }
        _setLoading(false);
      }
    });
  }

  Future<void> deleteAllLocalProjects() async {
    final projectIds = _projects
        .map((project) => project.uuid)
        .toList(growable: false);
    _deletedIds.addAll(projectIds);
    return _serialize(() async {
      _setLoading(true);
      final deletedIds = <String>{};
      try {
        for (final projectId in projectIds) {
          await _repository.deleteProject(projectId);
          deletedIds.add(projectId);
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
        _deletedIds
          ..removeWhere(
            (id) => projectIds.contains(id) && !deletedIds.contains(id),
          );
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
    if (value) {
      _loadingOperations += 1;
    } else if (_loadingOperations > 0) {
      _loadingOperations -= 1;
    }

    final nextValue = _loadingOperations > 0;
    if (_isLoading == nextValue) return;
    _isLoading = nextValue;
    notifyListeners();
  }
}

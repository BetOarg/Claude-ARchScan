import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';
import '../services/scan_draft_service.dart';

class ProjectProvider with ChangeNotifier {
  final LocalDatabaseService _dbService = LocalDatabaseService();

  List<IsarProject> _projects = [];
  IsarProject? _currentProject;
  bool _isLoading = false;

  List<IsarProject> get projects => _projects;
  IsarProject? get currentProject => _currentProject;
  bool get isLoading => _isLoading;

  /// Inicializa la base de datos y carga los proyectos guardados.
  ///
  /// `path_provider` (plugin de Flutter con canal nativo) vive acá: el
  /// core solo recibe el directorio ya resuelto, ver
  /// `LocalDatabaseService.init`.
  Future<void> init() async {
    _setLoading(true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      await _dbService.init(directoryPath: dir.path);
      await loadProjects();
    } finally {
      _setLoading(false);
    }
  }

  /// Carga la lista de proyectos desde Isar
  Future<void> loadProjects() async {
    _projects = await _dbService.getAllProjects();
    notifyListeners();
  }

  /// Crea o guarda un proyecto existente únicamente en el dispositivo.
  Future<void> saveCurrentProject({
    required String uuid,
    required String name,
    required List<RoomModel> rooms,
  }) async {
    _setLoading(true);

    try {
      await _dbService.saveProject(
        uuid: uuid,
        name: name,
        rooms: rooms,
      );

      await loadProjects();
    } finally {
      _setLoading(false);
    }
  }

  /// Carga un proyecto para trabajar en él
  Future<List<RoomModel>> selectProject(IsarProject project) async {
    final rooms = await _dbService.getRoomsForProject(project.uuid);
    _currentProject = project;
    notifyListeners();
    return rooms;
  }

  /// Elimina un proyecto por su UUID
  Future<void> deleteProject(String uuid) async {
    _setLoading(true);
    try {
      await _dbService.deleteProject(uuid);
      await const ScanDraftService().clear(uuid);
      if (_currentProject?.uuid == uuid) {
        _currentProject = null;
      }
      await loadProjects();
    } finally {
      _setLoading(false);
    }
  }

  /// Elimina del dispositivo todos los proyectos locales.
  Future<void> deleteAllLocalProjects() async {
    _setLoading(true);

    try {
      final projectIds = _projects
          .map((project) => project.uuid)
          .toList(growable: false);

      for (final projectId in projectIds) {
        await _dbService.deleteProject(projectId);
      }

      await const ScanDraftService().clearAll();

      _projects = [];
      _currentProject = null;
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}

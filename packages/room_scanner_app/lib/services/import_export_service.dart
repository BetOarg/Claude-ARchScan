import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as image_codec;
import 'package:path_provider/path_provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/floor_plan_provider.dart';

enum JsonImportResult {
  imported,
  cancelled,
  invalid,
}

enum ExportDestination { saveToFiles, share }

/// Capa de I/O de exportación/importación: selecciona ubicaciones externas y
/// archivos. Todo el cálculo (JSON, nombre de archivo,
/// SVG del plano, armado del PDF) vive en
/// `PlanExportBuilder` (`room_scanner_core`) y no se duplica acá.
class ImportExportService {
  /// Guarda el proyecto como JSON fuera del almacenamiento privado de la app.
  static Future<bool> exportToJson(
    List<RoomModel> rooms,
    String projectName, {
    ExportDestination destination = ExportDestination.saveToFiles,
    ui.Rect? sharePositionOrigin,
  }) async {
    final data = PlanExportBuilder.buildJsonData(rooms, projectName);
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    final fileName = PlanExportBuilder.buildJsonFileName(projectName);
    return _deliverFile(
      fileName: fileName,
      bytes: utf8.encode(jsonString),
      allowedExtension: 'json',
      mimeType: 'application/json',
      destination: destination,
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  /// Exports an editable 2D drawing locally; JSON remains the project backup.
  static Future<bool> exportToDxf(
    List<RoomModel> rooms,
    String projectName, {
    required String languageCode,
    ExportDestination destination = ExportDestination.saveToFiles,
    ui.Rect? sharePositionOrigin,
  }) async {
    final drawing = DxfExportBuilder.build(rooms, languageCode: languageCode);
    final jsonName = PlanExportBuilder.buildJsonFileName(projectName);
    final fileName = '${jsonName.substring(0, jsonName.length - 5)}.dxf';
    return _deliverFile(
      fileName: fileName,
      bytes: ascii.encode(drawing),
      allowedExtension: 'dxf',
      mimeType: 'image/vnd.dxf',
      destination: destination,
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  static Future<bool> exportToSvg(
    List<RoomModel> rooms,
    String projectName,
    MeasurementSystem measurementSystem, {
    required String languageCode,
    ExportDestination destination = ExportDestination.saveToFiles,
    ui.Rect? sharePositionOrigin,
  }) {
    final fileName = PlanExportBuilder.buildSvgFileName(projectName);
    final svg = PlanExportBuilder.buildFloorPlanSvg(
      rooms,
      measurementSystem,
      languageCode: languageCode,
      projectName: projectName,
    );
    return _deliverFile(
      fileName: fileName,
      bytes: utf8.encode(svg),
      allowedExtension: 'svg',
      mimeType: 'image/svg+xml',
      destination: destination,
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  /// Rasteriza el mismo SVG técnico utilizado por PDF y SVG a alta resolución.
  /// Así JPG/PNG conservan la ortogonalización, carpinterías y cotas. El PNG
  /// mantiene máxima nitidez; el JPG usa calidad 92 y fondo blanco.
  static Future<bool> exportToRasterImage(
    List<RoomModel> rooms,
    String projectName,
    MeasurementSystem measurementSystem, {
    required String languageCode,
    required bool jpeg,
    ExportDestination destination = ExportDestination.saveToFiles,
    ui.Rect? sharePositionOrigin,
  }) async {
    final svg = PlanExportBuilder.buildFloorPlanSvg(
      rooms,
      measurementSystem,
      languageCode: languageCode,
      projectName: projectName,
    );
    final pictureInfo = await vg.loadPicture(SvgStringLoader(svg), null);
    const width = 2400;
    const height = 1579;

    // `Picture.toImage` increases the bitmap canvas but does not scale the
    // vector commands. Draw the SVG into a second picture with an explicit
    // transform so the plan fills and stays centred in the exported image.
    final sourceSize = pictureInfo.size;
    final widthScale = width / sourceSize.width;
    final heightScale = height / sourceSize.height;
    final scale = widthScale < heightScale ? widthScale : heightScale;
    final offsetX = (width - (sourceSize.width * scale)) / 2;
    final offsetY = (height - (sourceSize.height * scale)) / 2;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src)
      ..translate(offsetX, offsetY)
      ..scale(scale)
      ..drawPicture(pictureInfo.picture);
    final scaledPicture = recorder.endRecording();
    pictureInfo.picture.dispose();
    final rendered = await scaledPicture.toImage(width, height);
    scaledPicture.dispose();
    try {
      final pngData = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (pngData == null) throw StateError('Could not rasterize floor plan.');
      final png = pngData.buffer.asUint8List();
      final bytes = jpeg
          ? _addJpegComment(
              Uint8List.fromList(
                image_codec.encodeJpg(
                  image_codec.decodePng(png)!,
                  quality: 92,
                ),
              ),
              'Generated by ARchScan',
            )
          : _addPngText(png, 'Software', 'ARchScan');
      final jsonName = PlanExportBuilder.buildJsonFileName(projectName);
      final baseName = jsonName.substring(0, jsonName.length - 5);
      final extension = jpeg ? 'jpg' : 'png';
      return _deliverFile(
        fileName: '$baseName.$extension',
        bytes: bytes,
        allowedExtension: extension,
        mimeType: jpeg ? 'image/jpeg' : 'image/png',
        destination: destination,
        sharePositionOrigin: sharePositionOrigin,
      );
    } finally {
      rendered.dispose();
    }
  }

  static Uint8List _addJpegComment(Uint8List jpeg, String comment) {
    if (jpeg.length < 2 || jpeg[0] != 0xff || jpeg[1] != 0xd8) return jpeg;
    final value = ascii.encode(comment);
    final length = value.length + 2;
    return Uint8List.fromList([
      0xff, 0xd8, 0xff, 0xfe, length >> 8, length & 0xff,
      ...value,
      ...jpeg.sublist(2),
    ]);
  }

  static Uint8List _addPngText(
    Uint8List png,
    String keyword,
    String value,
  ) {
    if (png.length < 33) return png;
    final type = ascii.encode('tEXt');
    final data = Uint8List.fromList([
      ...latin1.encode(keyword), 0, ...latin1.encode(value),
    ]);
    final crc = _crc32(Uint8List.fromList([...type, ...data]));
    final chunk = <int>[
      data.length >> 24,
      (data.length >> 16) & 0xff,
      (data.length >> 8) & 0xff,
      data.length & 0xff,
      ...type,
      ...data,
      crc >> 24,
      (crc >> 16) & 0xff,
      (crc >> 8) & 0xff,
      crc & 0xff,
    ];
    return Uint8List.fromList([...png.sublist(0, 33), ...chunk, ...png.sublist(33)]);
  }

  static int _crc32(Uint8List bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0
            ? (crc >> 1) ^ 0xedb88320
            : crc >> 1;
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  /// Importa un archivo JSON seleccionado desde el dispositivo.
  ///
  /// Admite tanto selectores que entregan el contenido en memoria como los
  /// que entregan una ruta local, manteniendo compatibilidad en Android e iOS.
  static Future<JsonImportResult> importProject(
    FloorPlanProvider provider, {
    required Future<bool> Function() confirmReplacement,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'svg'],
        withData: false,
      );

      if (result == null || result.files.isEmpty) {
        return JsonImportResult.cancelled;
      }

      final selected = result.files.single;
      if (selected.size > PlanExportBuilder.maxImportBytes) {
        return JsonImportResult.invalid;
      }
      final fileContent = await _readSelectedText(selected);
      if (fileContent == null) {
        return JsonImportResult.invalid;
      }

      final extension = selected.extension?.toLowerCase();
      final parsed = extension == 'svg'
          ? await compute(PlanExportBuilder.parseProjectSvg, fileContent)
          : await compute(PlanExportBuilder.parseProjectJson, fileContent);
      if (parsed == null) {
        return JsonImportResult.invalid;
      }

      if (!await confirmReplacement()) {
        return JsonImportResult.cancelled;
      }
      if (!await provider.loadExistingRooms(parsed.rooms, parsed.projectName)) {
        return JsonImportResult.invalid;
      }
      return JsonImportResult.imported;
    } catch (_) {
      return JsonImportResult.invalid;
    }
  }

  static Future<String?> _readSelectedText(PlatformFile selectedFile) async {
    final bytes = selectedFile.bytes;
    if (bytes != null) {
      if (bytes.length > PlanExportBuilder.maxImportBytes) return null;
      return utf8.decode(bytes);
    }

    final path = selectedFile.path;
    if (path == null || path.trim().isEmpty) {
      return null;
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in File(path).openRead()) {
      if (builder.length + chunk.length > PlanExportBuilder.maxImportBytes) {
        return null;
      }
      builder.add(chunk);
    }
    return utf8.decode(builder.takeBytes());
  }

  /// Genera el informe técnico y lo guarda fuera de la app.
  static Future<bool> exportToPdf(
    List<RoomModel> rooms,
    String projectName,
    MeasurementSystem measurementSystem, {
    ExportDestination destination = ExportDestination.saveToFiles,
    ui.Rect? sharePositionOrigin,
    String? languageCode,
  }) async {
    final pdfFileName = PlanExportBuilder.buildPdfFileName(projectName);
    final pdf = PlanExportBuilder.buildPdfDocument(
      rooms,
      projectName,
      measurementSystem,
      languageCode: languageCode ?? Platform.localeName,
    );

    return _deliverFile(
      fileName: pdfFileName,
      bytes: await pdf.save(),
      allowedExtension: 'pdf',
      mimeType: 'application/pdf',
      destination: destination,
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  static Future<bool> _deliverFile({
    required String fileName,
    required List<int> bytes,
    required String allowedExtension,
    required String mimeType,
    required ExportDestination destination,
    ui.Rect? sharePositionOrigin,
  }) {
    if (destination == ExportDestination.share) {
      return _shareTemporaryFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
        sharePositionOrigin: sharePositionOrigin,
      );
    }
    return _saveOutsideApp(
      fileName: fileName,
      bytes: bytes,
      allowedExtension: allowedExtension,
    );
  }

  static Future<bool> _shareTemporaryFile({
    required String fileName,
    required List<int> bytes,
    required String mimeType,
    ui.Rect? sharePositionOrigin,
  }) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    final result = await Share.shareXFiles([
      XFile(file.path, mimeType: mimeType, name: fileName),
    ], sharePositionOrigin: sharePositionOrigin);
    // Some destinations cannot report completion; dismissal is never success.
    return result.status != ShareResultStatus.dismissed;
  }

  static Future<bool> _saveOutsideApp({
    required String fileName,
    required List<int> bytes,
    required String allowedExtension,
  }) async {
    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: fileName,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [allowedExtension],
      bytes: Uint8List.fromList(bytes),
    );

    return savedPath != null;
  }
}

import 'dart:convert';

import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:test/test.dart';

void main() {
  group('import resource limits', () {
    test('rejects oversized JSON and SVG before decoding', () {
      final oversized = List.filled(PlanExportBuilder.maxImportBytes + 1, ' ').join();
      expect(PlanExportBuilder.parseProjectJson(oversized), isNull);
      expect(PlanExportBuilder.parseProjectSvg(oversized), isNull);
    });
    test('rejects excess room count', () {
      final source = jsonEncode({
        'rooms': List.generate(PlanExportBuilder.maxImportRooms + 1,
            (_) => {'points': [], 'features': []}),
      });
      expect(PlanExportBuilder.parseProjectJson(source), isNull);
    });
    test('rejects excess point count', () {
      final source = jsonEncode({
        'rooms': List.generate(21, (_) => {
          'points': List.filled(500, {'x': 0, 'y': 0, 'z': 0}),
          'features': [],
        }),
      });
      expect(PlanExportBuilder.parseProjectJson(source), isNull);
    });
    test('rejects excess points in a single room', () {
      final source = jsonEncode({
        'rooms': [{'points': List.filled(
            PlanExportBuilder.maxImportPointsPerRoom + 1,
            {'x': 0, 'y': 0, 'z': 0}), 'features': []}],
      });
      expect(PlanExportBuilder.parseProjectJson(source), isNull);
    });
    test('accepts an ordinary historical project', () {
      final room = RoomModel(id: 'legacy', name: 'Legacy',
          type: RoomType.other, points: [
            ARPoint(x: 0, y: 0, z: 0),
            ARPoint(x: 1, y: 0, z: 0),
            ARPoint(x: 1, y: 0, z: 1),
          ], isClosed: true);
      final parsed = PlanExportBuilder.parseProjectJson(
          jsonEncode({'rooms': [room.toJson()]}));
      expect(parsed, isNotNull);
      expect(parsed!.rooms.single.id, 'legacy');
    });
    test('rejects excess feature count', () {
      final source = jsonEncode({
        'rooms': [{'points': [], 'features': List.filled(
            PlanExportBuilder.maxImportFeatures + 1, {})}],
      });
      expect(PlanExportBuilder.parseProjectJson(source), isNull);
    });
  });

  test('JSON exporta versión, unidad y medidas verticales', () {
    final room = RoomModel(
      id: 'room-1',
      name: 'Dormitorio',
      type: RoomType.dormitorio,
      points: [
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 3, y: 0, z: 0),
        ARPoint(x: 3, y: 0, z: 3),
      ],
      features: [
        WallFeature(
          id: 'window-1',
          type: FeatureType.window,
          start: ARPoint(x: 0.5, y: 0, z: 0),
          end: ARPoint(x: 1.7, y: 0, z: 0),
          openingHeightMeters: 1.1,
          sillHeightMeters: 0.85,
        ),
      ],
      isClosed: true,
    );

    final data = PlanExportBuilder.buildJsonData(
      [room],
      'Casa',
    );
    final rooms = data['rooms'] as List<dynamic>;
    final roomJson = rooms.single as Map<String, dynamic>;
    final features = roomJson['features'] as List<dynamic>;
    final feature = features.single as Map<String, dynamic>;

    expect(data['formatVersion'], 2);
    expect(data['application'], 'ARchScan');
    expect(data['generator'], 'ARchScan');
    expect(data['lengthUnit'], 'meters');
    expect(feature['openingHeightMeters'], closeTo(1.1, 0.000001));
    expect(feature['sillHeightMeters'], closeTo(0.85, 0.000001));
  });

  group('nombre del archivo JSON', () {
    test('conserva un nombre normal y agrega la extensión', () {
      expect(
        PlanExportBuilder.buildJsonFileName('Casa familiar'),
        'Casa familiar.json',
      );
    });

    test('reemplaza caracteres inválidos para archivos', () {
      expect(
        PlanExportBuilder.buildJsonFileName('Casa: planta/alta?'),
        'Casa_ planta_alta_.json',
      );
    });

    test('usa un nombre seguro cuando el proyecto está vacío', () {
      expect(
        PlanExportBuilder.buildJsonFileName('   '),
        'Plano 2D.json',
      );
    });
  });

  group('nombre del archivo PDF', () {
    test('conserva un nombre normal y agrega la extensión PDF', () {
      expect(
        PlanExportBuilder.buildPdfFileName('Casa familiar'),
        'Casa familiar.pdf',
      );
    });

    test('reutiliza la normalización segura del nombre JSON', () {
      expect(
        PlanExportBuilder.buildPdfFileName('Casa: planta/alta?'),
        'Casa_ planta_alta_.pdf',
      );
    });

    test('usa un nombre seguro cuando el proyecto está vacío', () {
      expect(
        PlanExportBuilder.buildPdfFileName('   '),
        'Plano 2D.pdf',
      );
    });
  });

  group('plano geométrico del PDF', () {
    test('dibuja ambientes, puertas y ventanas', () {
      final room = RoomModel(
        id: 'room-svg',
        name: 'Estar principal',
        type: RoomType.living,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 4, y: 0, z: 0),
          ARPoint(x: 4, y: 0, z: 3),
          ARPoint(x: 0, y: 0, z: 3),
        ],
        features: [
          WallFeature(
            id: 'door-svg',
            type: FeatureType.door,
            start: ARPoint(x: 0.8, y: 0, z: 0),
            end: ARPoint(x: 1.7, y: 0, z: 0),
          ),
          WallFeature(
            id: 'window-svg',
            type: FeatureType.window,
            start: ARPoint(x: 4, y: 0, z: 0.8),
            end: ARPoint(x: 4, y: 0, z: 2.0),
          ),
        ],
        isClosed: true,
      );

      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );

      expect(svg, contains('<polygon'));
      expect(svg, contains('Estar principal'));
      expect(svg, contains('data-feature-id="door-svg"'));
      expect(svg, contains('data-feature-id="window-svg"'));
      expect(svg, contains('#F57C00'));
      expect(svg, contains('#C2185B'));
    });

    test('omite el tipo genérico Otro espacio del plano exportado', () {
      final room = RoomModel(
        id: 'generic-room',
        name: 'Local',
        type: RoomType.other,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 2),
          ARPoint(x: 0, y: 0, z: 2),
        ],
        isClosed: true,
      );

      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );

      expect(svg, contains('Local'));
      expect(svg, isNot(contains('Otro espacio')));
    });

    test('la puerta exportada respeta interior y exterior', () {
      RoomModel roomWith(DoorOpeningDirection direction) => RoomModel(
            id: 'door-room',
            name: 'Local',
            type: RoomType.living,
            points: [
              ARPoint(x: 0, y: 0, z: 0),
              ARPoint(x: 3, y: 0, z: 0),
              ARPoint(x: 3, y: 0, z: 2),
              ARPoint(x: 0, y: 0, z: 2),
            ],
            features: [
              WallFeature(
                id: 'direction-door',
                type: FeatureType.door,
                start: ARPoint(x: 0.5, y: 0, z: 0),
                end: ARPoint(x: 1.5, y: 0, z: 0),
                doorOpeningDirection: direction,
              ),
            ],
            isClosed: true,
          );

      String drawingFor(DoorOpeningDirection direction) {
        final svg = PlanExportBuilder.buildFloorPlanSvg(
          [roomWith(direction)],
          MeasurementSystem.metric,
        );
        return RegExp(
          r'<g data-feature-id="direction-door">([\s\S]*?)</g>',
        ).firstMatch(svg)!.group(1)!;
      }

      expect(
        drawingFor(DoorOpeningDirection.interior),
        isNot(drawingFor(DoorOpeningDirection.exterior)),
      );
    });

    test('no duplica una abertura compartida entre ambientes', () {
      final sharedDoor = WallFeature(
        id: 'shared-door',
        type: FeatureType.door,
        start: ARPoint(x: 2, y: 0, z: 0.8),
        end: ARPoint(x: 2, y: 0, z: 1.7),
      );
      final rooms = [
        RoomModel(
          id: 'room-a',
          name: 'Ambiente A',
          type: RoomType.living,
          points: [
            ARPoint(x: 0, y: 0, z: 0),
            ARPoint(x: 2, y: 0, z: 0),
            ARPoint(x: 2, y: 0, z: 2.5),
            ARPoint(x: 0, y: 0, z: 2.5),
          ],
          features: [sharedDoor],
          isClosed: true,
        ),
        RoomModel(
          id: 'room-b',
          name: 'Ambiente B',
          type: RoomType.cocina,
          points: [
            ARPoint(x: 2, y: 0, z: 0),
            ARPoint(x: 4, y: 0, z: 0),
            ARPoint(x: 4, y: 0, z: 2.5),
            ARPoint(x: 2, y: 0, z: 2.5),
          ],
          features: [sharedDoor],
          isClosed: true,
        ),
      ];

      final svg = PlanExportBuilder.buildFloorPlanSvg(
        rooms,
        MeasurementSystem.metric,
      );
      final occurrences = RegExp(
        'data-feature-id="shared-door"',
      ).allMatches(svg).length;

      expect(occurrences, 1);
    });

    test('incluye cotas métricas de paredes y aberturas', () {
      final room = RoomModel(
        id: 'dimensions-room',
        name: 'Estudio',
        type: RoomType.dormitorio,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 2),
          ARPoint(x: 0, y: 0, z: 2),
        ],
        features: [
          WallFeature(
            id: 'dimension-door',
            type: FeatureType.door,
            start: ARPoint(x: 0.5, y: 0, z: 0),
            end: ARPoint(x: 1.4, y: 0, z: 0),
          ),
        ],
        isClosed: true,
      );

      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );

      expect(svg, contains('3,00 m'));
      expect(svg, contains('2,00 m'));
      expect(svg, contains('0,90 m'));
    });

    test('las cotas del plano respetan el sistema imperial', () {
      final room = RoomModel(
        id: 'imperial-room',
        name: 'Office',
        type: RoomType.dormitorio,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 3.048, y: 0, z: 0),
          ARPoint(x: 3.048, y: 0, z: 2),
        ],
        isClosed: true,
      );

      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.imperial,
      );

      expect(svg, contains('′'));
      expect(svg, contains('″'));
    });

    test('reubica cotas coincidentes para evitar superposición', () {
      final room = RoomModel(
        id: 'compact-room',
        name: 'Ambiente pequeño',
        type: RoomType.pasillo,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 1, y: 0, z: 0),
          ARPoint(x: 1, y: 0, z: 1),
          ARPoint(x: 0, y: 0, z: 1),
        ],
        features: [
          WallFeature(
            id: 'full-width-door',
            type: FeatureType.door,
            start: ARPoint(x: 0, y: 0, z: 0),
            end: ARPoint(x: 1, y: 0, z: 0),
          ),
        ],
        isClosed: true,
      );

      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );
      final matches = RegExp(
        r'data-dimension-label="1,00 m" data-layout-index="(\d+)" '
        r'x="([\d.]+)" y="([\d.]+)"',
      ).allMatches(svg).toList();
      final positions = matches
          .map((match) => '${match.group(2)}:${match.group(3)}')
          .toSet();

      expect(matches.length, greaterThanOrEqualTo(2));
      expect(positions.length, matches.length);
    });

    test('traduce la leyenda del plano al inglés', () {
      final room = RoomModel(
        id: 'english-room',
        name: 'Custom room name',
        type: RoomType.cocina,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 2, y: 0, z: 0),
          ARPoint(x: 2, y: 0, z: 2),
        ],
        isClosed: true,
      );

      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
        languageCode: 'en',
      );

      expect(svg, contains('Wall'));
      expect(svg, contains('Door'));
      expect(svg, contains('Window'));
      expect(svg, isNot(contains('Pared')));
      expect(svg, contains('Kitchen'));
      expect(svg, contains('Custom room name'));
    });

    test('mantiene la leyenda española por defecto', () {
      final room = RoomModel(
        id: 'spanish-room',
        name: 'Nombre personalizado',
        type: RoomType.living,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 2, y: 0, z: 0),
          ARPoint(x: 2, y: 0, z: 2),
        ],
        isClosed: true,
      );

      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );

      expect(svg, contains('Pared'));
      expect(svg, contains('Puerta'));
      expect(svg, contains('Ventana'));
      expect(svg, contains('Nombre personalizado'));
      expect(svg, contains('data-generator="ARchScan"'));
    });

    test('conserva en el SVG la misma orientación vertical de la app', () {
      final room = RoomModel(
        id: 'orientation-room',
        name: 'Orientación',
        type: RoomType.other,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 1),
        ],
        isClosed: false,
      );

      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );
      final points = RegExp(r'<polyline points="([^"]+)"')
          .firstMatch(svg)!
          .group(1)!
          .split(' ')
          .map((pair) => pair.split(',').map(double.parse).toList())
          .toList();

      expect(points[0][1], points[1][1]);
      expect(points[2][1], greaterThan(points[1][1]));
    });

    test('las cotas no ocupan el recuadro de nombre y superficie', () {
      final room = RoomModel(
        id: 'caption-room',
        name: 'Dormitorio principal',
        type: RoomType.dormitorio,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 1, y: 0, z: 0),
          ARPoint(x: 1, y: 0, z: 1),
          ARPoint(x: 0, y: 0, z: 1),
        ],
        isClosed: true,
      );

      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );
      final nameMatch = RegExp(
        r'<text x="([\d.]+)" y="([\d.]+)" text-anchor="middle" '
        r'font-family="Helvetica" font-size="13"',
      ).firstMatch(svg)!;
      final nameX = double.parse(nameMatch.group(1)!);
      final nameY = double.parse(nameMatch.group(2)!) + 4;
      final dimensions = RegExp(
        r'data-dimension-label="[^"]+" data-layout-index="\d+" '
        r'x="([\d.]+)" y="([\d.]+)"',
      ).allMatches(svg);

      for (final dimension in dimensions) {
        final x = double.parse(dimension.group(1)!);
        final y = double.parse(dimension.group(2)!);
        expect((x - nameX).abs() > 85 || (y - nameY).abs() > 17, isTrue);
      }
    });
  });
  group('importación JSON compatible y segura', () {
    test('conserva exactamente nombres y caracteres especiales', () {
      const projectName = 'Casa Ñandú 🏠 "Norte"';
      const customName = 'Estar de Sofía / niño\nplanta alta';
      final room = RoomModel(
        id: 'room-special',
        name: customName,
        type: RoomType.living,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 2),
        ],
        isClosed: true,
      );

      final exported = jsonEncode(
        PlanExportBuilder.buildJsonData([room], projectName),
      );
      final imported = PlanExportBuilder.parseProjectJson(exported);

      expect(imported, isNotNull);
      expect(imported!.projectName, projectName);
      expect(imported.rooms.single.name, customName);
    });

    test('acepta un proyecto histórico sin metadatos ni campos nuevos', () {
      const historicalJson = '''
{
  "projectName": "Depósito histórico",
  "rooms": [
    {
      "id": "legacy-room",
      "name": "Galpón Ñ",
      "type": "living",
      "points": [
        {"x": 0, "y": 0, "z": 0},
        {"x": 4, "y": 0, "z": 0}
      ]
    }
  ]
}
''';

      final imported =
          PlanExportBuilder.parseProjectJson(historicalJson);

      expect(imported, isNotNull);
      expect(imported!.projectName, 'Depósito histórico');
      expect(imported.rooms.single.name, 'Galpón Ñ');
      expect(imported.rooms.single.features, isEmpty);
      expect(imported.rooms.single.isClosed, isFalse);
    });

    test('conserva todas las propiedades al exportar e importar', () {
      final room = RoomModel(
        id: 'room-round-trip',
        name: 'Oficina de José & Zoë',
        type: RoomType.other,
        points: [
          ARPoint(x: -1.25, y: 0.1, z: 2.75),
          ARPoint(x: 3.5, y: 0.1, z: 2.75),
          ARPoint(x: 3.5, y: 0.1, z: 6.0),
        ],
        features: [
          WallFeature(
            id: 'door-round-trip',
            type: FeatureType.door,
            start: ARPoint(x: 0.2, y: 0.1, z: 2.75),
            end: ARPoint(x: 1.1, y: 0.1, z: 2.75),
            connectedRoomId: 'room-connected',
            connectionSide: OpeningConnectionSide.right,
            doorHingeSide: DoorHingeSide.end,
            doorSwingSide: DoorSwingSide.right,
            doorOpeningDirection: DoorOpeningDirection.exterior,
            openingHeightMeters: 2.05,
            sillHeightMeters: 0,
          ),
          WallFeature(
            id: 'window-round-trip',
            type: FeatureType.window,
            start: ARPoint(x: 3.5, y: 0.1, z: 3.2),
            end: ARPoint(x: 3.5, y: 0.1, z: 4.6),
            openingHeightMeters: 1.15,
            sillHeightMeters: 0.92,
          ),
        ],
        isClosed: true,
      );

      final encoded = jsonEncode(
        PlanExportBuilder.buildJsonData(
          [room],
          'Proyecto "Área Ñ" 🧭',
        ),
      );
      final imported = PlanExportBuilder.parseProjectJson(encoded);

      expect(imported, isNotNull);
      expect(imported!.projectName, 'Proyecto "Área Ñ" 🧭');
      expect(imported.rooms.single.toJson(), room.toJson());
    });

    test('acepta la marca UTF-8 BOM al inicio del archivo', () {
      const jsonWithBom =
          '\uFEFF{"projectName":"Casa","rooms":[]}';

      final imported = PlanExportBuilder.parseProjectJson(jsonWithBom);

      expect(imported, isNotNull);
      expect(imported!.projectName, 'Casa');
      expect(imported.rooms, isEmpty);
    });

    test('rechaza contenido dañado sin lanzar excepciones', () {
      final damagedFiles = <String>[
        '{',
        '[]',
        '{"projectName":7,"rooms":[]}',
        '{"formatVersion":3,"projectName":"Casa","rooms":[]}',
        '{"lengthUnit":"feet","projectName":"Casa","rooms":[]}',
        '{"projectName":"Casa","rooms":[{"id":"r","name":"X",'
            '"type":"living","points":[{"x":1e400,"y":0,"z":0}]}]}',
      ];

      for (final damagedFile in damagedFiles) {
        expect(
          PlanExportBuilder.parseProjectJson(damagedFile),
          isNull,
          reason: damagedFile,
        );
      }
    });
  });

  group('representación técnica de relevamientos abiertos', () {
    test('no agrega una diagonal de cierre inexistente', () {
      final room = RoomModel(
        id: 'open-room',
        name: 'Ambiente en progreso',
        type: RoomType.other,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 4),
        ],
        isClosed: false,
      );

      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );

      expect(svg, contains('<polyline'));
      expect(svg, isNot(contains('<polygon')));
      expect(svg, contains('data-dimension-label="3,00 m"'));
      expect(svg, contains('data-dimension-label="4,00 m"'));
      expect(svg, isNot(contains('data-dimension-label="5,00 m"')));
      expect(
        GeometryService.calculatePathLength(
          room.points,
          closePath: false,
        ),
        closeTo(7, 0.000001),
      );
      expect(
        GeometryService.calculatePathLength(room.points),
        closeTo(12, 0.000001),
      );
    });

    test('usa el separador decimal del idioma del documento', () {
      final room = RoomModel(
        id: 'decimal-room',
        name: 'Measurement room',
        type: RoomType.other,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 3.05, y: 0, z: 0),
        ],
        isClosed: false,
      );

      final englishSvg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
        languageCode: 'en',
      );
      final spanishSvg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
        languageCode: 'es',
      );

      expect(englishSvg, contains('data-dimension-label="3.05 m"'));
      expect(englishSvg, isNot(contains('3,05 m')));
      expect(spanishSvg, contains('data-dimension-label="3,05 m"'));
    });
  });

  group('importación SVG segura', () {
    test('recupera exactamente el proyecto embebido por ARchScan', () {
      final room = RoomModel(
        id: 'svg-room',
        name: 'Cocina & comedor',
        type: RoomType.cocina,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 3.25, y: 0, z: 0),
          ARPoint(x: 3.25, y: 0, z: 2.5),
        ],
        features: [
          WallFeature(
            id: 'svg-door',
            type: FeatureType.door,
            start: ARPoint(x: 0.5, y: 0, z: 0),
            end: ARPoint(x: 1.4, y: 0, z: 0),
          ),
        ],
        isClosed: false,
      );
      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
        projectName: 'Casa Ñ',
      );
      final parsed = PlanExportBuilder.parseProjectSvg(svg);

      expect(parsed, isNotNull);
      expect(parsed!.projectName, 'Casa Ñ');
      expect(parsed.rooms.single.toJson(), room.toJson());
    });

    test('rechaza SVG externo sin metadatos ARchScan', () {
      expect(
        PlanExportBuilder.parseProjectSvg(
          '<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0"/></svg>',
        ),
        isNull,
      );
    });
  });

  group('documento PDF técnico', () {
    test('genera medidas y detalles de aberturas en ambos idiomas', () async {
      final room = RoomModel(
        id: 'technical-room',
        name: 'Oficina técnica Ñ',
        type: RoomType.other,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 4, y: 0, z: 0),
          ARPoint(x: 4, y: 0, z: 3),
          ARPoint(x: 0, y: 0, z: 3),
        ],
        features: [
          WallFeature(
            id: 'technical-door',
            type: FeatureType.door,
            start: ARPoint(x: 0.5, y: 0, z: 0),
            end: ARPoint(x: 1.4, y: 0, z: 0),
            doorHingeSide: DoorHingeSide.end,
            doorSwingSide: DoorSwingSide.right,
            doorOpeningDirection: DoorOpeningDirection.exterior,
          ),
          WallFeature(
            id: 'technical-window',
            type: FeatureType.window,
            start: ARPoint(x: 4, y: 0, z: 0.7),
            end: ARPoint(x: 4, y: 0, z: 2.1),
            openingHeightMeters: 1.2,
            sillHeightMeters: 0.9,
          ),
        ],
        isClosed: true,
      );

      for (final languageCode in ['es', 'en']) {
        final document = PlanExportBuilder.buildPdfDocument(
          [room],
          'Proyecto técnico Ñ',
          MeasurementSystem.metric,
          languageCode: languageCode,
        );
        final bytes = await document.save();

        expect(bytes.length, greaterThan(1000));
      }
    });
  });
}

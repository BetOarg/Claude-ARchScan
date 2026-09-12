import 'dart:convert';

import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScanDraft {
  final RoomModel room;
  final ScanContinuationReference? continuationReference;
  final List<ARPoint> basicHistory;

  const ScanDraft({
    required this.room,
    required this.continuationReference,
    this.basicHistory = const <ARPoint>[],
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'room': room.toJson(),
        'continuationReference':
            continuationReference == null
                ? null
                : _continuationToJson(continuationReference!),
        'basicHistory': basicHistory.map((point) => point.toJson()).toList(),
      };

  factory ScanDraft.fromJson(Map<String, dynamic> json) {
    final historyJson = json['basicHistory'] as List<dynamic>?;

    return ScanDraft(
      room: RoomModel.fromJson(
        Map<String, dynamic>.from(json['room'] as Map),
      ),
      continuationReference: _continuationFromJson(
        json['continuationReference'],
      ),
      basicHistory: historyJson == null
          ? const <ARPoint>[]
          : historyJson
              .map(
                (value) => ARPoint.fromJson(
                  Map<String, dynamic>.from(value as Map),
                ),
              )
              .toList(),
    );
  }

  static Map<String, dynamic> _continuationToJson(
    ScanContinuationReference reference,
  ) =>
      <String, dynamic>{
        'sourceRoomId': reference.sourceRoomId,
        'featureId': reference.featureId,
        'featureType': reference.featureType.name,
        'globalStart': reference.globalStart.toJson(),
        'globalEnd': reference.globalEnd.toJson(),
        'side': reference.side.name,
        'startEndpoint': reference.startEndpoint.name,
      };

  static ScanContinuationReference? _continuationFromJson(
    dynamic value,
  ) {
    if (value is! Map) {
      return null;
    }

    final json = Map<String, dynamic>.from(value);
    return ScanContinuationReference(
      sourceRoomId: json['sourceRoomId'] as String,
      featureId: json['featureId'] as String,
      featureType: FeatureType.values.firstWhere(
        (type) => type.name == json['featureType'],
      ),
      globalStart: ARPoint.fromJson(
        Map<String, dynamic>.from(json['globalStart'] as Map),
      ),
      globalEnd: ARPoint.fromJson(
        Map<String, dynamic>.from(json['globalEnd'] as Map),
      ),
      side: OpeningConnectionSide.values.firstWhere(
        (side) => side.name == json['side'],
      ),
      startEndpoint: ContinuationStartEndpoint.values.firstWhere(
        (endpoint) => endpoint.name == json['startEndpoint'],
      ),
    );
  }
}

class ScanDraftService {
  static const String _keyPrefix = 'scan_draft_v1_';

  const ScanDraftService();

  String _key(String projectUuid) => '$_keyPrefix$projectUuid';

  Future<void> save({
    required String projectUuid,
    required RoomModel room,
    ScanContinuationReference? continuationReference,
    List<ARPoint> basicHistory = const <ARPoint>[],
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final draft = ScanDraft(
      room: room,
      continuationReference: continuationReference,
      basicHistory: basicHistory,
    );
    final saved = await preferences.setString(
      _key(projectUuid),
      jsonEncode(draft.toJson()),
    );
    if (!saved) throw StateError('Scan draft could not be saved.');
  }

  Future<ScanDraft?> load(String projectUuid) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key(projectUuid));

    if (encoded == null || encoded.isEmpty) {
      return null;
    }

    try {
      return ScanDraft.fromJson(
        Map<String, dynamic>.from(jsonDecode(encoded) as Map),
      );
    } catch (_) {
      await preferences.remove(_key(projectUuid));
      return null;
    }
  }

  Future<void> clear(String projectUuid) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(projectUuid));
  }
}

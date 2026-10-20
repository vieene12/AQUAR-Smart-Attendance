import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AttendanceLocationConfig {
  const AttendanceLocationConfig({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.maxAccuracyMeters,
  });

  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final double maxAccuracyMeters;

  bool get isValid =>
      name.trim().isNotEmpty &&
      name.trim().length <= 100 &&
      latitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude.isFinite &&
      longitude >= -180 &&
      longitude <= 180 &&
      radiusMeters.isFinite &&
      radiusMeters > 0 &&
      maxAccuracyMeters.isFinite &&
      maxAccuracyMeters > 0;

  bool hasSameValues(AttendanceLocationConfig other) =>
      name.trim() == other.name.trim() &&
      latitude == other.latitude &&
      longitude == other.longitude &&
      radiusMeters == other.radiusMeters &&
      maxAccuracyMeters == other.maxAccuracyMeters;

  Map<String, dynamic> toMap() {
    if (!isValid) throw const FormatException('Cấu hình vị trí không hợp lệ.');
    return {
      'name': name.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
      'maxAccuracyMeters': maxAccuracyMeters,
    };
  }

  factory AttendanceLocationConfig.fromMap(Map<String, dynamic> data) {
    if (data.keys.toSet().difference({
          'name',
          'latitude',
          'longitude',
          'radiusMeters',
          'maxAccuracyMeters',
        }).isNotEmpty ||
        data.length != 5) {
      throw const FormatException('Cấu hình vị trí không hợp lệ.');
    }
    final name = data['name'];
    final latitude = data['latitude'];
    final longitude = data['longitude'];
    final radius = data['radiusMeters'];
    final accuracy = data['maxAccuracyMeters'];
    if (name is! String ||
        latitude is! num ||
        longitude is! num ||
        radius is! num ||
        accuracy is! num) {
      throw const FormatException('Cấu hình vị trí không hợp lệ.');
    }
    final config = AttendanceLocationConfig(
      name: name,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      radiusMeters: radius.toDouble(),
      maxAccuracyMeters: accuracy.toDouble(),
    );
    if (!config.isValid) {
      throw const FormatException('Cấu hình vị trí không hợp lệ.');
    }
    return config;
  }
}

abstract class AttendanceLocationRepository {
  Future<AttendanceLocationConfig?> load();
  Future<AttendanceLocationConfig> save(AttendanceLocationConfig config);
}

class FirestoreAttendanceLocationRepository
    implements AttendanceLocationRepository {
  FirestoreAttendanceLocationRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _providedAuth = auth,
       _providedFirestore = firestore;

  final FirebaseAuth? _providedAuth;
  final FirebaseFirestore? _providedFirestore;

  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _document =>
      _firestore.collection('company_settings').doc('attendance_location');

  @override
  Future<AttendanceLocationConfig?> load() async {
    if (_auth.currentUser == null) {
      throw FirebaseException(plugin: 'firebase_auth', code: 'unauthenticated');
    }
    final snapshot = await _document.get(
      const GetOptions(source: Source.server),
    );
    if (!snapshot.exists) return null;
    return AttendanceLocationConfig.fromMap(snapshot.data()!);
  }

  @override
  Future<AttendanceLocationConfig> save(AttendanceLocationConfig config) async {
    if (_auth.currentUser == null) {
      throw FirebaseException(plugin: 'firebase_auth', code: 'unauthenticated');
    }
    await _document.set(config.toMap());
    final saved = await load();
    if (saved == null || !saved.hasSameValues(config)) {
      throw const FormatException('Chưa xác nhận được cấu hình đã lưu.');
    }
    return saved;
  }
}

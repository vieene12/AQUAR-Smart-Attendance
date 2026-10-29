import 'package:flutter/material.dart';
import 'package:smart_attendance/app/app.dart';
import 'package:smart_attendance/core/firebase/firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBootstrap.initialize();
  runApp(const SmartAttendanceApp());
}

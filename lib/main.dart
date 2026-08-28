import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app.dart';
import 'app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    debugPrint('[NoteEryk][FlutterError] ${details.exception}');
    if (details.stack != null) {
      debugPrint('[NoteEryk][FlutterError][stack]\n${details.stack}');
    }
    FlutterError.presentError(details);
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[NoteEryk][PlatformError] $error\n$stack');
    return false;
  };
  final state = AppState();
  runApp(NihongoNotebookApp(state: state));
  unawaited(state.initialize());
}

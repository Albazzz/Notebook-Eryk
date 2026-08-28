import 'package:flutter/services.dart';

/// Reads files staged by the iOS Share Extension.
///
/// Other platforms simply return an empty list, so the rest of the app does
/// not need platform checks.
class SharedImportService {
  static const _channel = MethodChannel('com.example.noteeryk/shared_import');

  Future<List<String>> pendingFiles() async {
    try {
      final files = await _channel.invokeListMethod<String>('pendingFiles');
      return files ?? const [];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  Future<void> acknowledge(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('acknowledge', paths);
    } on MissingPluginException {
      // The channel is intentionally unavailable outside iOS.
    } on PlatformException {
      // Keep app import failures non-fatal. The files can be discovered again
      // on the next foreground pass if native cleanup did not happen.
    }
  }
}

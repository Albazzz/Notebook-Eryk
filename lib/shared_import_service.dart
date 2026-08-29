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

  Future<String> diagnostics() async {
    try {
      return await _channel.invokeMethod<String>('shareDiagnostics') ?? '';
    } on MissingPluginException {
      return '';
    } on PlatformException catch (error) {
      return 'Không đọc được nhật ký native: ${error.message ?? error.code}';
    }
  }

  Future<void> clearDiagnostics() async {
    try {
      await _channel.invokeMethod<void>('clearShareDiagnostics');
    } on MissingPluginException {
      // Diagnostics are only available in the iOS build.
    } on PlatformException {
      // Keep diagnostics UI non-fatal.
    }
  }
}

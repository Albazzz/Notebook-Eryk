import 'dart:async';

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models.dart';
import 'screens/editor_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/weaknesses_screen.dart';
import 'screens/dictionary_screen.dart';
import 'shared_import_service.dart';
import 'theme.dart';
import 'widgets/app_sidebar.dart';

class NihongoNotebookApp extends StatefulWidget {
  const NihongoNotebookApp({super.key, required this.state});
  final AppState state;

  @override
  State<NihongoNotebookApp> createState() => _NihongoNotebookAppState();
}

class _NihongoNotebookAppState extends State<NihongoNotebookApp>
    with WidgetsBindingObserver {
  late ThemeMode _themeMode;
  final SharedImportService _sharedImport = SharedImportService();
  List<String> _pendingSharedFiles = const [];
  bool _checkingSharedFiles = false;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.state.themeMode;
    widget.state.addListener(_onStateChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSharedFiles());
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSharedFiles();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // iPadOS may terminate a suspended app without a final callback. The
      // debounced autosave handles normal edits; this also creates a portable
      // session snapshot while the process is still alive.
      unawaited(_persistSessionSnapshot());
    }
  }

  Future<void> _persistSessionSnapshot() async {
    try {
      await widget.state.flushPersistence(snapshot: true);
    } catch (error, stackTrace) {
      debugPrint('[NoteEryk][Storage] session snapshot failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _checkSharedFiles() async {
    if (_checkingSharedFiles || _pendingSharedFiles.isNotEmpty) return;
    _checkingSharedFiles = true;
    var paths = const <String>[];
    try {
      paths = await _sharedImport.pendingFiles();
      // The Share Extension writes into the App Group immediately before it
      // closes. On iPadOS the containing app can receive `resumed` a fraction
      // earlier, so give the filesystem a short chance to publish the files.
      for (var attempt = 0; paths.isEmpty && attempt < 3; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        paths = await _sharedImport.pendingFiles();
      }
    } catch (error) {
      debugPrint('[NoteEryk][Share] pending file check failed: $error');
    } finally {
      _checkingSharedFiles = false;
    }
    if (!mounted || paths.isEmpty) return;
    widget.state.goTo(AppDestination.library);
    setState(() => _pendingSharedFiles = paths);
  }

  Future<void> _finishSharedImport(List<String> paths) async {
    await _sharedImport.acknowledge(paths);
    if (!mounted) return;
    setState(() => _pendingSharedFiles = const []);
  }

  void _deferSharedImport() {
    if (!mounted || _pendingSharedFiles.isEmpty) return;
    setState(() => _pendingSharedFiles = const []);
  }

  void _onStateChanged() {
    if (!mounted || _themeMode == widget.state.themeMode) return;
    setState(() => _themeMode = widget.state.themeMode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Note Eryk',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: _themeMode,
      // Keep MaterialApp/Theme/MediaQuery mounted while screens change.
      home: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) => widget.state.openNotebook != null
            ? EditorScreen(
                state: widget.state,
                notebook: widget.state.openNotebook!,
              )
            : _AppShell(
                state: widget.state,
                sharedFiles: _pendingSharedFiles,
                onSharedFilesHandled: _finishSharedImport,
                onSharedFilesDeferred: _deferSharedImport,
              ),
      ),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell({
    required this.state,
    required this.sharedFiles,
    required this.onSharedFilesHandled,
    required this.onSharedFilesDeferred,
  });
  final AppState state;
  final List<String> sharedFiles;
  final ValueChanged<List<String>> onSharedFilesHandled;
  final VoidCallback onSharedFilesDeferred;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;
        // Keep each primary screen mounted while navigating. Replacing an
        // inherited-widget subtree during a drawer transition can leave stale
        // dependents in debug builds (the `_dependents.isEmpty` assertion).
        // IndexedStack preserves the elements and only changes visibility.
        final content = IndexedStack(
          index: state.destination.index,
          sizing: StackFit.expand,
          children: [
            LibraryScreen(
              state: state,
              sharedFiles: sharedFiles,
              onSharedFilesHandled: onSharedFilesHandled,
              onSharedFilesDeferred: onSharedFilesDeferred,
            ),
            WeaknessesScreen(state: state),
            DictionaryScreen(state: state),
            SettingsScreen(state: state),
          ],
        );
        if (!wide) {
          return Scaffold(
            appBar: AppBar(title: const Text('Note Eryk')),
            drawer: Drawer(
              child: SafeArea(child: AppSidebar(state: state, compact: true)),
            ),
            body: content,
          );
        }
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                SizedBox(width: 232, child: AppSidebar(state: state)),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          ),
        );
      },
    );
  }
}

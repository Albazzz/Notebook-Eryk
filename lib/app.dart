import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/editor_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/weaknesses_screen.dart';
import 'screens/dictionary_screen.dart';
import 'theme.dart';
import 'widgets/app_sidebar.dart';

class NihongoNotebookApp extends StatefulWidget {
  const NihongoNotebookApp({super.key, required this.state});
  final AppState state;

  @override
  State<NihongoNotebookApp> createState() => _NihongoNotebookAppState();
}

class _NihongoNotebookAppState extends State<NihongoNotebookApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.state.themeMode;
    widget.state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    super.dispose();
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
            : _AppShell(state: widget.state),
      ),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell({required this.state});
  final AppState state;

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
            LibraryScreen(state: state),
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

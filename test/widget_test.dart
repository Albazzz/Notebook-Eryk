import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteeryk/app.dart';
import 'package:noteeryk/app_state.dart';
import 'package:noteeryk/furigana.dart';
import 'package:noteeryk/models.dart';
import 'package:noteeryk/review.dart';
import 'package:noteeryk/screens/settings_screen.dart';
import 'package:noteeryk/services.dart';
import 'package:flutter/rendering.dart';
import 'package:noteeryk/widgets/color_panel.dart';
import 'package:noteeryk/widgets/notebook_cover.dart';
import 'package:noteeryk/widgets/page_rendering.dart';
import 'package:noteeryk/widgets/ocr_highlight_sheet.dart';
import 'package:noteeryk/widgets/quick_check_sheet.dart';
import 'package:noteeryk/widgets/weak_point_input_sheet.dart';

void main() {
  _quickCheckTests();

  testWidgets('tô cụm trên OCR trả về đúng các cụm đã chọn', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    OcrHighlightResult? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => picked = await showOcrHighlightSheet(
                context,
                ocrText: 'かれは毎日、勉強します。',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('勉強'),
      ),
    );
    Offset glyphCenter(int index) {
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: index, extentOffset: index + 1),
          )
          .first
          .toRect();
      return paragraph.localToGlobal(box.center);
    }

    // Chạm một kanji tô cả cụm kanji liền nhau: 毎日 rồi 勉強.
    await tester.tapAt(glyphCenter(3));
    await tester.pump();
    await tester.tapAt(glyphCenter(6));
    await tester.pump();
    expect(find.text('Tạo điểm yếu (2)'), findsOneWidget);

    // Chạm lại cụm đã tô thì bỏ tô.
    await tester.tapAt(glyphCenter(4));
    await tester.pump();
    expect(find.text('Tạo điểm yếu (1)'), findsOneWidget);

    await tester.tap(find.text('Tạo điểm yếu (1)'));
    await tester.pumpAndSettle();
    expect(picked?.terms, ['勉強']);
  });

  testWidgets('tạo vở trắng mở ngay vở mới trên iPad ngang', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tạo mới').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Tên vở'), 'Vở thử');
    final create = find.widgetWithText(FilledButton, 'Tạo vở');
    await tester.ensureVisible(create);
    await tester.pumpAndSettle();
    await tester.tap(create);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(
      state.notebooks.map((notebook) => notebook.title),
      contains('Vở thử'),
    );
    expect(state.openNotebook?.title, 'Vở thử');
  });

  testWidgets('hiển thị thư viện notebook trên tablet', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Vở của tôi'), findsWidgets);
    expect(find.text('N3 Grammar'), findsOneWidget);
    expect(find.text('Tạo mới'), findsOneWidget);
  });

  testWidgets('folder luôn có thao tác xóa trên iPad', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    state.createFolder('JLPT');
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Tùy chọn folder'));
    await tester.pumpAndSettle();
    expect(find.text('Xóa folder'), findsOneWidget);

    await tester.tap(find.text('Xóa folder'));
    await tester.pumpAndSettle();
    expect(find.text('Giữ ghi chú'), findsOneWidget);
    expect(find.text('Chuyển vào Thùng rác'), findsOneWidget);
  });

  testWidgets('chọn nhiều trên iPad dọc không ép tiêu đề thành cột', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.playlist_add_check_rounded));
    await tester.pump();
    await tester.tap(find.text('N3 Grammar'));
    await tester.pumpAndSettle();

    expect(find.text('1 vở đã chọn'), findsOneWidget);
    expect(find.byIcon(Icons.drive_file_move_outline), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsWidgets);
    final titleSize = tester.getSize(find.text('Vở của tôi').last);
    expect(titleSize.width, greaterThan(120));
    expect(tester.takeException(), isNull);
  });

  testWidgets('chọn tất cả và bỏ chọn tất cả các vở đang hiển thị', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.playlist_add_check_rounded));
    await tester.pump();
    await tester.tap(find.text('Chọn tất cả'));
    await tester.pump();

    expect(find.text('1 vở đã chọn'), findsOneWidget);
    expect(find.text('Bỏ chọn tất cả'), findsOneWidget);

    await tester.tap(find.text('Bỏ chọn tất cả'));
    await tester.pump();
    expect(find.text('1 vở đã chọn'), findsNothing);
    expect(find.text('Chọn tất cả'), findsOneWidget);
  });

  testWidgets('chạm đồng thời hai ngón hoàn tác nét vừa vẽ', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    state.open(state.notebooks.first);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    final stylus = TestPointer(10, PointerDeviceKind.stylus);
    await tester.sendEventToBinding(stylus.down(const Offset(600, 310)));
    await tester.sendEventToBinding(stylus.move(const Offset(650, 340)));
    await tester.sendEventToBinding(stylus.move(const Offset(700, 320)));
    await tester.sendEventToBinding(stylus.up());
    await tester.pump();
    expect(state.strokesFor('n3'), hasLength(1));

    final firstFinger = TestPointer(20, PointerDeviceKind.touch);
    final secondFinger = TestPointer(21, PointerDeviceKind.touch);
    await tester.sendEventToBinding(firstFinger.down(const Offset(610, 330)));
    await tester.sendEventToBinding(secondFinger.down(const Offset(665, 330)));
    await tester.sendEventToBinding(firstFinger.up());
    await tester.sendEventToBinding(secondFinger.up());
    await tester.pump();

    expect(state.strokesFor('n3'), isEmpty);
    expect(find.text('Đã hoàn tác · chạm hai ngón'), findsOneWidget);
  });

  testWidgets('xoay iPad ngang sang dọc, nét viết giữ đúng chỗ trên trang', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    state.open(state.notebooks.first);
    await tester.pumpWidget(NihongoNotebookApp(state: state));

    // Writes a short stroke at the same spot of the page (as a fraction of
    // the page on screen) and returns where it was stored.
    Future<Offset> writeAtCentre(Size screen, int pointer) async {
      tester.view.physicalSize = screen;
      await tester.pumpAndSettle();
      final page = tester.getRect(find.byKey(const ValueKey('page-canvas')));
      final at = page.topLeft + Offset(page.width * .5, page.height * .4);
      final stylus = TestPointer(pointer, PointerDeviceKind.stylus);
      await tester.sendEventToBinding(stylus.down(at));
      await tester.sendEventToBinding(stylus.move(at + const Offset(10, 0)));
      await tester.sendEventToBinding(stylus.up());
      await tester.pump();
      return state.strokesFor('n3').last.points.first.offset;
    }

    final landscape = await writeAtCentre(const Size(1180, 820), 41);
    final portrait = await writeAtCentre(const Size(820, 1180), 42);
    // Same place on the page → same stored point, whatever the orientation.
    expect((landscape - portrait).distance, lessThan(1.5));
    expect(landscape.dx, closeTo(kPageCanvasSize.width * .5, 1.5));
    expect(landscape.dy, closeTo(kPageCanvasSize.height * .4, 1.5));
  });

  testWidgets('nét vẽ không bị đè khi chuyển trang', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    state.open(state.notebooks.first, page: 1);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    Future<void> drawStroke(Offset start, Offset end) async {
      final stylus = TestPointer(
        100 + state.openPage,
        PointerDeviceKind.stylus,
      );
      await tester.sendEventToBinding(stylus.down(start));
      await tester.sendEventToBinding(stylus.move(end));
      await tester.sendEventToBinding(stylus.up());
      await tester.pump();
    }

    await drawStroke(const Offset(600, 310), const Offset(700, 330));
    expect(state.strokesFor('n3', 1), hasLength(1));

    await tester.tap(
      find.byWidgetPredicate((widget) => widget is Text && widget.data == '2'),
    );
    await tester.pump();
    await drawStroke(const Offset(600, 360), const Offset(700, 380));

    expect(state.strokesFor('n3', 1), hasLength(1));
    expect(state.strokesFor('n3', 2), hasLength(1));
  });

  testWidgets('bấm thumbnail để chuyển nhanh đến trang', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    state.open(state.notebooks.first);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate((widget) => widget is Text && widget.data == '1'),
    );
    await tester.pump();

    expect(state.openPage, 1);
    expect(find.text('Trang 1 · Đã lưu'), findsOneWidget);
  });

  testWidgets('nút thước chỉ bật tắt thước và giữ bút vẽ', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    state.open(state.notebooks.first);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thước'));
    await tester.pump();
    expect(
      find.text('Một ngón kéo · Hai ngón thu phóng / xoay · Pencil để kẻ'),
      findsOneWidget,
    );

    await tester.tap(find.text('Thước'));
    await tester.pump();
    expect(
      find.text('Một ngón kéo · Hai ngón thu phóng / xoay · Pencil để kẻ'),
      findsNothing,
    );
  });

  testWidgets('chọn Tẩy một phần sẽ cắt nét và có thể hoàn tác', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook()..autoSave = false;
    addTearDown(state.dispose);
    state.saveStrokes('n3', [
      InkStroke(
        points: const [
          StrokePoint(Offset(100, 200), 1),
          StrokePoint(Offset(300, 200), 1),
        ],
        color: const Color(0xff000000),
        width: 3,
        tool: EditorTool.pen,
        createdAt: DateTime(2026, 1, 1),
      ),
    ], 1);
    state.open(state.notebooks.first, page: 1);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tẩy'));
    await tester.pump();
    await tester.tap(find.text('Tẩy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tẩy một phần'));
    await tester.pump();

    final selector = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(selector.selected, {'part'});

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    final ink = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString() == '_InkPainter',
    );
    expect(ink, findsWidgets);
    final inkWidgets = tester.widgetList<CustomPaint>(ink).toList();
    inkWidgets.sort((a, b) {
      final aSize = tester.getSize(find.byWidget(a));
      final bSize = tester.getSize(find.byWidget(b));
      return (bSize.width * bSize.height).compareTo(aSize.width * aSize.height);
    });
    final pageInk = find.byWidget(inkWidgets.first);
    // The page is scaled to fit the screen; (200, 200) is in page space.
    final pageRect = tester.getRect(pageInk);
    final eraserPoint =
        pageRect.topLeft +
        const Offset(200, 200) * (pageRect.width / kPageCanvasSize.width);
    final stylus = TestPointer(71, PointerDeviceKind.stylus);
    await tester.sendEventToBinding(stylus.down(eraserPoint));
    await tester.sendEventToBinding(stylus.up());
    await tester.pump();

    expect(state.strokesFor('n3', 1), hasLength(2));

    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pump();
    expect(state.strokesFor('n3', 1), hasLength(1));
  });

  testWidgets('tra từ nhanh mở ngay trên thanh công cụ và không chặn bút', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    state.open(state.notebooks.first);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    final quickLookupLabel = find.text('Tra từ nhanh');
    expect(tester.widget<Text>(quickLookupLabel).textAlign, TextAlign.center);
    final quickLookupButton = find
        .ancestor(of: quickLookupLabel, matching: find.byType(InkWell))
        .first;
    final quickLookupIcon = find.descendant(
      of: quickLookupButton,
      matching: find.byIcon(Icons.search_rounded),
    );
    expect(
      (tester.getCenter(quickLookupLabel).dx -
              tester.getCenter(quickLookupIcon).dx)
          .abs(),
      lessThan(1),
    );

    await tester.tap(find.text('Tra từ nhanh'));
    await tester.pump();
    expect(
      find.text('Kana · Kanji · Hán Việt · nghĩa tiếng Việt'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Bút thư pháp'));
    await tester.pump();
    expect(
      find.text('Kana · Kanji · Hán Việt · nghĩa tiếng Việt'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('đóng menu trước khi chuyển trang trên màn hình nhỏ', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
    await tester.pumpAndSettle();

    expect(state.destination, AppDestination.weaknesses);
    expect(tester.takeException(), isNull);
  });

  testWidgets('đóng hộp thoại AI trước khi rời trình soạn thảo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    state.open(state.notebooks.first);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AI Tra từ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thiết lập AI'));
    await tester.pumpAndSettle();

    expect(state.destination, AppDestination.settings);
    expect(state.openNotebook, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('ngón tay kéo trang còn Pencil chỉ tạo nét', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    state.open(state.notebooks.first, page: 1);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    final initial = List<double>.of(controller.value.storage);
    final finger = TestPointer(30, PointerDeviceKind.touch);
    await tester.sendEventToBinding(finger.down(const Offset(600, 360)));
    await tester.sendEventToBinding(finger.move(const Offset(640, 390)));
    await tester.sendEventToBinding(finger.move(const Offset(690, 420)));
    await tester.sendEventToBinding(finger.up());
    await tester.pump();
    expect(controller.value.storage, isNot(equals(initial)));

    controller.value = controller.value.clone()..setIdentity();
    final beforePencil = List<double>.of(controller.value.storage);
    final pencil = TestPointer(31, PointerDeviceKind.stylus);
    await tester.sendEventToBinding(pencil.down(const Offset(600, 310)));
    await tester.sendEventToBinding(pencil.move(const Offset(650, 340)));
    await tester.sendEventToBinding(pencil.move(const Offset(700, 320)));
    await tester.sendEventToBinding(pencil.up());
    await tester.pump();

    expect(controller.value.storage, equals(beforePencil));
    expect(state.strokesFor('n3', 1), hasLength(1));
  });

  testWidgets('xoay trang theo góc và trả về thẳng', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    state.open(state.notebooks.first, page: 1);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('0°'), findsOneWidget);
    await tester.tap(find.byTooltip('Xoay phải 15°'));
    await tester.pump();
    expect(find.text('15°'), findsOneWidget);
    await tester.tap(find.byTooltip('Xoay trái 15°'));
    await tester.pump();
    await tester.tap(find.byTooltip('Xoay trái 15°'));
    await tester.pump();
    expect(find.text('-15°'), findsOneWidget);
    await tester.tap(find.byTooltip('Trả trang về thẳng'));
    await tester.pump();
    expect(find.text('0°'), findsOneWidget);
  });

  testWidgets('công cụ Văn bản: vẽ ô, gõ trong ô, kéo, xóa và hoàn tác', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    state.open(state.notebooks.first, page: 1);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Văn bản'));
    await tester.pump();
    // Draw a box step by step like a pencil.
    final pen = await tester.startGesture(
      const Offset(560, 260),
      kind: PointerDeviceKind.stylus,
    );
    for (var step = 0; step < 8; step++) {
      await pen.moveBy(const Offset(30, 12));
      await tester.pump();
    }
    await pen.up();
    await tester.pumpAndSettle();

    final drawn = state.textBoxesFor('n3', 1).single;
    expect(drawn.width, greaterThan(150));
    expect(drawn.height, greaterThan(40));
    expect(find.byKey(const ValueKey('text-box-inline')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('text-box-inline')),
      '日本語のメモ',
    );
    await tester.tap(find.text('Xong'));
    await tester.pumpAndSettle();
    final created = state.textBoxesFor('n3', 1).single;
    expect(created.text, '日本語のメモ');
    expect(state.strokesFor('n3', 1), isEmpty);
    // The frame spans the whole box, so all of it can be grabbed.
    expect(
      tester.getSize(find.byKey(ValueKey('text-box-${created.id}'))).width,
      created.width,
    );

    // Bigger text from the toolbar applies to the selected box.
    await tester.tap(find.byTooltip('Chữ to hơn'));
    await tester.pump();
    expect(state.textBoxesFor('n3', 1).single.fontSize, created.fontSize + 2);

    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey('text-box-${created.id}'))),
    );
    for (var step = 0; step < 6; step++) {
      await finger.moveBy(const Offset(20, 15));
      await tester.pump();
    }
    await finger.up();
    await tester.pump();
    final moved =
        state.textBoxesFor('n3', 1).single.position - created.position;
    expect(moved.dx, greaterThan(0));
    expect(moved.dy, greaterThan(0));

    await tester.tap(find.text('Xóa'));
    await tester.pump();
    expect(state.textBoxesFor('n3', 1), isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Hoàn tác'));
    await tester.pump();
    expect(state.textBoxesFor('n3', 1).single.text, '日本語のメモ');
  });

  testWidgets('ô văn bản đang gõ được lưu khi chuyển trang, ô trống bị bỏ', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    state.open(state.notebooks.first, page: 1);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Văn bản'));
    await tester.pump();

    Future<void> drawBox(Offset from) async {
      final pen = await tester.startGesture(
        from,
        kind: PointerDeviceKind.stylus,
      );
      for (var step = 0; step < 6; step++) {
        await pen.moveBy(const Offset(30, 10));
        await tester.pump();
      }
      await pen.up();
      await tester.pumpAndSettle();
    }

    // An empty box disappears when the learner taps elsewhere.
    await drawBox(const Offset(560, 520));
    expect(state.textBoxesFor('n3', 1), hasLength(1));
    await tester.tapAt(const Offset(760, 420));
    await tester.pumpAndSettle();
    expect(state.textBoxesFor('n3', 1), isEmpty);

    await drawBox(const Offset(560, 260));
    await tester.enterText(
      find.byKey(const ValueKey('text-box-inline')),
      'chưa bấm Xong',
    );
    state.goToPage(2);
    await tester.pumpAndSettle();
    expect(state.textBoxesFor('n3', 1).single.text, 'chưa bấm Xong');
    expect(tester.takeException(), isNull);
  });

  testWidgets('thêm điểm yếu ngữ pháp thủ công không cần AI', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook()..weakPoints = [];
    addTearDown(state.dispose);
    state.goTo(AppDestination.weaknesses);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Thêm thủ công'));
    await tester.pumpAndSettle();
    expect(find.text('Thêm điểm yếu'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Mẫu ngữ pháp (vd 〜わけではない)'),
      '〜とはいえ',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Nghĩa / cách dùng'),
      'dẫu nói là... nhưng',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Cách nối (接続), vd V辞書形 / Nの + わけではない'),
      '普通形 + とはいえ',
    );
    final add = find.widgetWithText(FilledButton, 'Thêm');
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    final point = state.weakPoints.single;
    expect(point.title, '〜とはいえ');
    expect(point.kind, WeaknessKind.grammar);
    expect(point.conjugation, '普通形 + とはいえ');
    expect(point.isTyped, isTrue);
    expect(point.isNormalized, isTrue);
  });

  testWidgets('nhập điểm yếu không dùng AI: tách dòng, kèm nghĩa, không trùng', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showWeakPointInputSheet(context, state),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Tạo bằng AI'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('weak-point-input')),
      '. Trọng tâm ngữ pháp\n〜わけではない [N3]\nCách dùng: không hẳn là\n〜にもかかわらず: mặc dù\n〜ものの',
    );
    await tester.pump();
    await tester.tap(find.text('Lưu 3 dòng, không dùng AI'));
    await tester.pumpAndSettle();

    final points = state.weakPoints;
    expect(points.map((point) => point.title).toSet(), {
      '〜わけではない',
      '〜にもかかわらず',
      '〜ものの',
    });
    expect(points.every((point) => point.kind == WeaknessKind.grammar), isTrue);
    expect(
      points.every((point) => point.isTyped && !point.isNormalized),
      isTrue,
    );
    expect(
      points.firstWhere((point) => point.title == '〜にもかかわらず').content,
      'mặc dù',
    );
    expect(points.first.sourceLabel, 'Nhập tay');
  });

  for (final size in const [Size(1180, 820), Size(1024, 700), Size(820, 560)]) {
    testWidgets(
      'bảng nhập điểm yếu không tràn khi bàn phím bật (${size.width.toInt()}x${size.height.toInt()})',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final state = _stateWithNotebook();
        addTearDown(state.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showWeakPointInputSheet(context, state),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        // The iPad keyboard with its suggestion bar takes about half the screen.
        tester.view.viewInsets = FakeViewPadding(bottom: size.height * .5);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final field = tester.getRect(
          find.byKey(const ValueKey('weak-point-input')),
        );
        final chips = tester.getRect(find.text('Chỉ Kanji'));
        expect(field.top, greaterThan(chips.bottom));
        expect(field.height, greaterThanOrEqualTo(159));
        // The hint fits inside the field instead of spilling over the chips.
        final hint = tester.getRect(find.textContaining('〜とはいえ [N2]'));
        expect(hint.top, greaterThanOrEqualTo(field.top));
      },
    );
  }

  testWidgets(
    'thêm thủ công tự điền furigana, nghĩa từ từ điển, không đè chữ tự gõ',
    (tester) async {
      tester.view.physicalSize = const Size(1180, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final state = _stateWithNotebook()..weakPoints = [];
      addTearDown(state.dispose);
      state.goTo(AppDestination.weaknesses);
      await tester.pumpWidget(NihongoNotebookApp(state: state));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Thêm thủ công'));
      await tester.pumpAndSettle();

      String textOf(String label) => tester
          .widget<TextField>(find.widgetWithText(TextField, label))
          .controller!
          .text;

      await tester.enterText(
        find.widgetWithText(TextField, 'Mẫu ngữ pháp (vd 〜わけではない)'),
        '揚げる',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      // A dictionary word switches away from the default grammar form.
      expect(textOf('Cách đọc (よみ / furigana)'), 'あげる');
      expect(textOf('Hán Việt'), 'DƯƠNG');
      expect(textOf('Nghĩa'), 'chiên, rán');
      expect(find.textContaining('Đã tự điền từ từ điển'), findsOneWidget);

      // What the learner writes survives the next lookup.
      await tester.enterText(
        find.widgetWithText(TextField, 'Nghĩa'),
        'nghĩa riêng',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Từ vựng'), '食べる');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(textOf('Nghĩa'), 'nghĩa riêng');
      expect(textOf('Cách đọc (よみ / furigana)'), 'たべる');

      final add = find.widgetWithText(FilledButton, 'Thêm');
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      final point = state.weakPoints.single;
      expect(point.kind, WeaknessKind.vocabulary);
      expect(point.reading, 'たべる');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('lưu không dùng AI vẫn lấy furigana và nghĩa từ từ điển', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook()..weakPoints = [];
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showWeakPointInputSheet(context, state),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('weak-point-input')),
      '揚げる\n〜とはいえ: dẫu nói là',
    );
    await tester.pump();
    await tester.tap(find.text('Lưu 2 dòng, không dùng AI'));
    await tester.pumpAndSettle();

    final word = state.weakPoints.firstWhere((p) => p.title == '揚げる');
    expect(word.kind, WeaknessKind.vocabulary);
    expect(word.reading, 'あげる');
    expect(word.content, 'chiên, rán');
    final grammar = state.weakPoints.firstWhere((p) => p.title == '〜とはいえ');
    expect(grammar.kind, WeaknessKind.grammar);
    expect(grammar.content, 'dẫu nói là');
  });

  testWidgets('bảng tô ở chế độ Tra từ trả về từ đã tô hoặc nguyên đoạn', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    OcrHighlightResult? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => picked = await showOcrHighlightSheet(
                context,
                ocrText: 'かれは毎日、勉強します。',
                forLookup: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Tô từ cần tra'), findsOneWidget);
    expect(find.text('AI tự tìm'), findsNothing);
    expect(find.textContaining('Tạo điểm yếu'), findsNothing);

    await tester.tap(find.text('Tra nguyên đoạn'));
    await tester.pumpAndSettle();
    expect(picked?.terms, isEmpty);
    expect(picked?.text, 'かれは毎日、勉強します。');
  });

  test('furigana chỉ nằm trên phần kanji, chừa okurigana', () {
    List<String> pairs(String surface, String reading) => [
      for (final span in alignFurigana(surface, reading))
        '${surface.substring(span.start, span.end)}:${span.reading}',
    ];
    expect(pairs('勉強', 'べんきょう'), ['勉強:べんきょう']);
    expect(pairs('食べる', 'たべる'), ['食:た']);
    expect(pairs('食べ物', 'たべもの'), ['食:た', '物:もの']);
    expect(pairs('お金', 'おかね'), ['金:かね']);
    expect(pairs('ひらがな', 'ひらがな'), isEmpty);
  });

  test('furigana đặt đúng chữ trên trang', () {
    const region = Rect.fromLTWH(100, 200, 400, 100);
    // Vision reports the whole line for each character: estimate along it.
    const line = OcrLine(
      text: '私は学生',
      box: Rect.fromLTWH(0, .2, 1, .6),
      characterBoxes: [
        Rect.fromLTWH(0, .2, 1, .6),
        Rect.fromLTWH(0, .2, 1, .6),
        Rect.fromLTWH(0, .2, 1, .6),
        Rect.fromLTWH(0, .2, 1, .6),
      ],
      tokens: [
        OcrToken(start: 0, length: 1, reading: 'わたし'),
        OcrToken(start: 1, length: 1, reading: 'は'),
        OcrToken(start: 2, length: 2, reading: 'がくせい'),
      ],
    );
    final estimated = buildFuriganaMarks(
      const [line],
      region: region,
      keepInside: region,
    );
    expect(estimated.map((mark) => mark.reading), ['わたし', 'がくせい']);
    expect(estimated.first.rect.left, closeTo(100, .01));
    expect(estimated.first.rect.width, closeTo(100, .01));
    expect(estimated.first.rect.top, closeTo(220, .01));
    expect(estimated.last.rect.left, closeTo(300, .01));
    expect(estimated.last.rect.width, closeTo(200, .01));

    // Real per-character boxes win over the estimate.
    final located = buildFuriganaMarks(
      const [
        OcrLine(
          text: '山川',
          box: Rect.fromLTWH(0, 0, 1, 1),
          characterBoxes: [
            Rect.fromLTWH(0, 0, .2, 1),
            Rect.fromLTWH(.7, 0, .3, 1),
          ],
          tokens: [
            OcrToken(start: 0, length: 1, reading: 'やま'),
            OcrToken(start: 1, length: 1, reading: 'かわ'),
          ],
        ),
      ],
      region: region,
      keepInside: region,
    );
    expect(located.last.rect.left, closeTo(380, .01));
    expect(located.last.rect.width, closeTo(120, .01));

    // Words in the capture margin, outside the circled area, are left out.
    final kept = buildFuriganaMarks(
      const [line],
      region: region,
      keepInside: const Rect.fromLTWH(100, 200, 150, 100),
    );
    expect(kept.map((mark) => mark.reading), ['わたし']);
  });

  test('sửa âm dài おお mà bộ tách từ đọc thành おう', () {
    List<String> readings(String surface, String reading) => buildFuriganaMarks(
      [
        OcrLine(
          text: surface,
          box: const Rect.fromLTWH(0, 0, 1, .5),
          tokens: [
            OcrToken(start: 0, length: surface.length, reading: reading),
          ],
        ),
      ],
      region: const Rect.fromLTWH(0, 0, 100, 100),
      keepInside: const Rect.fromLTWH(0, 0, 100, 100),
    ).map((mark) => mark.reading).toList();
    expect(readings('大きい', 'おうきい'), ['おお']);
    expect(readings('通り', 'とうり'), ['とお']);
    expect(readings('多い', 'おうい'), ['おお']);
    // On'yomi compounds keep おう / とう.
    expect(readings('通学', 'つうがく'), ['つうがく']);
    expect(readings('東京', 'とうきょう'), ['とうきょう']);
  });

  testWidgets(
    'furigana còn nguyên khi đổi công cụ, chỉ mất khi tô lại và xóa',
    (tester) async {
      tester.view.physicalSize = const Size(1180, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final state = _stateWithNotebook();
      addTearDown(state.dispose);
      state.open(state.notebooks.first, page: 1);
      state.addFurigana('n3', 1, const [
        FuriganaMark(
          id: 'a',
          reading: 'わたし',
          rect: Rect.fromLTWH(200, 200, 30, 30),
        ),
        FuriganaMark(
          id: 'b',
          reading: 'やま',
          rect: Rect.fromLTWH(200, 500, 30, 30),
        ),
      ]);
      await tester.pumpWidget(NihongoNotebookApp(state: state));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('furigana-layer')), findsOneWidget);

      // Other tools and page changes leave it alone.
      await tester.tap(find.byTooltip('Tẩy'));
      await tester.pump();
      state.goToPage(2);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('furigana-layer')), findsNothing);
      state.goToPage(1);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('furigana-layer')), findsOneWidget);
      expect(state.furiganaFor('n3', 1), hasLength(2));

      final page = tester.getRect(find.byKey(const ValueKey('page-canvas')));
      Offset onPage(double x, double y) =>
          page.topLeft + Offset(x, y) * (page.width / kPageCanvasSize.width);
      Future<void> circle() async {
        final pen = TestPointer(81, PointerDeviceKind.stylus);
        await tester.sendEventToBinding(pen.down(onPage(150, 170)));
        await tester.sendEventToBinding(pen.move(onPage(250, 220)));
        await tester.sendEventToBinding(pen.move(onPage(300, 260)));
        await tester.sendEventToBinding(pen.up());
        await tester.pumpAndSettle();
      }

      await tester.ensureVisible(find.byTooltip('Furigana'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Furigana'));
      await tester.pumpAndSettle();

      // Circling it asks first; cancelling keeps it.
      await circle();
      expect(find.text('Vùng này đã có furigana'), findsOneWidget);
      // Old furigana from an earlier run can be replaced in one go.
      expect(find.widgetWithText(FilledButton, 'Làm lại'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(state.furiganaFor('n3', 1), hasLength(2));

      // Deleting only touches the circled area.
      await circle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Xóa'),
        ),
      );
      await tester.pumpAndSettle();
      expect(state.furiganaFor('n3', 1).single.reading, 'やま');
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'khung từng chữ sai thì ước lượng theo dòng, chiều cao luôn theo dòng',
    () {
      const region = Rect.fromLTWH(0, 0, 100, 100);
      // Vision puts the second character before the first and far below.
      final marks = buildFuriganaMarks(
        const [
          OcrLine(
            text: '山川',
            box: Rect.fromLTWH(0, .2, 1, .2),
            characterBoxes: [
              Rect.fromLTWH(.6, .5, .3, .3),
              Rect.fromLTWH(.1, .6, .3, .3),
            ],
            tokens: [
              OcrToken(start: 0, length: 1, reading: 'やま'),
              OcrToken(start: 1, length: 1, reading: 'かわ'),
            ],
          ),
        ],
        region: region,
        keepInside: region,
      );
      expect(marks.first.rect.left, closeTo(0, .01));
      expect(marks.last.rect.left, closeTo(50, .01));
      expect(marks.every((mark) => mark.rect.top == 20), isTrue);

      // A box twice as tall as the others is two lines merged: skipped.
      OcrLine line(String text, double top, double height) => OcrLine(
        text: text,
        box: Rect.fromLTWH(0, top, 1, height),
        tokens: [OcrToken(start: 0, length: 1, reading: 'やま')],
      );
      final merged = buildFuriganaMarks(
        [line('山', 0, .1), line('山', .2, .1), line('山', .4, .25)],
        region: region,
        keepInside: region,
      );
      expect(merged, hasLength(2));
    },
  );

  testWidgets('chỉnh sửa furigana: tô để chọn, kéo, đổi cỡ, sửa chữ, xóa', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    state.open(state.notebooks.first, page: 1);
    state.addFurigana('n3', 1, const [
      FuriganaMark(
        id: 'a',
        reading: 'いま',
        rect: Rect.fromLTWH(200, 300, 30, 30),
      ),
      FuriganaMark(
        id: 'b',
        reading: 'やま',
        rect: Rect.fromLTWH(200, 600, 30, 30),
      ),
    ]);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    final page = tester.getRect(find.byKey(const ValueKey('page-canvas')));
    final scale = page.width / kPageCanvasSize.width;
    Offset onPage(double x, double y) => page.topLeft + Offset(x, y) * scale;

    await tester.ensureVisible(find.byTooltip('Furigana'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Furigana'));
    await tester.pumpAndSettle();
    // Tapping the tool again opens the mode choice.
    await tester.tap(find.byTooltip('Furigana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chỉnh sửa furigana'));
    await tester.pumpAndSettle();
    expect(find.text('Tô quanh hoặc chạm furigana cần sửa'), findsOneWidget);

    final pen = TestPointer(91, PointerDeviceKind.stylus);
    await tester.sendEventToBinding(pen.down(onPage(150, 260)));
    await tester.sendEventToBinding(pen.move(onPage(240, 300)));
    await tester.sendEventToBinding(pen.move(onPage(290, 345)));
    await tester.sendEventToBinding(pen.up());
    await tester.pumpAndSettle();
    expect(find.text('1 furigana'), findsOneWidget);

    // Drag the selection with a finger, step by step.
    final handle = find.byKey(const ValueKey('furigana-selection'));
    final finger = await tester.startGesture(tester.getCenter(handle));
    for (var step = 0; step < 5; step++) {
      await finger.moveBy(const Offset(10, 6));
      await tester.pump();
    }
    await finger.up();
    await tester.pumpAndSettle();
    var moved = state.furiganaFor('n3', 1).firstWhere((m) => m.id == 'a');
    expect(moved.rect.left, greaterThan(200));
    expect(moved.rect.top, greaterThan(300));
    expect(
      state.furiganaFor('n3', 1).firstWhere((m) => m.id == 'b').rect.left,
      200,
    );

    await tester.tap(find.byTooltip('Furigana to hơn'));
    await tester.pump();
    moved = state.furiganaFor('n3', 1).firstWhere((m) => m.id == 'a');
    expect(moved.scale, closeTo(1.15, .001));

    await tester.tap(find.text('Sửa chữ'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('furigana-reading')),
      'きょう',
    );
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(
      state.furiganaFor('n3', 1).firstWhere((m) => m.id == 'a').reading,
      'きょう',
    );

    await tester.tap(find.widgetWithText(TextButton, 'Xóa'));
    await tester.pump();
    expect(state.furiganaFor('n3', 1).single.id, 'b');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Hoàn tác'));
    await tester.pump();
    expect(state.furiganaFor('n3', 1), hasLength(2));

    // Stored with its position, size and reading.
    final restored = FuriganaMark.fromJson(
      state.furiganaFor('n3', 1).firstWhere((m) => m.id == 'a').toJson(),
    );
    expect(restored.reading, 'きょう');
    expect(restored.scale, closeTo(1.15, .001));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'chạm để bỏ furigana đã đúng khỏi vùng chọn rồi chỉ kéo chữ sai',
    (tester) async {
      tester.view.physicalSize = const Size(1180, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final state = _stateWithNotebook();
      addTearDown(state.dispose);
      state.open(state.notebooks.first, page: 1);
      const wrong = FuriganaMark(
        id: 'wrong',
        reading: 'いま',
        rect: Rect.fromLTWH(200, 300, 30, 30),
      );
      const right = FuriganaMark(
        id: 'right',
        reading: 'やま',
        rect: Rect.fromLTWH(320, 300, 30, 30),
      );
      state.addFurigana('n3', 1, const [wrong, right]);
      await tester.pumpWidget(NihongoNotebookApp(state: state));
      await tester.pumpAndSettle();

      final page = tester.getRect(find.byKey(const ValueKey('page-canvas')));
      final scale = page.width / kPageCanvasSize.width;
      Offset onPage(Offset point) => page.topLeft + point * scale;

      await tester.ensureVisible(find.byTooltip('Furigana'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Furigana'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chỉnh sửa'));
      await tester.pumpAndSettle();

      // The area catches both words.
      final pen = TestPointer(92, PointerDeviceKind.stylus);
      await tester.sendEventToBinding(pen.down(onPage(const Offset(150, 260))));
      await tester.sendEventToBinding(pen.move(onPage(const Offset(300, 300))));
      await tester.sendEventToBinding(pen.move(onPage(const Offset(400, 345))));
      await tester.sendEventToBinding(pen.up());
      await tester.pumpAndSettle();
      expect(find.text('2 furigana'), findsOneWidget);

      // Tap the one already in place to leave it out.
      await tester.tapAt(onPage(furiganaLabelRect(right).center));
      await tester.pumpAndSettle();
      expect(find.text('1 furigana'), findsOneWidget);

      final handle = find.byKey(const ValueKey('furigana-selection'));
      final finger = await tester.startGesture(tester.getCenter(handle));
      // The first ~36 px only start the drag.
      for (var step = 0; step < 10; step++) {
        await finger.moveBy(const Offset(0, 8));
        await tester.pump();
      }
      await finger.up();
      await tester.pumpAndSettle();
      final marks = {for (final m in state.furiganaFor('n3', 1)) m.id: m};
      expect(marks['wrong']!.rect.top, greaterThan(300));
      expect(marks['right']!.rect, right.rect);

      // A pencil tap on a furigana outside the selection adds it back.
      final tap = TestPointer(93, PointerDeviceKind.stylus);
      final at = onPage(furiganaLabelRect(right).center);
      await tester.sendEventToBinding(tap.down(at));
      await tester.sendEventToBinding(tap.up());
      await tester.pumpAndSettle();
      expect(find.text('2 furigana'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('bìa vở vẽ giấy và nét viết tay của trang 1', (tester) async {
    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    state.saveStrokes('n3', [
      InkStroke(
        points: const [
          StrokePoint(Offset(40, 40), 1),
          StrokePoint(Offset(90, 60), 1),
        ],
        color: const Color(0xff000000),
        width: 3,
        tool: EditorTool.pen,
        createdAt: DateTime(2026),
      ),
    ], 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 260,
            child: NotebookCover(state: state, notebook: state.notebooks.first),
          ),
        ),
      ),
    );
    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .toList();
    final ink = painters.whereType<InkStrokesPainter>().single;
    expect(ink.strokes, hasLength(1));
    expect(painters.whereType<PaperPainter>(), hasLength(1));
  });

  testWidgets('bảng màu: vòng màu bên phải, màu mẫu và độ đậm', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Color? picked;
    double? opacity;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 600,
              child: ColorPanel(
                color: const Color(0xff1f2633),
                opacity: 1,
                onChanged: (color, value) {
                  picked = color;
                  opacity = value;
                },
                sideChildren: const [Text('Độ dày')],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('color-panel-hex')), findsNothing);
    expect(find.text('Độ dày'), findsOneWidget);
    // Wheel on the right, controls on the left.
    expect(
      tester.getCenter(find.byKey(const ValueKey('color-panel-wheel'))).dx,
      greaterThan(
        tester.getCenter(find.byKey(const ValueKey('color-panel-opacity'))).dx,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('swatch-4284927129')));
    await tester.pump();
    expect(picked?.toARGB32(), 0xff66cc99);

    // Tap the far left of the opacity track.
    final slider = find.byKey(const ValueKey('color-panel-opacity'));
    await tester.tapAt(tester.getTopLeft(slider) + const Offset(1, 14));
    await tester.pump();
    expect(opacity, closeTo(.1, .01));
    expect(find.text('10%'), findsOneWidget);
  });

  testWidgets('chỉ điều hướng trang từ hai vùng mép ngoài', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook();
    addTearDown(state.dispose);
    state.open(state.notebooks.first, page: 1);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('next-page-edge')));
    await tester.pump();
    expect(state.openPage, 2);

    await tester.tap(find.byKey(const ValueKey('previous-page-edge')));
    await tester.pump();
    expect(state.openPage, 1);
  });

  testWidgets('một ngón viết tay và hai ngón điều hướng', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook()..drawWithFinger = true;
    addTearDown(state.dispose);
    state.open(state.notebooks.first, page: 1);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    final identity = List<double>.of(controller.value.storage);
    final finger = TestPointer(40, PointerDeviceKind.touch);
    await tester.sendEventToBinding(finger.down(const Offset(600, 310)));
    await tester.sendEventToBinding(finger.move(const Offset(650, 340)));
    await tester.sendEventToBinding(finger.move(const Offset(700, 320)));
    await tester.sendEventToBinding(finger.up());
    await tester.pump();
    expect(state.strokesFor('n3', 1), hasLength(1));
    expect(controller.value.storage, equals(identity));

    final first = TestPointer(41, PointerDeviceKind.touch);
    final second = TestPointer(42, PointerDeviceKind.touch);
    await tester.sendEventToBinding(first.down(const Offset(590, 370)));
    await tester.sendEventToBinding(second.down(const Offset(670, 370)));
    await tester.sendEventToBinding(first.move(const Offset(540, 400)));
    await tester.sendEventToBinding(second.move(const Offset(720, 400)));
    await tester.sendEventToBinding(first.up());
    await tester.sendEventToBinding(second.up());
    await tester.pump();

    expect(controller.value.storage, isNot(equals(identity)));
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
    expect(state.strokesFor('n3', 1), hasLength(1));
  });

  testWidgets('khoanh vùng chọn nét, kéo di chuyển; tẩy xong tự về bút', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook()
      ..drawWithFinger = true
      ..returnToPenAfterEraser = true;
    addTearDown(state.dispose);
    state.open(state.notebooks.first, page: 1);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    Future<void> drag(List<Offset> points, int id) async {
      final pointer = TestPointer(id, PointerDeviceKind.touch);
      await tester.sendEventToBinding(pointer.down(points.first));
      for (final point in points.skip(1)) {
        await tester.sendEventToBinding(pointer.move(point));
      }
      await tester.sendEventToBinding(pointer.up());
      await tester.pump();
    }

    await drag(const [
      Offset(600, 310),
      Offset(650, 330),
      Offset(700, 320),
    ], 50);
    await drag(const [
      Offset(600, 500),
      Offset(650, 520),
      Offset(700, 510),
    ], 51);
    expect(state.strokesFor('n3', 1), hasLength(2));
    final before = state.strokesFor('n3', 1).first.points.first.offset;
    final other = state.strokesFor('n3', 1).last.points.first.offset;

    await tester.tap(find.byTooltip('Khoanh vùng'));
    await tester.pump();
    // Loop around the first stroke only.
    await drag(const [
      Offset(570, 280),
      Offset(730, 280),
      Offset(730, 360),
      Offset(570, 360),
      Offset(570, 285),
    ], 52);
    expect(find.textContaining('Đã chọn 1 nét'), findsOneWidget);

    // Drag from inside the selection moves only the selected stroke.
    await drag(const [
      Offset(650, 325),
      Offset(700, 345),
      Offset(750, 365),
    ], 53);
    // A 100×40 drag on screen, converted to the page's own space.
    final scale =
        kPageCanvasSize.width /
        tester.getRect(find.byKey(const ValueKey('page-canvas'))).width;
    final moved = state.strokesFor('n3', 1).first.points.first.offset - before;
    expect(moved.dx, closeTo(100 * scale, .5));
    expect(moved.dy, closeTo(40 * scale, .5));
    expect(state.strokesFor('n3', 1).last.points.first.offset, other);

    await tester.tap(find.text('Bỏ chọn'));
    await tester.pump();
    expect(find.textContaining('Đã chọn'), findsNothing);

    // Erasing then lifting the finger returns to the pen.
    await tester.tap(find.byTooltip('Tẩy'));
    await tester.pump();
    await drag(const [Offset(600, 620), Offset(625, 625)], 54);
    await drag(const [
      Offset(600, 660),
      Offset(650, 680),
      Offset(700, 670),
    ], 55);
    expect(state.strokesFor('n3', 1), hasLength(3));
  });
}

void _quickCheckTests() {
  testWidgets('cài đặt chọn nội dung riêng cho hai mặt flashcard', (
    tester,
  ) async {
    final state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FlashcardSettingsPanel(state: state),
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilterChip, 'Kanji').first);
    await tester.pump();
    expect(state.flashcardFrontFields, contains(FlashcardField.kanji));
    await tester.tap(find.widgetWithText(FilterChip, 'Từ / mẫu').first);
    await tester.pump();
    expect(state.flashcardFrontFields, {FlashcardField.kanji});
    expect(
      state.flashcardBackFields,
      containsAll([FlashcardField.meaning, FlashcardField.hanViet]),
    );
  });

  testWidgets('sổ điểm yếu: ôn flashcard, vuốt xóa và hoàn tác', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithNotebook()..autoSave = false;
    addTearDown(state.dispose);
    state.weakPoints = [
      WeakPoint(
        id: 'w1',
        title: '認識',
        kind: WeaknessKind.vocabulary,
        content: 'nhận thức',
        reminder: '',
        note: '',
        tags: const ['N3', '問題:文脈規定'],
        notebookId: 'n3',
        notebookTitle: 'N3 Grammar',
        page: 1,
        ocrText: '',
        createdAt: DateTime(2026, 9, 1),
        reading: 'にんしき',
        hanViet: 'NHẬN THỨC',
        mistake: 'Dễ nhầm với 意識.',
      ),
      WeakPoint(
        id: 'w2',
        title: '〜わけではない',
        kind: WeaknessKind.grammar,
        content: 'không hẳn là',
        reminder: '',
        note: '',
        tags: const ['N3'],
        notebookId: 'n3',
        notebookTitle: 'N3 Grammar',
        page: 2,
        ocrText: '',
        createdAt: DateTime(2026, 9, 2),
        sourceSentence: '嫌いなわけではない。',
      ),
    ];
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    state.goTo(AppDestination.weaknesses);
    await tester.pumpAndSettle();

    expect(find.text('Ôn tập (2)'), findsOneWidget);
    expect(find.textContaining('Dạng đề sai nhiều'), findsOneWidget);

    await tester.tap(find.text('Ôn tập (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Tạo phiên flashcard'), findsOneWidget);
    await tester.tap(find.text('Bắt đầu · 2 thẻ'));
    await tester.pumpAndSettle();
    expect(find.text('Ôn tập · 1/2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('flashcard-tap')));
    await tester.pump();
    // The flip takes 260 ms, so 130 ms is its halfway point.
    await tester.pump(const Duration(milliseconds: 130));
    final halfway = tester.widget<Transform>(
      find.byKey(const ValueKey('flashcard-rotation')),
    );
    expect(halfway.transform.storage[0].abs(), lessThan(.05));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('flashcard-tap')),
        matching: find.text('nhận thức'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('flashcard-tap')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('flashcard-tap')),
        matching: find.text('認識'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('flashcard-tap')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đã nhớ'));
    await tester.pumpAndSettle();
    expect(find.text('Ôn tập · 2/2'), findsOneWidget);
    // Swiping right rates "Đã nhớ" without flipping the card first.
    await tester.drag(
      find.byKey(const ValueKey('flashcard-swipe')),
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Xong phiên ôn tập'), findsOneWidget);
    expect(state.dueWeakPoints, isEmpty);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();

    await tester.drag(find.text('認識'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(state.weakPoints.map((item) => item.id), ['w2']);
    await tester.tap(find.text('Hoàn tác'));
    await tester.pumpAndSettle();
    expect(state.weakPoints.map((item) => item.id), ['w1', 'w2']);
  });

  testWidgets('kiểm tra nhanh: bấm đáp án trước khi AI trả về rồi được chấm', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final completer = Completer<QuickCheckResult>();
    List<QuickCheckAnswer>? wrongAnswers;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => QuickCheckSheet(
                  result: completer.future,
                  title: 'Kiểm tra nhanh đáp án',
                  initialQuestionCount: 2,
                  onWrongAnswers: (wrong) => wrongAnswers = wrong,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // The loading bar animates until the AI result arrives, so settle only
    // the sheet's entrance animation here.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Câu 1'), findsOneWidget);
    expect(find.text('Câu 2'), findsOneWidget);
    // Người học chọn lựa chọn thứ hai của câu 1 khi AI còn đang giải.
    await tester.tap(find.widgetWithText(ChoiceChip, '2').first);
    await tester.pump();

    QuickCheckChoice choice(String label, bool correct) => QuickCheckChoice(
      label: label,
      text: 'đáp án $label',
      correct: correct,
      reason: correct ? 'Hợp ngữ cảnh' : 'Sai collocation',
    );
    completer.complete(
      QuickCheckResult(
        questions: [
          QuickCheckQuestion(
            label: '1',
            stem: '彼は（　）。',
            choices: [
              choice('1', false),
              choice('2', false),
              choice('3', true),
              choice('4', false),
            ],
            answer: '3',
            explanation: 'Vì ngữ cảnh.',
            point: 'わけではない',
            kind: WeaknessKind.grammar,
            questionType: JlptQuestionType.grammarForm,
          ),
          QuickCheckQuestion(
            label: '2',
            stem: '別の問題',
            choices: [choice('1', true), choice('2', false)],
            answer: '1',
            explanation: '',
            point: '',
            kind: WeaknessKind.vocabulary,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Đáp án đúng: 3. đáp án 3'), findsOneWidget);
    expect(find.text('Đáp án đúng: 1. đáp án 1'), findsOneWidget);
    expect(find.text('Sai collocation'), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    expect(find.text('Đúng 0/1 · 2 câu'), findsOneWidget);

    await tester.tap(find.text('Thêm câu này vào Điểm yếu').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu câu đã tích vào Điểm yếu (1)'));
    await tester.pumpAndSettle();
    expect(wrongAnswers, hasLength(1));
    expect(wrongAnswers!.single.pickedIndex, 1);
    expect(wrongAnswers!.single.learnerContext, contains('đáp án đúng là 3'));
  });
}

class _FakeDictionary implements DictionaryRepository {
  static const _words = {
    '揚げる': DictionaryEntry(
      word: '揚げる',
      reading: 'あげる',
      meaning: 'chiên, rán',
      level: 'N3',
      hanViet: 'DƯƠNG',
    ),
    '食べる': DictionaryEntry(
      word: '食べる',
      reading: 'たべる',
      meaning: 'ăn',
      level: 'N5',
      hanViet: 'THỰC',
    ),
  };

  @override
  Future<DictionaryEntry?> lookupBasic(String text) async =>
      _words[text.trim()];
  @override
  Future<DictionaryEntry?> lookupExact(String text) => lookupBasic(text);
  @override
  Future<DictionaryEntry?> lookupNormalized(String text) => lookupBasic(text);
  @override
  Future<List<DictionaryEntry>> search(String text, {int limit = 30}) async => [
    ?_words[text.trim()],
  ];
  @override
  Future<List<KanjiEntry>> kanjiIn(String text) async => const [];
}

AppState _stateWithNotebook() {
  final state = AppState()..dictionary = _FakeDictionary();
  state.addNotebook(
    const NotebookData(
      id: 'n3',
      title: 'N3 Grammar',
      type: 'Vở ghi',
      pages: 12,
      color: Color(0xff5269a8),
      paperStyle: PaperStyle.grid,
    ),
  );
  return state;
}

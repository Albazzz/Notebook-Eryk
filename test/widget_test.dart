import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteeryk/app.dart';
import 'package:noteeryk/app_state.dart';
import 'package:noteeryk/models.dart';
import 'package:noteeryk/review.dart';
import 'package:noteeryk/screens/settings_screen.dart';
import 'package:flutter/rendering.dart';
import 'package:noteeryk/widgets/color_panel.dart';
import 'package:noteeryk/widgets/ocr_highlight_sheet.dart';
import 'package:noteeryk/widgets/quick_check_sheet.dart';

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
    final eraserPoint = tester.getTopLeft(pageInk) + const Offset(200, 200);
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

  testWidgets('bảng màu nhận mã hex, màu mẫu và độ đậm', (tester) async {
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
              width: 420,
              child: ColorPanel(
                color: const Color(0xff1f2633),
                opacity: 1,
                onChanged: (color, value) {
                  picked = color;
                  opacity = value;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('color-panel-hex')),
      '66CC99',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(picked?.toARGB32(), 0xff66cc99);
    expect(find.text('102'), findsOneWidget); // R
    expect(find.text('204'), findsOneWidget); // G

    // Drag the opacity thumb to the far left.
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
    await tester.pump(const Duration(milliseconds: 280));
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
    await tester.tap(find.byKey(const ValueKey('flashcard-tap')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đã nhớ'));
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

AppState _stateWithNotebook() {
  final state = AppState();
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

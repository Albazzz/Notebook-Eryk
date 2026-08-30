import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteeryk/app.dart';
import 'package:noteeryk/app_state.dart';
import 'package:noteeryk/models.dart';

void main() {
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

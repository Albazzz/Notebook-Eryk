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

    await tester.pumpWidget(NihongoNotebookApp(state: AppState()));
    await tester.pumpAndSettle();

    expect(find.text('Vở của tôi'), findsWidgets);
    expect(find.text('N3 Grammar'), findsOneWidget);
    expect(find.text('Tạo mới'), findsOneWidget);
  });

  testWidgets('chạm đồng thời hai ngón hoàn tác nét vừa vẽ', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState();
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

  testWidgets('bấm thumbnail để chuyển nhanh đến trang', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState();
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

    final state = AppState();
    state.open(state.notebooks.first);
    await tester.pumpWidget(NihongoNotebookApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thước'));
    await tester.pump();
    expect(
      find.text('Dùng Bút để kẻ · Bấm Thước lần nữa để ẩn'),
      findsOneWidget,
    );

    await tester.tap(find.text('Thước'));
    await tester.pump();
    expect(find.text('Dùng Bút để kẻ · Bấm Thước lần nữa để ẩn'), findsNothing);
  });

  testWidgets('tra từ nhanh mở ngay trên thanh công cụ và không chặn bút', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState();
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

    final state = AppState();
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

    final state = AppState();
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
}

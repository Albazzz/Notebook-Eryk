import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:noteeryk/app_state.dart';
import 'package:noteeryk/models.dart';

void main() {
  test('gán một model cho nhiều chức năng', () {
    final state = AppState();
    addTearDown(state.dispose);
    const model = OpenRouterModel(
      id: 'example/model',
      name: 'Model dùng chung',
      contextLength: 32000,
      vision: false,
      free: false,
    );

    state.setModelForSlots(const {
      AiModelSlot.translate,
      AiModelSlot.explain,
    }, model);

    expect(state.modelIds[AiModelSlot.translate], model.id);
    expect(state.modelIds[AiModelSlot.explain], model.id);
    expect(state.modelIds[AiModelSlot.solve], isNull);
  });

  test('ảnh nền và ảnh chèn có vị trí độc lập', () {
    final state = AppState();
    addTearDown(state.dispose);

    state.attachImages('book', 1, const ['/tmp/pdf-page.png']);
    state.attachImages('book', 1, const [
      '/tmp/photo.png',
    ], asPageBackground: false);
    final placements = state.imagePlacementsForPage('book', 1);
    final background = placements.singleWhere((item) => item.isBackground);
    final editable = placements.singleWhere((item) => !item.isBackground);

    expect(background.rect, const Rect.fromLTWH(0, 0, 1, 1));
    expect(editable.rect.width, lessThan(1));

    state.updateImagePlacement(
      editable.copyWith(rect: const Rect.fromLTWH(.2, .2, .4, .3)),
    );
    expect(
      state
          .imagePlacementsForPage('book', 1)
          .singleWhere((item) => item.id == editable.id)
          .rect,
      const Rect.fromLTWH(.2, .2, .4, .3),
    );

    state.removePageImage('book', 1, editable.id);
    expect(state.imagesForPage('book', 1), const ['/tmp/pdf-page.png']);
  });

  test('mỗi vở giữ cài đặt giấy riêng', () {
    final state = AppState();
    addTearDown(state.dispose);
    const notebook = NotebookData(
      id: 'book',
      title: 'N3',
      type: 'Vở ghi',
      pages: 1,
      color: Color(0xff000000),
      paperStyle: PaperStyle.lined,
      paperLineOpacity: .12,
    );
    state.addNotebook(notebook);
    state.updateNotebook(
      notebook.copyWith(paperStyle: PaperStyle.grid, paperLineOpacity: .28),
    );

    expect(state.notebooks.single.paperStyle, PaperStyle.grid);
    expect(state.notebooks.single.paperLineOpacity, .28);
  });

  test('crop ảnh thay đường dẫn nhưng giữ nguyên vị trí', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.attachImages('book', 1, const [
      '/tmp/original.png',
    ], asPageBackground: false);
    final placement = state.imagePlacementsForPage('book', 1).single;

    state.replacePageImage('book', 1, placement, '/tmp/cropped.png');

    final updated = state.imagePlacementsForPage('book', 1).single;
    expect(updated.path, '/tmp/cropped.png');
    expect(updated.rect, placement.rect);
  });

  test('nét viết được lưu riêng theo từng trang', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.autoSave = false;
    final stroke = InkStroke(
      points: [StrokePoint(Offset(10, 10), 1)],
      color: Color(0xff000000),
      width: 3,
      tool: EditorTool.pen,
      createdAt: DateTime(2026, 1, 1),
    );
    final otherStroke = InkStroke(
      points: [StrokePoint(Offset(20, 20), 1)],
      color: Color(0xffff0000),
      width: 3,
      tool: EditorTool.pen,
      createdAt: DateTime(2026, 1, 1),
    );

    state.saveStrokes('book', [stroke], 1);
    state.saveStrokes('book', [otherStroke], 2);

    expect(state.strokesFor('book', 1), [stroke]);
    expect(state.strokesFor('book', 2), [otherStroke]);
  });
}

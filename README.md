# Note Eryk

Ứng dụng notebook học tiếng Nhật tối ưu cho tablet và bút cảm ứng, được triển khai từ `lib/idea.md`.

## Chạy project

```bash
flutter pub get
flutter run
```

Kiểm tra chất lượng:

```bash
flutter analyze
flutter test
flutter build apk --debug
```

APK debug được tạo tại `build/app/outputs/flutter-apk/app-debug.apk`.

## Chức năng đã có

- Thư viện vở, tạo vở và luồng nhập PDF.
- Editor tablet với page rail, Pen thư pháp làm mượt, pressure, Highlight, Tẩy, Thước, undo/redo, zoom và lưu stroke vector.
- Chạm đồng thời hai ngón trên canvas để hoàn tác nét vừa vẽ.
- Gesture vùng chọn riêng cho Tra từ, AI Dịch, AI Giải thích và Điểm yếu; kết quả AI là popup có thể kéo và đóng.
- Tra từ ngoại tuyến qua `DictionaryRepository`, tách khỏi AI.
- OpenRouter service dùng chung, tải model động, tùy chọn JLPT/ngôn ngữ.
- API key lưu bằng secure storage và không hiển thị lại sau khi lưu.
- Tạo, sửa, lọc, xóa Điểm yếu; mở lại đúng vở/trang nguồn.
- Light/dark mode và layout thích nghi tablet/khổ hẹp.

## Điểm tích hợp cần dữ liệu/native service

- OCR tiếng Nhật dùng ML Kit Text Recognition v2 trên thiết bị. App crop đúng vùng khoanh, lưu PNG nguồn và OCR text cùng Điểm yếu.
- `LocalDictionaryRepository` có dữ liệu mẫu. Hãy thay implementation bằng database Nhật–Việt thực tế của sản phẩm.
- Sheet nhập PDF đã có UX và mô hình notebook; chọn file/render từng trang PDF cần nối plugin PDF/file picker trong giai đoạn tích hợp thiết bị.

OpenRouter chỉ được gọi khi người dùng đã cấu hình key/model và chủ động khoanh vùng bằng công cụ AI. Tra từ không đi qua OpenRouter.

## Chạy trên iPad

APK Android không cài trực tiếp được trên iPad. Cần build iOS trên macOS có Xcode, hoặc dùng dịch vụ build macOS như Codemagic/GitHub Actions.

Trên máy Mac:

```bash
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace
```

Trong Xcode, chọn Team Apple Developer, đổi Bundle Identifier nếu cần, cắm iPad và bấm Run. Để gửi bản beta cho iPad, archive rồi upload lên App Store Connect và cài qua TestFlight. Project đã bật iPad và đặt iOS Deployment Target 15.5 vì ML Kit yêu cầu tối thiểu phiên bản này.

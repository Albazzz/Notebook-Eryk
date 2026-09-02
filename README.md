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

- OCR tiếng Nhật trên iPad dùng Apple Vision chạy trên thiết bị. App crop đúng vùng khoanh, lưu PNG nguồn và OCR text cùng Điểm yếu.
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

Trong Xcode, chọn Team Apple Developer, đổi Bundle Identifier nếu cần, cắm iPad và bấm Run. Để gửi bản beta cho iPad, archive rồi upload lên App Store Connect và cài qua TestFlight. Project đã bật iPad và đặt iOS Deployment Target 15.5; OCR Vision chạy trực tiếp trên thiết bị.

### Share Extension trên iPad

Target `ShareExtension` làm Note Eryk xuất hiện trong Share Sheet của Files và Photos. Tệp được đưa vào App Group rồi app mở hộp thoại xem trước khi nhập. Trong Xcode:

1. Chọn cùng một Apple Developer Team cho `Runner` và `ShareExtension`.
2. Đăng ký App Group `group.com.example.noteeryk` trong Apple Developer và bật group này cho cả hai App ID.
3. Nếu đổi bundle identifier, đổi đồng bộ bundle ID của extension, App Group và hằng `appGroup` trong hai file Swift.
4. Xóa app cũ khỏi iPad rồi cài lại. Trong Files/Photos chọn Share → More nếu cần → bật **Nhập vào Note Eryk**.

iPadOS không cho Share Extension tự mở app chứa nó; tệp đã chia sẻ sẽ được app nhận ở lần mở hoặc quay lại foreground kế tiếp.

### Cài IPA bằng Sideloadly

Workflow Codemagic tạo `Notebook-Eryk-unsigned.ipa` để Sideloadly ký bằng Apple ID. Khi cài:

1. Giữ **Remove app extensions** ở trạng thái tắt để `ShareExtension.appex` không bị xóa.
2. Có thể dùng Automatic Bundle ID; app đọc App Group được cấp trong provisioning profile sau khi Sideloadly ký.
3. Dùng lại cùng Apple ID và bundle ID khi auto-refresh để cập nhật đè lên bản cũ.
4. Tài khoản miễn phí cần ký lại trong 7 ngày và Share Extension dùng thêm một App ID.

Codemagic đồng bộ version của extension với app, nhúng entitlement App Group vào chữ ký ad-hoc rồi chạy `tool/validate_ios_ipa.py` trên chính IPA. Chữ ký ad-hoc này chỉ giữ metadata để Sideloadly cấp profile và ký lại, không dùng để cài trực tiếp. Pipeline sẽ dừng nếu thiếu `CFBundleVersion`, extension không nằm trong app, bundle ID không đúng quan hệ cha–con, executable/chữ ký metadata bị thiếu hoặc bản build không phải iPad-only.

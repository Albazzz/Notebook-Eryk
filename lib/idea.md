# Prompt triển khai app Notebook học tiếng Nhật trên iPad

Hãy xây dựng một ứng dụng **Notebook học tiếng Nhật dành cho iPad**, tập trung vào trải nghiệm **viết trực tiếp bằng Apple Pencil/bút cảm ứng**.

Đây không phải app chat AI và cũng không phải app nhập liệu bằng bàn phím là chính.

**Trọng tâm quan trọng nhất: người dùng viết, tô, khoanh và thao tác trực tiếp bằng bút trên trang notebook.**

Không được thiết kế flow theo kiểu người dùng phải chọn text bằng chuột, copy text hoặc nhập prompt thủ công.

---

# 1. Mục tiêu sản phẩm

Ứng dụng hoạt động giống một notebook thông thường trên iPad nhưng được bổ sung các công cụ chuyên cho học tiếng Nhật:

* Viết trực tiếp bằng Apple Pencil.
* Highlight.
* Tẩy.
* Thước.
* Mở PDF và viết trực tiếp lên PDF.
* Tra từ nhanh bằng database có sẵn.
* Dịch nhanh bằng AI.
* AI giải thích tiếng Nhật.
* AI giải bài tập.
* Lưu nhanh nội dung người dùng cảm thấy yếu.
* Người dùng tự nhập OpenRouter API Key.
* Người dùng tự chọn model AI muốn sử dụng.

Nguyên tắc thiết kế:

> **Notebook trước, AI sau.**

AI chỉ xuất hiện khi người dùng chủ động dùng công cụ AI.

---

# 2. Trải nghiệm viết bằng bút là yêu cầu bắt buộc

Toàn bộ canvas phải được tối ưu cho:

**Apple Pencil / stylus input.**

Người dùng phải có thể đặt tay lên màn hình trong lúc viết mà không làm canvas di chuyển hoặc tạo nét ngoài ý muốn.

Cần hỗ trợ:

* Palm rejection.
* Pressure sensitivity nếu thiết bị hỗ trợ.
* Nét bút mượt.
* Không bị giật khi viết nhanh.
* Độ trễ thấp.
* Zoom canvas nhưng vẫn giữ nét chính xác.
* Pan bằng ngón tay.
* Viết bằng Pencil.
* Undo/redo.
* Lưu lại stroke vector nếu có thể.

Ưu tiên:

**Pencil = viết**

**Finger = di chuyển / zoom**

Có thể có setting để thay đổi hành vi này.

Không xây dựng canvas chỉ dựa trên mouse event.

Phải hỗ trợ pointer/stylus event phù hợp với iPad.

---

# 3. Thanh công cụ chính

Thanh công cụ notebook gồm:

**Bút | Highlight | Tẩy | Thước | Tra từ | AI Dịch | AI Giải thích/Giải bài | Điểm yếu**

Không làm quá nhiều tool gây rối.

---

# 4. Bút viết

Chỉ cần một loại bút viết chính:

**Bút thư pháp**

Người dùng có thể chỉnh:

* Màu.
* Độ dày.
* Độ đậm.
* Có thể dùng lực Apple Pencil để điều chỉnh nét nếu hỗ trợ.

Nét phải có cảm giác tự nhiên như viết bằng bút thật.

Không cần nhiều loại pen phức tạp trong bản đầu tiên.

---

# 5. Highlight

Highlight là một công cụ riêng.

Người dùng dùng Apple Pencil quẹt lên nội dung.

Highlight:

* Có transparency.
* Không che chữ phía dưới.
* Có nhiều màu.
* Có thể chỉnh độ dày.

Đây là highlight thông thường, không liên quan AI.

---

# 6. Tẩy

Tẩy bằng Apple Pencil.

Có thể hỗ trợ hai chế độ:

* Xóa một phần nét.
* Xóa cả stroke.

Không cần giao diện phức tạp.

---

# 7. Thước

Có một công cụ thước đơn giản để:

* Kẻ đường thẳng.
* Gạch dưới.
* Vẽ bảng.
* Chia vùng ghi chú.

Người dùng vẫn dùng Apple Pencil để kéo đường.

---

# 8. Công cụ Tra từ bằng Database

Đây là công cụ rất quan trọng nhưng **KHÔNG sử dụng AI**.

Nó hoạt động giống một cây bút highlight đặc biệt.

Người dùng:

1. Chọn công cụ **Tra từ**.
2. Dùng Apple Pencil tô/quẹt qua đúng một từ hoặc cụm từ tiếng Nhật.
3. Khi nhấc bút, app lấy đúng vùng vừa tô.
4. OCR nội dung.
5. Dùng nội dung OCR để tìm trong database từ vựng có sẵn.
6. Hiển thị kết quả ngay cạnh vùng vừa tô.

Ví dụ:

Người dùng đang đọc:

**この問題について検討する必要があります。**

Người dùng không biết:

**検討**

Người dùng chọn:

**Tra từ**

Sau đó dùng Apple Pencil quẹt qua:

**検討**

App nhận dạng:

`検討`

Sau đó tìm trong DB.

Popup:

### 検討

**けんとう**

Danh từ / する-verb

**Xem xét, cân nhắc**

Ví dụ:

**もう一度検討します。**

→ Tôi sẽ xem xét lại.

Không gọi OpenRouter.

Không gửi dữ liệu cho AI.

Không phân tích toàn bộ câu.

Không tự tìm tất cả từ trong câu.

---

# 9. Quy tắc quan trọng của Tra từ

Người dùng đã biết mình muốn tra từ nào.

Vì vậy công cụ không cần tự động phát hiện từ.

Flow phải là:

**Thấy từ không biết → tô bằng bút → nghĩa hiện ra.**

Không làm:

**Khoanh câu → AI tìm từ → chọn từ → tra.**

Như vậy quá chậm.

---

# 10. Nếu người dùng tô một dạng biến đổi

Ví dụ người dùng tô:

**考えられる**

App OCR:

`考えられる`

Hệ thống có thể:

1. Tìm chính xác `考えられる`.
2. Nếu không có, thử đưa về dạng từ điển.
3. Tìm:

`考える`

Popup có thể hiển thị:

### 考える

**かんがえる**

Suy nghĩ / cân nhắc

**Dạng được chọn:**

考えられる

**Dạng khả năng**

→ Có thể suy nghĩ.

Việc phân tích dạng từ có thể dùng tokenizer/morphological analyzer hoặc dữ liệu DB.

Không cần gọi AI.

---

# 11. Tra Kanji bằng cùng công cụ

Nếu người dùng chỉ tô một Kanji:

**考**

DB trả về:

### 考

Onyomi:

**コウ**

Kunyomi:

**かんが・える**

Nghĩa:

**Suy nghĩ / cân nhắc**

Có thể hiển thị:

* JLPT.
* Số nét.
* Từ phổ biến chứa Kanji đó.

Vẫn không dùng AI.

---

# 12. AI Dịch

AI Dịch là một công cụ khác hoàn toàn với Tra từ.

Người dùng chọn:

**AI Dịch**

Sau đó dùng Apple Pencil **kéo một vùng hình chữ nhật** quanh câu hoặc đoạn muốn dịch.

Ví dụ:

┌────────────────────────────────────┐
│ 努力したからといって、             │
│ 必ず成功するわけではない。         │
└────────────────────────────────────┘

Khi người dùng nhấc Pencil:

1. App lấy ảnh vùng hình chữ nhật.
2. OCR nội dung nếu cần.
3. Gửi nội dung sang OpenRouter.
4. Sử dụng model mà người dùng đã chọn trong Settings.
5. Hiển thị bản dịch gần vùng vừa chọn.

Ví dụ:

### Bản dịch

Không phải cứ nỗ lực thì nhất định sẽ thành công.

Có thể có:

**Ghim vào trang**

**Sao chép**

**Đóng**

---

# 13. Không làm AI Dịch giống chatbot

Không mở một màn hình chat lớn.

Không yêu cầu người dùng nhập:

> “Dịch câu này giúp tôi.”

Chỉ cần:

**Chọn bút AI Dịch → khoanh bằng Pencil → có kết quả.**

---

# 14. AI Giải thích / Giải bài

Đây là một công cụ AI duy nhất.

Người dùng chọn:

**AI Giải thích / Giải bài**

Sau đó dùng Apple Pencil kéo vùng hình chữ nhật quanh nội dung.

Có thể khoanh:

* Một câu.
* Một đoạn.
* Một câu ngữ pháp.
* Một bài trắc nghiệm.
* Câu hỏi + đáp án.
* Ghi chú của giáo viên.
* Nội dung PDF.

AI tự xác định nội dung cần:

**Giải thích**

hay:

**Giải bài**

---

# 15. Ví dụ AI giải thích

Người dùng khoanh:

**日本語が話せるからといって、日本人と同じように考えられるわけではない。**

AI trả về:

### Nghĩa

Không phải cứ nói được tiếng Nhật thì có thể suy nghĩ giống người Nhật.

### 〜からといって

Chỉ vì A không có nghĩa là B.

### 〜わけではない

Không hẳn là...

Không có nghĩa là...

### Tách câu

**日本語が話せる**

→ Có thể nói tiếng Nhật.

**からといって**

→ Chỉ vì...

**日本人と同じように**

→ Giống người Nhật.

**考えられる**

→ Có thể suy nghĩ.

**わけではない**

→ Không có nghĩa là...

Kết quả phải:

* Ngắn.
* Có cấu trúc.
* Dễ đọc.
* Không giống một đoạn chat dài.

---

# 16. Ví dụ AI giải bài

Người dùng dùng Pencil khoanh:

**日本に10年住んでいるからといって、日本語が＿＿＿。**

A. 上手なはずだ
B. 上手とは限らない
C. 上手に違いない
D. 上手になった

AI phải trả:

### Đáp án

**B. 上手とは限らない**

### Vì sao?

「からといって」 mang nghĩa:

> Chỉ vì A không có nghĩa chắc chắn B.

### Vì sao A không phù hợp?

「はずだ」

→ Mang nghĩa kỳ vọng/chắc là.

### Vì sao C không phù hợp?

「に違いない」

→ Mang nghĩa chắc chắn.

Không chỉ trả về:

**Đáp án B.**

Mục tiêu là giúp người học hiểu.

---

# 17. Trình độ JLPT

Trong Settings, người dùng có thể đặt trình độ:

**N5 / N4 / N3 / N2 / N1**

Thông tin này được đưa vào prompt AI.

Ví dụ người dùng đặt:

**N3**

AI ưu tiên giải thích bằng kiến thức dễ hiểu đối với người N3.

Không dùng quá nhiều thuật ngữ khó.

Ngôn ngữ giải thích mặc định:

**Tiếng Việt.**

---

# 18. Công cụ Điểm yếu

Điểm yếu cũng sử dụng **Apple Pencil**.

Người dùng không nhập điểm yếu bằng form từ đầu.

Luồng:

1. Chọn công cụ **Điểm yếu**.
2. Pencil chuyển sang chế độ chọn vùng.
3. Người dùng kéo một **hình chữ nhật** quanh phần kiến thức mình cảm thấy yếu.
4. App lấy vùng đó.
5. OCR nội dung.
6. Gửi vùng + OCR text sang AI.
7. AI tạo một bản nháp Điểm yếu.
8. Người dùng được chỉnh sửa.
9. Chỉ khi bấm **Lưu** thì mới lưu.

---

# 19. Điểm yếu tuyệt đối không tự lưu ngay

Ví dụ người dùng khoanh:

┌──────────────────────────────────────┐
│ 〜わけではない                       │
│ Không hẳn là / không có nghĩa là     │
│ Hay nhầm với わけがない              │
└──────────────────────────────────────┘

AI tạo:

### Thêm điểm yếu

**Tên**

Phân biệt わけではない / わけがない

**Loại**

Ngữ pháp

**Nội dung**

わけではない = không hẳn là / không có nghĩa là.

**Điểm cần nhớ**

Dễ nhầm với わけがない.

**Ghi chú**

Cần xem lại sự khác nhau giữa hai mẫu.

Người dùng có thể sửa tất cả các trường.

Sau đó:

**Lưu**

hoặc:

**Hủy**

---

# 20. Người dùng luôn có quyền chỉnh sửa

Trước khi lưu Điểm yếu, cho phép sửa:

* Tên.
* Loại.
* Nội dung.
* Ghi chú.
* Điểm cần nhớ.
* Tag.

AI chỉ có nhiệm vụ:

> Tạo bản nháp giúp người dùng đỡ phải nhập lại bằng tay.

AI không quyết định nội dung cuối cùng.

---

# 21. Lưu vùng ảnh gốc của Điểm yếu

Khi lưu, nên lưu:

* Thumbnail vùng người dùng đã khoanh.
* OCR text.
* Nội dung đã chỉnh sửa.
* Notebook ID.
* Page ID.
* Tọa độ vùng trên trang.

Ví dụ một Điểm yếu:

### 使役受身

**Ngữ pháp**

> Hay nhầm cách chia động từ nhóm I.

**Nguồn**

N3 Grammar · Trang 12

Có nút:

**Xem trong vở**

Khi bấm, app mở đúng notebook, đúng trang và đưa viewport tới đúng khu vực mà người dùng đã khoanh trước đó.

---

# 22. Trang Điểm yếu

Có một màn hình:

**Điểm yếu**

Hiển thị những mục mà người dùng đã chủ động lưu.

Có filter:

**Tất cả | Ngữ pháp | Từ vựng | Kanji | Đọc hiểu | Khác**

Ví dụ:

### わけではない / わけがない

Ngữ pháp

> Hay nhầm nghĩa hai mẫu này.

---

### 使役受身

Ngữ pháp

> Hay quên cách chia nhóm I.

---

### 認識

Từ vựng

> Hay quên cách đọc にんしき.

Mỗi mục có:

**Mở | Sửa | Xem nguồn | Xóa**

Có thể bổ sung **Luyện bằng AI** sau.

---

# 23. OpenRouter

Tất cả chức năng AI sử dụng:

**OpenRouter API**

App không hard-code một model cụ thể.

Người dùng tự nhập:

**OpenRouter API Key**

và tự chọn:

**Model**

---

# 24. Settings AI

Tạo:

**Settings → AI**

Bao gồm:

### Provider

OpenRouter

### API Key

Input dạng password.

Sau khi lưu:

`••••••••••••`

Không hiển thị lại toàn bộ key.

Có:

**Test connection**

---

### Model

Có ô:

**Search model...**

Người dùng chọn model OpenRouter muốn sử dụng.

Lưu `model_id`.

---

### JLPT Level

N5
N4
N3
N2
N1

---

### Explanation Language

Mặc định:

**Vietnamese**

---

# 25. Một model chung trong bản đầu

Phiên bản đầu chỉ cần:

**Một model OpenRouter dùng chung cho tất cả chức năng AI.**

Ví dụ:

* AI Dịch.
* AI Giải thích.
* AI Giải bài.
* AI tạo Điểm yếu.

Tất cả lấy:

`settings.selectedModel`

Không hard-code model trong từng feature.

Sau này mới thêm:

**Advanced AI Settings**

để chọn model khác nhau cho từng tác vụ.

---

# 26. Bảo mật API Key

OpenRouter API Key là key của người dùng.

Không:

* Log key.
* Hiển thị key đầy đủ.
* Gửi key vào analytics.
* Gửi key vào DB ứng dụng nếu không cần.
* Nhúng key trong notebook.

Lưu key bằng secure storage của thiết bị.

Người dùng có thể:

**Thay key**

hoặc:

**Xóa key**

bất cứ lúc nào.

---

# 27. App vẫn dùng được nếu không có AI Key

Nếu chưa nhập OpenRouter API Key:

Người dùng vẫn dùng được:

* Notebook.
* Bút.
* Highlight.
* Tẩy.
* Thước.
* PDF.
* Tra từ bằng DB.

Chỉ các chức năng:

**AI Dịch**

**AI Giải thích/Giải bài**

**AI hỗ trợ tạo Điểm yếu**

mới yêu cầu OpenRouter.

Nếu chưa có key và người dùng chọn AI:

Hiện:

> Chưa thiết lập OpenRouter.

Nút:

**Thiết lập AI**

đưa tới:

**Settings → AI**

---

# 28. Khác biệt giữa 4 công cụ thông minh

Phải giữ rõ hành vi sau:

### Tra từ DB

**Apple Pencil tô đúng một từ/cụm từ**

→ OCR

→ DB

→ popup nghĩa.

Không AI.

---

### AI Dịch

**Apple Pencil kéo hình chữ nhật quanh câu/đoạn**

→ OCR

→ OpenRouter

→ dịch.

---

### AI Giải thích/Giải bài

**Apple Pencil kéo hình chữ nhật quanh nội dung**

→ OCR / ảnh

→ OpenRouter

→ phân tích.

---

### Điểm yếu

**Apple Pencil kéo hình chữ nhật quanh nội dung**

→ OCR / ảnh

→ OpenRouter tạo bản nháp

→ người dùng chỉnh sửa

→ lưu.

---

# 29. Interaction bằng Apple Pencil

Cần chú ý rất kỹ phần này khi code.

Khi công cụ hiện tại là:

### Pen

Pencil tạo stroke.

### Highlight

Pencil tạo highlight stroke.

### Eraser

Pencil xóa stroke.

### Tra từ

Pencil quẹt/tô một vùng nhỏ như highlighter.

Khi Pencil được nhấc lên:

→ crop vùng vừa tô
→ OCR
→ lookup DB.

### AI Dịch

Pencil drag từ điểm A đến B để tạo rectangle.

Khi nhấc Pencil:

→ hoàn thành rectangle
→ crop vùng
→ xử lý.

### AI Giải thích

Tương tự:

→ rectangle selection.

### Điểm yếu

Tương tự:

→ rectangle selection.

Không để selection tool vô tình viết nét lên notebook.

---

# 30. Feedback khi đang dùng Pencil

Khi người dùng kéo vùng AI:

Hiển thị rectangle với border nhẹ.

Ví dụ:

```text
╭───────────────────────╮
│                       │
│  vùng đang được chọn  │
│                       │
╰───────────────────────╯
```

Khi nhấc Pencil:

Có animation nhẹ:

**Scanning...**

Không mở modal toàn màn hình ngay.

Kết quả nên xuất hiện gần vùng người dùng vừa thao tác.

---

# 31. Không phá nội dung gốc

Các công cụ AI và Tra từ không được tự thay đổi nội dung notebook.

Ví dụ:

Người dùng dùng AI Dịch.

Kết quả chỉ là popup tạm thời.

Chỉ khi bấm:

**Ghim vào trang**

thì mới tạo một object mới trên canvas.

Nếu đóng popup:

Notebook trở lại như cũ.

---

# 32. PDF

Người dùng có thể import PDF.

PDF trở thành nền trang.

Người dùng có thể:

* Viết bằng Pencil lên trên.
* Highlight.
* Tẩy annotation.
* Tra từ.
* Khoanh AI Dịch.
* Khoanh AI Giải bài.
* Khoanh Điểm yếu.

Không chỉnh trực tiếp nội dung gốc PDF.

Annotations nằm thành layer riêng phía trên PDF.

---

# 33. Cấu trúc layer của một trang

Một page có thể hiểu như:

```text
Page
│
├── Background
│   ├── Blank paper
│   └── PDF page
│
├── Drawing Layer
│   ├── Pen strokes
│   ├── Highlights
│   └── Shapes
│
├── Annotation Layer
│   ├── Pinned AI translations
│   └── Notes
│
└── Interaction Layer
    ├── Dictionary selection
    ├── AI rectangle
    └── Weak-point rectangle
```

Selection rectangle không được lưu vào drawing layer.

---

# 34. Dữ liệu notebook

Có thể tổ chức:

```text
Notebook
 └── Pages
      ├── Background
      ├── Strokes
      ├── Highlights
      ├── Annotations
      └── AI Pinned Results
```

Mỗi stroke nên lưu:

* Points.
* Pressure nếu có.
* Width.
* Tool.
* Timestamp.
* Color.

Không nên lưu toàn bộ trang thành một ảnh duy nhất sau mỗi lần viết.

---

# 35. Database tiếng Nhật

Database tra từ đã có sẵn.

Tạo abstraction kiểu:

```text
DictionaryRepository

lookupExact(text)
lookupNormalized(text)
lookupKanji(character)
```

UI không phụ thuộc trực tiếp database implementation.

Flow:

```text
Pencil selection
      ↓
OCR
      ↓
normalize Japanese
      ↓
DictionaryRepository
      ↓
result
      ↓
dictionary popup
```

Không đưa OpenRouter vào flow này.

---

# 36. AI service

Tạo một lớp AI dùng chung:

```text
AIService
```

Nhận:

* OpenRouter key.
* Model ID.
* Task.
* Text.
* Image nếu cần.
* JLPT level.
* Output language.

Task có thể là:

```text
translate
explain
solve
create_weak_point
```

Không gọi OpenRouter trực tiếp từ từng widget UI.

---

# 37. OCR service

Tách riêng:

```text
OCRService
```

Có nhiệm vụ nhận:

**Image region**

và trả:

**recognized text**

Các feature:

* Dictionary.
* AI Translate.
* AI Explain.
* Weak Point.

đều dùng chung OCRService.

---

# 38. Tối ưu việc gọi AI

Không gửi toàn bộ trang notebook sang OpenRouter.

Chỉ gửi:

**vùng người dùng vừa khoanh.**

Ví dụ trang là A4 nhưng người dùng chỉ khoanh một câu:

→ crop đúng rectangle đó.

Điều này giúp:

* Nhanh hơn.
* Ít token hơn.
* Ít upload hơn.
* Riêng tư hơn.
* AI tập trung đúng nội dung.

---

# 39. Luồng sử dụng thực tế

Người dùng đang học trên PDF.

Câu:

**彼の意見を尊重しながら、もう一度検討する必要がある。**

Không biết `尊重`.

↓

Chọn:

**Tra từ**

↓

Dùng Pencil quẹt qua:

**尊重**

↓

DB hiện:

**尊重【そんちょう】**

Tôn trọng.

↓

Đóng popup.

↓

Không biết `検討`.

↓

Quẹt Pencil qua:

**検討**

↓

DB hiện nghĩa.

↓

Sau đó không hiểu toàn câu.

↓

Chọn:

**AI Giải thích**

↓

Dùng Pencil kéo rectangle quanh cả câu.

↓

OpenRouter giải thích toàn câu.

↓

Người dùng thấy mình thường quên cấu trúc này.

↓

Chọn:

**Điểm yếu**

↓

Dùng Pencil kéo rectangle quanh câu + ghi chú của mình.

↓

AI tạo bản nháp.

↓

Người dùng sửa:

**Tên: Câu ながら**

**Ghi chú: Hay quên chủ ngữ hai vế phải giống nhau.**

↓

Bấm:

**Lưu**

Toàn bộ quá trình đều thực hiện ngay trong notebook bằng Apple Pencil.

---

# 40. Yêu cầu UX quan trọng nhất

Không biến app thành:

> Notebook có một chatbot gắn bên cạnh.

Hãy biến AI thành:

> **Những cây bút thông minh.**

Người dùng không cần suy nghĩ:

> “Tôi phải hỏi AI thế nào?”

Người dùng chỉ cần:

**Muốn biết từ → tô từ.**

**Muốn dịch → khoanh câu.**

**Muốn hiểu → khoanh bài.**

**Muốn nhớ điểm yếu → khoanh vùng cần nhớ.**

Tất cả thao tác lựa chọn nội dung phải được thiết kế trước tiên cho:

**Apple Pencil / bút cảm ứng.**

Đây là yêu cầu cốt lõi của toàn bộ sản phẩm.

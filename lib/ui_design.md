# PROMPT THIẾT KẾ UI/UX CHO STITCH

Hãy thiết kế một ứng dụng iPad tên tạm thời là **Nihongo Notebook** — một ứng dụng vở ghi chép để học tiếng Nhật, tối ưu trước tiên cho **Apple Pencil**. Hãy tạo đầy đủ các màn hình và trạng thái được mô tả bên dưới dưới dạng các frame riêng, có liên kết thành một user flow hoàn chỉnh.

Đây là ứng dụng notebook có các công cụ học tiếng Nhật thông minh, **không phải chatbot AI**. Triết lý sản phẩm là:

> **Notebook trước, AI sau. AI hoạt động như những cây bút thông minh.**

Người dùng chủ yếu viết, tô, khoanh vùng và thao tác trực tiếp trên trang bằng Apple Pencil. Ngón tay dùng để cuộn, pan và pinch-to-zoom. Không thiết kế flow bắt người dùng copy nội dung, chọn text kiểu desktop hoặc nhập prompt thủ công.

---

## 1. Thiết bị, kích thước và phong cách chung

- Thiết kế chính xác cho **iPad thế hệ 11 (iPad A16), màn hình 11 inch**.
- Frame thiết kế chính dùng kích thước logic **1180 × 820 pt ở landscape**; độ phân giải vật lý tương ứng **2360 × 1640 px @2x**.
- Tạo thêm layout thích nghi **820 × 1180 pt ở portrait**. Landscape là chế độ ưu tiên khi viết và học trên notebook.
- Tôn trọng safe area của iPadOS; không đặt nút quan trọng sát mép màn hình hoặc vùng home indicator.
- Ở chiều rộng 1180 pt, toolbar 9 công cụ phải hiển thị vừa màn hình: dùng icon + label ngắn, khoảng cách gọn và cho phép thu gọn label phụ khi cần, nhưng không ẩn các công cụ cốt lõi vào menu overflow.
- Trong editor, Page Thumbnail Rail mặc định có thể thu gọn để dành tối đa diện tích cho trang giấy. Khi mở side sheet kết quả hoặc Điểm yếu, tự động thu gọn rail nếu canvas còn quá hẹp.
- Phong cách: hiện đại, yên tĩnh, tập trung, có cảm giác giấy và dụng cụ học tập cao cấp.
- Dùng ngôn ngữ thiết kế gần với iPadOS: navigation bar gọn, sidebar, popover neo vào công cụ, bottom sheet vừa phải, bo góc mềm.
- Không dùng giao diện quá nhiều gradient, neon hoặc hiệu ứng futuristic.
- Nền ứng dụng: xám ấm rất nhạt `#F5F3EE`.
- Bề mặt/card: trắng ngà `#FFFDF9`.
- Màu chủ đạo: xanh chàm `#3859C7`.
- Màu Tra từ: xanh lá `#2E8B70`.
- Màu AI Dịch: xanh dương `#3979D6`.
- Màu AI Giải thích: tím `#7A5BC7`.
- Màu Điểm yếu: cam hổ phách `#D9822B`.
- Màu lỗi: đỏ dịu `#C94C4C`.
- Typography phải hiển thị tiếng Việt và tiếng Nhật tốt. Dùng phong cách tương đương **SF Pro + Noto Sans JP**.
- Vùng chạm tối thiểu 44 × 44 pt; các tool dùng bằng Pencil cần nút lớn, dễ chọn.
- Icon dạng outline rõ ràng, có label tiếng Việt bên dưới hoặc tooltip; không dựa vào icon mơ hồ.
- Hạn chế modal toàn màn hình. Kết quả tra từ và AI ưu tiên xuất hiện trong popover/card cạnh vùng vừa chọn.
- Bảo đảm độ tương phản tốt, hỗ trợ Dynamic Type và không chỉ dùng màu sắc để thể hiện trạng thái.

---

## 2. Kiến trúc điều hướng

Navigation chính gồm sidebar có thể thu gọn:

1. **Vở của tôi**
2. **Điểm yếu**
3. **Cài đặt**

Trong màn hình notebook editor, ưu tiên toàn bộ diện tích cho trang giấy. Sidebar thư viện được thay bằng panel thumbnail trang có thể đóng/mở. Có nút quay lại thư viện ở góc trên trái.

Hãy tạo prototype flow chính:

**Vở của tôi → mở vở/PDF → viết hoặc chọn công cụ thông minh → xem kết quả cạnh vùng chọn → có thể ghim/lưu → mở Điểm yếu → xem lại nguồn trong đúng trang vở → Cài đặt AI.**

---

## 3. Screen 01 — Vở của tôi / Notebook Library

Thiết kế màn hình home khi người dùng đã có dữ liệu.

### Bố cục

- Sidebar trái rộng khoảng 220 pt, có logo nhỏ và tên **Nihongo Notebook** ở trên.
- Các mục sidebar: **Vở của tôi** đang active, **Điểm yếu**, **Cài đặt**.
- Cuối sidebar có avatar/local profile đơn giản và trạng thái đồng bộ/lưu cục bộ.
- Thanh trên của vùng nội dung có tiêu đề **Vở của tôi**, ô tìm kiếm **Tìm vở...**, nút đổi Grid/List, nút **Chọn**, và nút primary **+ Tạo mới**.
- Một hàng filter dạng chip: **Tất cả · Gần đây · Vở trắng · PDF**.
- Grid 3–4 cột gồm notebook card kích thước lớn.

### Nội dung notebook card

- Thumbnail bìa vở hoặc trang PDF đầu tiên.
- Tên ví dụ: **N3 Grammar**, **Từ vựng Soumatome**, **Đọc hiểu tháng 8**, **Shinkanzen PDF**.
- Loại tài liệu: Vở ghi hoặc PDF.
- Số trang và thời gian mở gần nhất.
- Menu dấu ba chấm: Đổi tên, Nhân bản, Xuất, Xóa.
- Một card **Tạo vở mới** dạng nét đứt nằm cuối grid.

### Trạng thái cần vẽ

- Library có dữ liệu.
- Empty state: minh họa tối giản cây bút trên trang giấy, tiêu đề **Bắt đầu vở học đầu tiên**, hai nút **Tạo vở trắng** và **Nhập PDF**.

---

## 4. Screen 02 — Tạo vở mới / Import PDF

Khi bấm **+ Tạo mới**, mở một sheet ở giữa màn hình, không che mất toàn bộ ngữ cảnh.

### Tab Tạo vở

- Preview bìa ở bên trái.
- Form bên phải: **Tên vở**, màu bìa, kiểu giấy.
- Kiểu giấy dạng thumbnail: **Trắng, Kẻ ngang, Ô vuông, Chấm, Genkō yōshi**.
- Khổ giấy: A4, Letter, iPad Screen.
- Nút **Hủy** và **Tạo vở**.

### Tab Nhập PDF

- Drop zone lớn có icon PDF và dòng **Chọn PDF từ Files**.
- Sau khi chọn, hiển thị tên file, dung lượng, số trang và thumbnail trang đầu.
- Trường **Tên vở** có thể sửa.
- Nút **Nhập PDF**.

---

## 5. Screen 03 — Notebook Editor, trạng thái viết thông thường

Đây là màn hình quan trọng nhất. Hãy làm nó có cảm giác như một notebook thật, không giống trình soạn thảo văn bản.

### Bố cục tổng thể

- Top bar cao vừa phải, nền sáng, không chiếm nhiều diện tích.
- Góc trái: nút quay lại, tên vở **N3 Grammar**, tên trang hoặc số trang, trạng thái **Đã lưu**.
- Chính giữa top bar: undo, redo và nhóm công cụ chính.
- Góc phải: tìm trong vở, chia sẻ/xuất, menu và nút mở thumbnail trang.
- Bên trái có **Page Thumbnail Rail** rộng khoảng 170 pt, có thể thu gọn. Hiển thị thumbnail, số trang, trang hiện tại có viền xanh. Cuối rail có nút **+ Trang**.
- Vùng giữa là canvas lớn, nền workspace xám ấm; một trang giấy trắng/ngà có bóng rất nhẹ.
- Trang mẫu có chữ viết tay tiếng Nhật, bài ngữ pháp, vài nét highlight và bảng kẻ bằng thước để thể hiện use case thật.
- Góc dưới phải có zoom control nhỏ: **− 100% +**, fit page và full screen.

### Thanh công cụ Apple Pencil

Thanh công cụ dạng pill nổi, đặt ngang gần top bar hoặc cạnh trên canvas. Gồm đúng các công cụ theo thứ tự:

1. **Bút**
2. **Highlight**
3. **Tẩy**
4. **Thước**
5. Divider
6. **Tra từ**
7. **AI Dịch**
8. **AI Giải thích**
9. **Điểm yếu**

Mỗi tool có icon và label ngắn. Tool đang chọn có nền màu nhạt, viền rõ và chấm màu công cụ. Không làm toolbar dày đặc như ứng dụng đồ họa chuyên nghiệp.

### Trạng thái Bút đang active

- Icon Bút có nền xanh chàm nhạt.
- Một popover nhỏ neo dưới nút Bút gồm:
  - Preview nét bút thư pháp.
  - 6 màu nhanh: đen, xanh đậm, đỏ, xanh lá, nâu, tím.
  - Slider **Độ dày**.
  - Slider **Độ đậm**.
  - Toggle **Nét theo lực bút**.
- Trên canvas có cursor/preview đầu bút rất nhỏ.
- Có hint ngắn, chỉ xuất hiện lần đầu: **Pencil để viết · Hai ngón tay để di chuyển/thu phóng**.

---

## 6. Screen 04 — Trạng thái Highlight, Tẩy và Thước

Tạo ba frame hoặc ba state variant của editor:

### Highlight active

- Popover gồm các màu vàng, xanh lá, xanh dương, hồng, tím.
- Slider độ dày và opacity.
- Preview cho thấy highlight trong suốt, không che chữ Nhật bên dưới.

### Tẩy active

- Segmented control: **Tẩy một phần · Tẩy cả nét**.
- Slider kích thước tẩy.
- Cursor tròn thể hiện kích thước tẩy trên canvas.

### Thước active

- Một cây thước bán trong suốt nằm trực tiếp trên trang, có tay cầm xoay ở hai đầu và số đo góc.
- Hint nhỏ **Kéo thước bằng ngón tay · Kẻ bằng Pencil**.
- Có nút đóng thước trên chính ruler.

---

## 7. Screen 05 — PDF Notebook Editor

Tạo một biến thể editor khi background là PDF giáo trình tiếng Nhật.

- Page thumbnail rail hiển thị các trang PDF.
- Trang chính có nội dung in tiếng Nhật, bài trắc nghiệm và hình ảnh đơn giản.
- Annotation viết tay, highlight và nét bút nằm ở layer phía trên PDF.
- Có badge nhỏ **PDF · Chỉ ghi chú** cạnh tên vở, làm rõ nội dung PDF gốc không bị sửa.
- Toolbar và mọi công cụ thông minh giống notebook trắng.
- Menu trang có **Ẩn annotations**, **Xoay trang**, **Xuất PDF có ghi chú**.

---

## 8. Screen 06 — Tra từ bằng Pencil / Dictionary Lookup

Đây là công cụ tra database, **không dùng AI**. Tạo ít nhất ba state liên tiếp trong editor.

### State A — đang chọn

- Tool **Tra từ** active với màu xanh lá.
- Pencil quẹt một vùng highlight mảnh qua đúng từ `検討` trong câu tiếng Nhật.
- Vệt chọn là xanh lá trong suốt và chỉ tồn tại tạm thời.
- Hint trên canvas: **Quẹt qua một từ hoặc Kanji để tra**.

### State B — đang nhận dạng

- Khi nhấc Pencil, vùng vừa quẹt có animation viền nhẹ.
- Chip nhỏ cạnh vùng chọn: spinner + **Đang nhận dạng...**.
- Không mở modal giữa màn hình.

### State C — kết quả từ vựng

- Một popover rộng khoảng 340 pt, neo cạnh từ vừa chọn, tránh che nội dung.
- Header: `検討` cỡ lớn; furigana `けんとう`; icon loa; nút đóng.
- Loại từ: **Danh từ · する-verb**.
- Nghĩa chính: **Xem xét, cân nhắc**.
- Ví dụ: `もう一度検討します。`
- Dịch ví dụ: **Tôi sẽ xem xét lại một lần nữa.**
- Các action dưới cùng: **Ghim vào trang**, **Đánh dấu điểm yếu**, **Đóng**.
- Có label nhỏ **Từ điển ngoại tuyến** để phân biệt với AI.

### Variant Kanji

Tạo thêm một popover khi người dùng chỉ quẹt Kanji `考`:

- Onyomi: `コウ`.
- Kunyomi: `かんが・える`.
- Nghĩa: **Suy nghĩ, cân nhắc**.
- Badge **JLPT N4**, **6 nét**.
- Danh sách 3 từ phổ biến chứa Kanji đó.

### Error state

- Popover nhỏ: **Không tìm thấy “...” trong từ điển**.
- Action: **Thử chọn lại**.
- Không tự động chuyển sang AI.

---

## 9. Screen 07 — AI Dịch bằng vùng chọn hình chữ nhật

Tạo bốn state liên tiếp, tất cả vẫn nằm trong editor.

### State A — chưa cấu hình AI

- Khi chọn **AI Dịch** nhưng chưa có API key, hiện popover nhỏ neo ở tool:
  - Icon khóa.
  - Tiêu đề **Chưa thiết lập OpenRouter**.
  - Mô tả ngắn: chức năng viết và Tra từ vẫn dùng bình thường.
  - Nút primary **Thiết lập AI**.
  - Nút secondary **Để sau**.

### State B — đang khoanh vùng

- Tool **AI Dịch** active màu xanh dương.
- Pencil kéo từ điểm A đến B tạo rectangle xanh dương rất nhạt quanh 1–2 câu tiếng Nhật.
- Rectangle có border nét liền, hai góc đối diện có dấu nhỏ, không giống nét vẽ được lưu.
- Hint: **Khoanh câu hoặc đoạn cần dịch**.

### State C — loading

- Sau khi nhấc bút, border rectangle có animation scanning từ trái sang phải.
- Chip nhỏ: **Đang đọc và dịch...** + nút hủy dạng icon.

### State D — kết quả

- Popover kết quả nằm cạnh vùng chọn, rộng 400–440 pt.
- Header có icon sparkle nhỏ, tiêu đề **Bản dịch**, badge model rút gọn trong menu info, nút đóng.
- Hiển thị câu gốc tiếng Nhật nhỏ hơn và bản dịch tiếng Việt nổi bật:
  - `努力したからといって、必ず成功するわけではない。`
  - **Không phải cứ nỗ lực thì nhất định sẽ thành công.**
- Action: **Ghim vào trang** là primary, **Sao chép**, **Thử lại**, **Đóng**.
- Ghim chỉ tạo một note card mới khi người dùng chủ động bấm; đóng popover không thay đổi trang gốc.

---

## 10. Screen 08 — AI Giải thích câu

- Tool **AI Giải thích** active màu tím.
- Người dùng đã khoanh một câu tiếng Nhật bằng rectangle tím nhạt.
- Popover kết quả lớn hơn Tra từ nhưng không phải màn hình chat.
- Header: **Giải thích**, badge **Phù hợp JLPT N3**, nút đóng.
- Nội dung chia thành các section rõ ràng:
  - **Nghĩa:** bản dịch tiếng Việt ngắn.
  - **Cấu trúc chính:** `〜からといって` — “Chỉ vì A không có nghĩa là B”.
  - **Mẫu kết hợp:** `〜わけではない` — “Không hẳn là / không có nghĩa là”.
  - **Tách câu:** từng cụm tiếng Nhật, mũi tên và nghĩa ngắn.
- Dùng card/rows dễ scan, không trình bày thành đoạn văn dài.
- Action dưới cùng: **Ghim tóm tắt**, **Tạo điểm yếu**, **Giải thích lại**, **Đóng**.
- Có menu overflow: ngắn gọn hơn, chi tiết hơn, báo kết quả không đúng.

---

## 11. Screen 09 — AI Giải bài trắc nghiệm

Tạo một frame trên PDF editor với vùng chọn bao quanh câu hỏi và bốn đáp án.

- Popover tiêu đề **Giải bài**.
- Block đầu tiên làm nổi bật:
  - Label **Đáp án**.
  - **B. 上手とは限らない**.
- Section **Vì sao?** giải thích `〜からといって` bằng tiếng Việt.
- Section **Phân tích lựa chọn** có rows A, B, C, D:
  - B có check màu xanh và trạng thái đúng.
  - A, C, D có icon trung tính và lý do ngắn tại sao không phù hợp.
- Có cảnh báo nhỏ: **Hãy dùng lời giải để hiểu bài, không chỉ chép đáp án.**
- Action: **Ghim lời giải**, **Tạo điểm yếu**, **Đóng**.
- Không có ô nhập chat, avatar AI hoặc bong bóng hội thoại.

---

## 12. Screen 10 — Tạo Điểm yếu từ vùng đã khoanh

Tạo flow gồm state chọn vùng và sheet chỉnh sửa bản nháp.

### Chọn vùng

- Tool **Điểm yếu** active màu cam.
- Pencil kéo rectangle quanh câu ngữ pháp và ghi chú viết tay của người dùng.
- Sau khi nhấc bút, chip loading: **Đang tạo bản nháp...**.

### Sheet “Thêm điểm yếu”

- Dùng side sheet trượt từ phải, rộng khoảng 440–500 pt để trang và vùng nguồn vẫn còn nhìn thấy bên trái.
- Header: **Thêm điểm yếu**, subtitle **AI đã tạo bản nháp — hãy kiểm tra trước khi lưu**.
- Thumbnail crop vùng gốc ở đầu sheet, có action **Xem vùng nguồn**.
- Các trường đều chỉnh sửa được:
  - **Tên:** `Phân biệt わけではない / わけがない`.
  - **Loại:** dropdown gồm Ngữ pháp, Từ vựng, Kanji, Đọc hiểu, Khác.
  - **Nội dung:** multiline text.
  - **Điểm cần nhớ:** multiline text.
  - **Ghi chú của tôi:** multiline text.
  - **Tag:** chip input, ví dụ N3, dễ nhầm.
- Footer cố định: **Hủy** và primary **Lưu điểm yếu**.
- Phải thể hiện rõ chưa lưu cho đến khi người dùng bấm nút Lưu.
- Sau khi lưu, toast nhỏ: **Đã lưu vào Điểm yếu** với action **Xem**.

---

## 13. Screen 11 — Danh sách Điểm yếu

### Bố cục

- Sidebar chính với **Điểm yếu** active.
- Header: **Điểm yếu**, số lượng mục, ô tìm kiếm và nút **Chọn**.
- Filter chips: **Tất cả · Ngữ pháp · Từ vựng · Kanji · Đọc hiểu · Khác**.
- Dropdown sắp xếp: **Mới lưu gần đây**, **Tên A–Z**, **Theo vở**.
- Nội dung dạng list/card rộng, không quá nhiều card nhỏ.

### Mỗi item

- Thumbnail vùng ảnh gốc bên trái.
- Tên mục, badge loại và tag JLPT.
- Một dòng “Điểm cần nhớ”.
- Nguồn: **N3 Grammar · Trang 12**.
- Thời gian lưu.
- Actions dễ thấy: **Mở**, **Sửa**, **Xem nguồn**, menu có Xóa.

### Dữ liệu mẫu

1. `わけではない / わけがない` — Ngữ pháp — Hay nhầm nghĩa hai mẫu này.
2. `使役受身` — Ngữ pháp — Hay quên cách chia động từ nhóm I.
3. `認識【にんしき】` — Từ vựng — Hay quên cách đọc.
4. `尊重【そんちょう】` — Từ vựng — Dễ nhầm với 重視.

### Empty state

- Tiêu đề **Chưa có điểm yếu nào**.
- Mô tả: **Trong vở, chọn công cụ Điểm yếu rồi khoanh nội dung bạn muốn ôn lại.**
- Minh họa trực tiếp thao tác Pencil khoanh rectangle trên trang.
- Nút **Mở vở gần đây**.

---

## 14. Screen 12 — Chi tiết và chỉnh sửa Điểm yếu

- Breadcrumb/back: **Điểm yếu / Chi tiết**.
- Layout hai cột.
- Cột trái: tên, loại, tags, nội dung, điểm cần nhớ, ghi chú.
- Cột phải: thumbnail ảnh nguồn lớn, OCR text dạng collapsible, thông tin **Vở · Trang · Ngày lưu**.
- Primary action **Xem trong vở**.
- Secondary actions **Sửa**, **Xóa**.
- Khi bấm **Xem trong vở**, prototype mở đúng notebook, đúng trang, zoom tới vùng gốc và pulse viền cam quanh khu vực đó trong 2 giây.
- Edit state dùng đúng các trường như sheet “Thêm điểm yếu”, có **Lưu thay đổi** và **Hủy**.
- Xóa phải có confirm dialog rõ tên mục, với nút destructive **Xóa điểm yếu**.

---

## 15. Screen 13 — Cài đặt chung

- Sidebar chính với **Cài đặt** active.
- Settings có sidebar con hoặc danh sách section: **Chung, Apple Pencil, AI, Dữ liệu & quyền riêng tư, Giới thiệu**.
- Màn hình Chung:
  - Ngôn ngữ giao diện: Tiếng Việt.
  - Giao diện: Sáng, Tối, Theo hệ thống.
  - Giấy mặc định.
  - Tự động lưu.
- Màn hình Apple Pencil:
  - Segmented setting **Pencil viết · Ngón tay di chuyển** đang chọn.
  - Toggle lực bút.
  - Toggle double-tap đổi sang tẩy.
  - Toggle palm rejection với mô tả ngắn.
  - Khu vực test nét bút trực tiếp.

---

## 16. Screen 14 — Settings → AI, chưa cấu hình

Thiết kế trang AI rõ ràng, đáng tin cậy và không gây cảm giác app sở hữu key của người dùng.

- Header **AI qua OpenRouter**.
- Info banner: **Các công cụ AI chỉ xử lý vùng bạn chủ động khoanh. Tra từ ngoại tuyến không gửi dữ liệu lên AI.**
- Section **Provider**: OpenRouter, cố định trong phiên bản đầu.
- Trường password **OpenRouter API Key** với icon hiện/ẩn trong lúc nhập.
- Link phụ **Lấy API key tại OpenRouter**.
- Trường **Model** bị disabled cho đến khi key hợp lệ, placeholder **Chọn model...**.
- Nút **Kiểm tra kết nối**.
- Section **Cá nhân hóa lời giải**:
  - JLPT Level: N5, N4, N3, N2, N1; chọn N3.
  - Ngôn ngữ giải thích: Tiếng Việt.
- Footer sticky: **Lưu cài đặt**.
- Security note: **Key được lưu an toàn trên thiết bị, không xuất hiện trong notebook hoặc analytics.**

### Trạng thái validation

- Empty key.
- Đang kiểm tra với spinner.
- Thành công: check xanh + **Kết nối thành công**.
- Lỗi: banner đỏ dịu + **Không thể kết nối. Hãy kiểm tra API key hoặc mạng.**

---

## 17. Screen 15 — Settings → AI, đã cấu hình và chọn model

- API key hiển thị dạng `••••••••••••••••`, không bao giờ hiện lại toàn bộ key đã lưu.
- Actions: **Thay key**, **Xóa key**.
- Trạng thái kết nối: chấm xanh + **Đã kết nối**.
- Model hiện tại là một card/select có model name, provider, model ID rút gọn và badge **Vision** nếu hỗ trợ ảnh.
- Bấm chọn model mở popover lớn:
  - Ô **Tìm model...**.
  - Filter **Tất cả · Có hỗ trợ ảnh · Miễn phí**.
  - List model có tên, provider, context, khả năng vision và dấu check ở model đang chọn.
  - Không hard-code một model duy nhất trong thiết kế.
- Ghi chú: **Một model được dùng chung cho AI Dịch, AI Giải thích, Giải bài và tạo Điểm yếu.**
- Confirm dialog khi Xóa key, giải thích Notebook, Pen, Highlight, PDF và Tra từ vẫn sử dụng được.

---

## 18. Các trạng thái hệ thống cần có trong component set

Hãy tạo component/variant có thể tái sử dụng cho:

- Saving / Đã lưu / Lỗi lưu.
- OCR loading / OCR thất bại / Không nhận dạng được chữ.
- AI loading / AI timeout / Mất mạng / API key sai / Hết quota.
- Dictionary result / Không tìm thấy.
- Tooltip hướng dẫn Pencil lần đầu.
- Toast sau khi ghim, lưu hoặc xóa.
- Confirm dialog cho hành động xóa.
- Skeleton cho notebook cards và model list.
- Popover tự đổi hướng nếu vùng chọn nằm sát cạnh màn hình.
- Dark mode cho các component chính, nhưng frame bàn giao chính dùng light mode.

Các lỗi phải xuất hiện gần nơi phát sinh, có câu chữ dễ hiểu và nút thử lại. Không làm mất stroke hoặc vùng người dùng đang thao tác.

---

## 19. Quy tắc tương tác bắt buộc

- **Apple Pencil = viết, highlight, tẩy, kẻ hoặc chọn vùng theo công cụ hiện tại.**
- **Ngón tay = pan, cuộn và pinch-to-zoom.**
- Pen tạo stroke tự nhiên, hỗ trợ pressure nếu thiết bị có.
- Tra từ dùng thao tác quẹt/tô đúng một từ hoặc Kanji.
- AI Dịch, AI Giải thích và Điểm yếu dùng thao tác kéo rectangle.
- Rectangle chọn vùng thuộc interaction layer, không được lưu thành nét vẽ.
- Khi nhấc Pencil mới bắt đầu OCR/xử lý.
- Chỉ crop và gửi đúng vùng được chọn, không gửi toàn trang.
- Kết quả chỉ là popover tạm thời. Chỉ khi bấm **Ghim vào trang** mới thêm object vào annotation layer.
- Không tự sửa PDF hoặc nội dung notebook gốc.
- Không tự lưu Điểm yếu; luôn cho người dùng xem và sửa bản nháp trước.
- Nếu không có OpenRouter key, Pen, Highlight, Tẩy, Thước, PDF và Tra từ vẫn hoạt động bình thường.
- Tra từ luôn dùng database và tuyệt đối không gọi AI.

---

## 20. Những điều tuyệt đối không thiết kế

- Không tạo màn hình chatbot.
- Không có bong bóng hội thoại, avatar robot hoặc ô nhập prompt cố định.
- Không bắt người dùng gõ “hãy dịch câu này” hoặc “hãy giải thích”.
- Không biến toolbar thành ribbon phức tạp với quá nhiều công cụ.
- Không tự động quét toàn bộ trang để tìm mọi từ khó.
- Không tự động thay đổi nội dung hoặc chèn kết quả AI vào trang.
- Không dùng selection kiểu chuột desktop làm interaction chính.
- Không che toàn bộ canvas bằng modal khi đang học.
- Không dùng layout điện thoại phóng to lên tablet.

---

## 21. Yêu cầu bàn giao từ Stitch

Hãy tạo:

1. **15 màn hình/frame chính** đã liệt kê.
2. Các frame trạng thái riêng cho Tra từ, AI Dịch, AI Giải thích, Giải bài và tạo Điểm yếu.
3. Một **component sheet** gồm buttons, toolbar tools, chips, notebook cards, page thumbnails, popovers, form fields, loading states, toast và dialogs.
4. Prototype flow hoàn chỉnh cho tình huống:
   - Mở **Shinkanzen PDF**.
   - Tra từ `尊重` bằng cách quẹt Pencil.
   - Khoanh cả câu bằng **AI Giải thích**.
   - Tạo một **Điểm yếu** từ câu đó.
   - Chỉnh bản nháp và bấm Lưu.
   - Mở danh sách Điểm yếu.
   - Bấm **Xem trong vở** để quay lại đúng vùng nguồn.
5. Ghi chú ngắn cạnh mỗi frame mô tả gesture Pencil, trạng thái trước/sau và hành động điều hướng.

Ưu tiên số một của toàn bộ thiết kế: người dùng phải cảm thấy họ đang học trong một cuốn vở thật bằng Apple Pencil; các chức năng AI chỉ xuất hiện đúng lúc, ngay cạnh nội dung họ vừa chủ động khoanh.

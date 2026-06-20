# VNKey engine corpus test

`EngineCorpusTest.cpp` tạo một corpus xác định gồm 10.000 từ tiếng Việt xen
English, chuyển phần tiếng Việt thành chuỗi phím Telex, chạy từng từ qua engine
thật rồi so sánh kết quả.

Test báo cáo bốn cấu hình:

- `baseline`: engine không khôi phục từ sai chính tả.
- `restore`: dùng cơ chế khôi phục hiện có.
- `structural`: restore cộng heuristic không dùng từ điển.
- `protected_lexicon`: restore cộng danh sách nhỏ các từ English dễ bị Telex
  biến đổi.

Chạy:

```sh
Tests/run_engine_corpus_test.sh
```

Chạy thêm AddressSanitizer và UndefinedBehaviorSanitizer:

```sh
SANITIZE=1 Tests/run_engine_corpus_test.sh
```

Chế độ sanitizer cũng bảo vệ regression từng gây truy cập `TypingWord[-1]`
khi xử lý một từ bắt đầu bằng `w/W`.

Corpus được tạo từ `seedCorpus()` và luôn cắt đúng 10.000 từ, vì vậy có thể
chạy lại ổn định sau mỗi thay đổi engine.

Test còn có nhóm mơ hồ (`Docs/Dóc`, `raw/ră`, `test/tét`) để chứng minh rằng
không thể luôn chọn đúng chỉ bằng một phép tra từ điển trên từ hiện tại; các ca
này được loại khỏi protected lexicon và cần ngữ cảnh, chế độ ứng dụng hoặc lựa
chọn đã học từ người dùng.

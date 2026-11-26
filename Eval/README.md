# Bộ câu để đo việc sửa cả câu

Dùng cho `vnkey-tool eval`: cùng một bộ câu, cùng một cách chấm, cho mọi đường sửa câu (thuật toán trên máy
mô hình của macOS ở các chế độ khác nhau; thuật toán `Proofreader.restore` từng là mốc so sánh, đã gỡ 2026-11-26). Thư mục này không nằm trong gói ứng dụng.

Mỗi dòng: `câu gõ <TAB> câu đúng <TAB> loại`. Dòng bắt đầu bằng `#` là ghi chú.

## Hai tệp

- `generated.tsv`: SINH TỰ ĐỘNG, đừng sửa tay. 460 câu đúng lấy từ Tatoeba rồi cấy lỗi. 400 câu đầu:
  `khong-dau` (bỏ hết dấu), `thieu-dau` (1–2 âm tiết mất dấu), `lan-am` (một âm tiết bị đổi theo bảng lẫn âm của
  bộ soát lỗi), `sai-thanh` (hỏi / ngã / nặng), `dung` (không lỗi, để đếm chỗ sửa bậy). Thêm 60 câu `ngoai-bang`: một âm tiết bị
  đổi thành âm tiết đúng cấu tạo nhưng KHÔNG có trong bảng thông dụng ("về" -> "vễ", "vào" -> "dào").
- `handwritten.tsv`: câu viết tay. Loại `da-chinh` là 20 câu đã dùng để chỉnh trọng số và bộ lọc, kết quả trên
  chúng lạc quan. Loại `xen-anh` là 128 câu Việt xen từ tiếng Anh (từ tiếng Anh phải giữ nguyên). Bốn nhóm `tay-…` và phần mở rộng của `xen-anh` (957 câu, viết 2026-11-26; cả tệp 1.001 câu) do người làm bộ đo viết theo các lỗi quen thuộc, không
  phải câu gõ thật của người dùng: `tay-chinh-ta` (303 câu lỗi chính tả hay gặp: "xử dụng", "bổ xung", hỏi / ngã),
  `tay-khong-dau` (197 tin nhắn không dấu), `tay-go-loi` (150 câu sót dấu, đảo chữ, lặp chữ), `tay-dung` (203 câu đúng có
  tên riêng, từ hiếm, thành ngữ: không được đổi gì). Thêm câu lỗi thật của bạn vào cuối tệp (bỏ cột loại thì thành `tay`).

## Giới hạn

- Lỗi trong `generated.tsv` là lỗi TỔNG HỢP. Nhóm `lan-am` và `sai-thanh` cấy lỗi bằng chính bảng mà
  `Proofreader` dùng để sửa, nên thiên vị cho đường thuật toán. Chỉ câu viết tay mới là lỗi thật.
- Câu Tatoeba ngắn, kiểu câu ví dụ học ngoại ngữ; không đại diện cho tin nhắn, thư từ hay văn bản dài.
- Câu đúng lấy nguyên từ nguồn, chưa ai soát lại: một số câu "đúng" có thể có lỗi chính tả.

## Sinh lại

```bash
curl -O https://downloads.tatoeba.org/exports/per_language/vie/vie_sentences.tsv.bz2
```

```bash
bunzip2 vie_sentences.tsv.bz2
```

```bash
swift run -c release vnkey-tool eval-make vie_sentences.tsv --count 400 --seed 1 > Eval/generated.tsv
```

Cùng tệp nguồn và cùng hạt giống thì ra cùng bộ câu. Tệp nguồn của Tatoeba đổi theo tuần, nên sinh lại vào ngày khác
có thể ra bộ câu khác; bản hiện tại sinh ngày 2026-11-26.

## Đo

```bash
swift run -c release vnkey-tool eval --engine all --json ket-qua.json
```

`--engine apple|apple-raw|apple-retry|apple-open|all` (`apple-retry`: bị bộ lọc an toàn từ chối thì hỏi lại ở mức dành cho việc biến đổi văn bản, như ứng dụng làm), `--kind <loại>`, `--limit N`, `--set <tệp.tsv>`, `--part a|b` (nửa câu chẵn / lẻ), `--instructions <tệp>` (thử lời nhắc khác). Chạy từ gốc dự án.

## Đo bộ soát lỗi theo từ

```bash
swift run -c release vnkey-tool check-eval
```

Chạy `Proofreader.check` (thứ ứng dụng gạch chân) trên cột "câu gõ" rồi so từng từ với cột "câu đúng": từ sai nào được
gạch, đề nghị đứng đầu có đúng không, từ đúng nào bị gạch nhầm. Từ sai chia ba loại: viết không dấu (bộ soát cố ý không
gạch riêng lẻ), chữ không có thật (không phải tiếng Việt cũng không phải tiếng Anh), trùng một từ có thật.

## Nguồn và giấy phép

Câu đúng trong `generated.tsv` lấy từ [Tatoeba](https://tatoeba.org), giấy phép
[CC BY 2.0 FR](https://creativecommons.org/licenses/by/2.0/fr/). Thay đổi so với bản gốc: chỉ giữ câu thuần Việt dài
4–20 âm tiết, lấy mẫu 400 câu, và cấy lỗi vào cột "câu gõ".

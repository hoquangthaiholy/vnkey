# Train thử mô hình sửa câu (THỬ NGHIỆM)

Thử xem một mô hình nhỏ tự train có sửa dấu và chính tả cả câu tốt hơn thuật toán từ điển (`Proofreader.restore`)
và mô hình của macOS không. Ứng dụng CHƯA dùng gì ở đây; thư mục này không nằm trong gói ứng dụng.

## Mô hình

Bộ mã hoá Transformer nhỏ (4 lớp, rộng 192, khoảng 2,15 triệu tham số). Mỗi từ vào là dãy chữ cái của nó; với từng
từ, mô hình chọn một trong 3.320 âm tiết của bảng tần suất, hoặc "giữ nguyên" (từ tiếng Anh, tên riêng, số, âm tiết
hiếm). Nó không sinh chữ tự do nên không thêm, bớt hay đảo từ được.

## Dữ liệu

- Câu đúng: kho phụ đề OpenSubtitles 2018 bản tiếng Việt trên OPUS (cùng kho với các bảng của engine; xem README ở
  gốc dự án), khoảng 3,86 triệu dòng thoại. Kho này KHÔNG nằm trong dự án: tải `mono/vi.txt.gz` về máy.
- Lỗi được cấy tự động mỗi lô: bỏ hết dấu, bỏ dấu vài từ, bỏ riêng dấu thanh, lẫn âm và lẫn thanh theo bảng của
  `Proofreader` (xuất bằng `vnkey-tool train-tables`).
- Từ tiếng Anh để chèn vào câu Việt (nhãn "giữ nguyên"): `en_50k.txt` của
  [FrequencyWords](https://github.com/hermitdave/FrequencyWords) (CC BY-SA 4.0), tải về `Training/work/`, không commit.
- Bộ đo là `Eval/` (câu Tatoeba), không dùng để train.

## Chạy

```bash
python3 -m venv Training/.venv && Training/.venv/bin/pip install torch numpy
```

```bash
swift run -c release vnkey-tool train-tables > Training/work/tables.tsv
```

```bash
Training/.venv/bin/python Training/fixer.py prepare vi.txt.gz Training/work/tables.tsv Training/work/en_50k.txt
```

```bash
Training/.venv/bin/python Training/fixer.py train --steps 40000
```

```bash
Training/.venv/bin/python Training/fixer.py predict Eval/generated.tsv Eval/handwritten.tsv > Training/work/predictions.tsv
```

```bash
swift run -c release vnkey-tool eval --engine local,file:Training/work/predictions.tsv
```

`Training/.venv/` và `Training/work/` (dữ liệu, mô hình) không được commit.

## Kết quả (2026-11-26, M4)

Câu đúng hoàn toàn trên `Eval/` (504 câu). Lượt đầu: 30.000 bước, 24,5 phút, chỉ cấy lỗi bỏ dấu / lẫn âm / lẫn thanh
ra từ có thật. Lượt hai: 40.000 bước, 46,7 phút, thêm lỗi ra âm tiết ngoài bảng, trượt phím, chèn tiếng Anh, cờ chữ
hoa. Tệp mô hình 9 MB (số thực 32 bit, chưa nén).

| Loại lỗi | Số câu | Lượt hai | Lượt đầu | `Proofreader.restore` | Mô hình macOS + lọc |
|---|---|---|---|---|---|
| Không dấu | 120 | 69,2% | 65,8% | 57,5% | 38,3% |
| Thiếu dấu | 100 | 88,0% | 87,0% | 87,0% | 69,0% |
| Lẫn âm | 80 | 85,0% | 81,2% | 36,2% | 53,8% |
| Sai thanh | 40 | 95,0% | 95,0% | 20,0% | 77,5% |
| Câu đúng sẵn | 60 | 96,7% | 100% | 98,3% | 100% |
| Lỗi ra âm tiết ngoài bảng | 60 | 88,3% | chưa đo | 90,0% | 65,0% |
| 20 câu lỗi thật viết tay | 20 | 70,0% | 55,0% | 90,0% | 95,0% |
| Việt xen tiếng Anh | 24 | 87,5% | chưa đo | 87,5% | 87,5% |
| Tổng | 504 | 83,9% | (81,0% trên 420 câu) | 68,5% | 65,1% |

Lượt hai sửa bậy 3,3 âm tiết trên 1.000 (`restore` 5,9). Thời gian 0,6 ms mỗi câu (PyTorch, CPU một luồng). Còn yếu:
hay chọn từ phổ biến hơn từ đúng ("tiếng viet" -> "tiếng viết", "phong hop" -> "phòng hợp", "chia sẽ" giữ nguyên), và
đổi bậy 2 trong 60 câu vốn đúng ("dấu phẩy" -> "dấu phải").

## Ghép với từ điển (THỬ NGHIỆM, 2026-11-26)

`Proofreader.restore` nhận thêm điểm của mô hình cho từng từ (`Proofreader.guide`, mặc định tắt): ứng viên đứng đầu
của mô hình được thêm vào danh sách, và điểm của nó cộng vào điểm của bảng tần suất / bảng cặp / từ ghép.

```bash
Training/.venv/bin/python Training/fixer.py predict --scores Training/work/scores.jsonl Eval/generated.tsv Eval/handwritten.tsv > Training/work/predictions.tsv
```

```bash
swift run -c release vnkey-tool eval --engine file:Training/work/predictions.tsv,hybrid:Training/work/scores.jsonl --guide-weight 5 --guide-adds 1
```

Trọng số chọn trên một bộ dev riêng (447 câu Tatoeba khác, hạt giống 2, bỏ câu trùng bộ đo): mô hình riêng 84,8%, ghép
85,7%. Trên bộ đo 504 câu: mô hình riêng 83,9%, ghép 85,3% (hơn 7 câu), nhưng sửa bậy tăng từ 3,3 lên 5,4 âm tiết
trên 1.000. Lợi nhỏ, chưa chắc hơn sai số của bộ đo. Các lỗi "phòng hợp", "chia sẽ", "bánh trứng" vẫn còn ở cả hai.

## Trên câu viết tay (1.001 câu, 2026-11-26)

Câu đúng hoàn toàn. Đây là con số nên tin hơn con số trên câu sinh tự động.

| Nhóm | Số câu | Mô hình macOS + lọc | Ghép | Mô hình này | `restore` |
|---|---|---|---|---|---|
| Lỗi chính tả quen thuộc | 303 | 75,9% | 80,9% | 70,6% | 64,7% |
| Câu đúng có tên riêng, từ hiếm, thành ngữ | 203 | 98,5% | 67,0% | 68,0% | 79,8% |
| Tin nhắn không dấu | 197 | 50,8% | 68,0% | 64,5% | 50,3% |
| Lỗi gõ (sót dấu, đảo, lặp, sót chữ) | 150 | 90,7% | 84,7% | 78,7% | 56,0% |
| Việt xen tiếng Anh | 128 | 80,5% | 83,6% | 82,8% | 68,0% |
| 20 câu cũ (đã dùng để chỉnh) | 20 | 95,0% | 75,0% | 70,0% | 90,0% |
| Tổng | 1.001 | 78,7% | 76,3% | 71,6% | 64,5% |
| Sửa bậy trên 1.000 âm tiết | | 1,0 | 19,9 | 17,9 | 13,5 |

Mô hình macOS từ chối 30 câu (bộ lọc an toàn), trung vị 343 ms mỗi câu. Mô hình này đổi bậy khoảng một phần ba số câu
đúng có tên riêng / từ hiếm ("Nguyễn Du" -> "Nguyên Du", "têm trầu" -> "thêm chầu"): đây là lỗi phải sửa trước khi
nghĩ tới việc đưa vào ứng dụng. Các câu do người làm bộ đo viết, không phải câu gõ thật của người dùng.

## Lượt ba (2026-11-26)

Bảng đầu ra 7.492 âm tiết (thêm âm tiết hiếm của từ điển từ ghép), không cấy lỗi ra từ có thật, 22% câu train là câu
đúng, 2,96 triệu tham số (tệp 12 MB), 40.000 bước trong 55 phút. `predict --margin M`: chỉ đổi khi mô hình tin ứng viên
hơn việc để nguyên ít nhất M (log xác suất); M = 2 chọn trên bộ dev (447 câu có lỗi + 800 câu đúng, Tatoeba).

| Câu đúng hoàn toàn | Lượt ba | Lượt ba, ngưỡng 2 | Lượt ba ghép từ điển | Lượt hai | Lượt hai ghép | macOS + lọc |
|---|---|---|---|---|---|---|
| 460 câu sinh tự động | 80,7% | 76,5% | 87,6% | 83,9% (trên 504) | 85,3% (trên 504) | chưa đo riêng |
| 1.001 câu viết tay | 70,2% | 65,3% | 78,2% | 71,6% | 76,3% | 78,7% |
| trong đó 203 câu đúng sẵn | 81,8% | 87,7% | 78,8% | 68,0% | 67,0% | 98,5% |
| trong đó 303 câu lỗi chính tả | 57,8% | 46,9% | 78,2% | 70,6% | 80,9% | 75,9% |
| Sửa bậy trên 1.000 âm tiết (viết tay) | 11,9 | 6,2 | 12,9 | 17,9 | 19,9 | 1,0 |

Lượt ba đổi bậy ít hơn nhưng cũng sửa ít hơn: đứng riêng không hơn lượt hai. Ghép với từ điển thì ngang mô hình macOS
về số câu đúng, nhưng vẫn đổi bậy nhiều gấp hơn mười lần. Chỗ còn sai nặng là tên riêng và từ ít gặp trong phụ đề phim
("Phan Thiết" -> "Phân Thiết", "bún chả" -> "bún trả", "rau ngót" -> "rau ngọt", "móm mém" -> "mồm mém").

## Giới hạn

- Lỗi train và lỗi trong bộ đo được cấy theo cùng một kiểu, nên con số trên `Eval/generated.tsv` lạc quan so với lỗi
  gõ thật. Mô hình chưa hề thấy lỗi trật phím Telex / VNI, gõ đảo, gõ thừa phím.
- Phụ đề phim là văn nói; văn viết, thuật ngữ, tên riêng Việt ít gặp.
- Chỉ sửa trong phạm vi 3.320 âm tiết thông dụng.
- Thời gian `predict` in ra là PyTorch trên CPU một luồng, không phải thời gian trong ứng dụng (chưa chuyển sang
  Core ML).

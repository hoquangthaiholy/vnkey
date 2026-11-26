"""THỬ NGHIỆM: train một mô hình nhỏ sửa dấu và chính tả cho cả câu tiếng Việt.

Mô hình đọc cả câu (mỗi từ là một dãy chữ cái), rồi với TỪNG từ chọn một âm tiết trong bảng âm tiết thông dụng của
VNKey, hoặc "giữ nguyên" (từ tiếng Anh, tên riêng, số). Nó không sinh chữ tự do nên không thêm bớt từ được.

    python fixer.py prepare <vi.txt.gz> <tables.tsv> <en_50k.txt>   dựng dữ liệu (work/data.npz)
    python fixer.py train [--steps N]                    train (work/model.pt), in độ chính xác trên phần giữ lại
    python fixer.py predict [--margin M] [--scores điểm.jsonl] <tệp.tsv>... > kết quả.tsv   sửa cột đầu của các tệp trong Eval/, in `câu gõ<TAB>kết quả`

Dữ liệu train: kho phụ đề OpenSubtitles 2018 (cùng kho với các bảng của engine); lỗi được cấy tự động.
`tables.tsv` sinh bằng `vnkey-tool train-tables`. Xem README.md cùng thư mục.
"""

import gzip
import math
import os
import re
import sys
import time
import unicodedata
from collections import Counter

import numpy as np

WORK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "work")
MAXLEN = 8  # số chữ cái tối đa của một từ đưa vào mô hình ("nghiêng" là 7)
MAXWORDS = 32
TONES = {"̀": 2, "́": 1, "̃": 4, "̉": 3, "̣": 5}
WORD = re.compile(r"[^\W_]+")


def nfc(s):
    return unicodedata.normalize("NFC", s)


def key(word):
    """Dạng chuẩn của một âm tiết: (chữ cái đã bỏ thanh, thanh). Hai cách đặt dấu thanh cho cùng một khoá."""
    tone, out = 0, []
    for ch in unicodedata.normalize("NFD", word):
        if ch in TONES:
            tone = TONES[ch]
        else:
            out.append(ch)
    return nfc("".join(out)), tone


def strip_tone(word):
    return key(word)[0]


def strip_all(word):
    s = "".join(c for c in unicodedata.normalize("NFD", word) if not unicodedata.combining(c))
    return s.replace("đ", "d").replace("Đ", "D")


# ---------------------------------------------------------------------------------------------------------------------
def prepare(corpus, tables, english):
    vocab, cols = [], {}
    for line in open(tables, encoding="utf-8"):
        f = nfc(line.rstrip("\n")).split("\t") + [""] * 6
        vocab.append(f[0])
        cols[f[0]] = [f[i].split() for i in range(2, 6)]  # lẫn âm, lẫn thanh, lẫn âm ngoài bảng, mọi thanh khác
    by_key = {key(w): i + 1 for i, w in enumerate(vocab)}  # lớp 0 = giữ nguyên
    V = len(vocab)

    print("đọc kho ngữ liệu…", file=sys.stderr)
    lines, oov = [], Counter()
    cache = {}
    with gzip.open(corpus, "rt", encoding="utf-8", errors="ignore") as f:
        for raw in f:
            words = WORD.findall(nfc(raw))
            if not 3 <= len(words) <= MAXWORDS:
                continue
            ids, known = [], 0
            for w in words:
                c = cache.get(w)
                if c is None:
                    low = w.lower()
                    c = cache[w] = (by_key.get(key(low), 0) or low, w[0].isupper())
                if isinstance(c[0], int):
                    known += 1
                ids.append(c)
            if known * 10 < len(words) * 7:
                continue
            for w, _ in ids:
                if isinstance(w, str):
                    oov[w] += 1
            lines.append(ids)
    print(f"{len(lines)} dòng dùng được, {len(oov)} từ ngoài bảng", file=sys.stderr)

    # Dạng chữ ("form"): 0 = đệm, 1…V = âm tiết trong bảng, rồi từ ngoài bảng hay gặp, các dạng lỗi, và từ tiếng Anh.
    forms = [""] + vocab
    form_id = {w: i for i, w in enumerate(forms)}

    def form(w):
        i = form_id.get(w)
        if i is None:
            i = form_id[w] = len(forms)
            forms.append(w)
        return i

    for w, n in oov.most_common(30000):
        if n >= 5:
            form(w)
    kept = set(forms)
    widths = (6, 2, 10, 5)
    tabs = [np.full((V + 1, k), -1, dtype=np.int32) for k in widths]
    all_ = np.zeros(V + 1, dtype=np.int32)
    notone = np.zeros(V + 1, dtype=np.int32)
    for i, w in enumerate(vocab, start=1):
        all_[i] = form(strip_all(w))
        notone[i] = form(strip_tone(w))
        for n, (tab, options, k) in enumerate(zip(tabs, cols[w], widths)):
            # Hai cột "bất kỳ" chỉ giữ dạng KHÔNG phải từ có thật: cấy lỗi ra một từ hiếm có thật ("thêm" -> "têm") sẽ dạy
            # mô hình sửa bậy từ hiếm. Lỗi ra từ thông dụng đã có ở hai cột đầu.
            if n >= 2:
                options = [o for o in options if key(o) not in by_key]
            for j, o in enumerate(options[:k]):
                tab[i, j] = form(o)

    # Từ tiếng Anh để chèn vào câu Việt (nhãn "giữ nguyên"). Từ trùng một âm tiết Việt không dấu ("to", "do", "me")
    # được lấy ít hơn hẳn: trong câu Việt gõ không dấu chúng thường là tiếng Việt.
    plain = {strip_all(w) for w in vocab}
    eng, weight = [], []
    for line in open(english, encoding="utf-8"):
        f = line.split()
        if len(f) != 2 or not f[0].isascii() or not f[0].isalpha() or len(eng) >= 20000:
            continue
        eng.append(form(f[0]))
        weight.append(math.sqrt(int(f[1])) * (0.15 if f[0] in plain else 1))

    F = len(forms)
    chars = sorted({c for w in forms for c in w})
    char_id = {c: i + 2 for i, c in enumerate(chars)}  # 0 = đệm, 1 = chữ lạ
    spell = np.zeros((F, MAXLEN), dtype=np.int16)
    for i, w in enumerate(forms):
        for j, c in enumerate(w[:MAXLEN]):
            spell[i, j] = char_id[c]

    tokens, caps, offsets = [], [], [0]
    for ids in lines:
        if any(isinstance(w, str) and w not in kept for w, _ in ids):
            continue
        tokens.extend(w if isinstance(w, int) else form_id[w] for w, _ in ids)
        caps.extend(c for _, c in ids)
        offsets.append(len(tokens))
    os.makedirs(WORK, exist_ok=True)
    np.savez(
        os.path.join(WORK, "data.npz"), tokens=np.array(tokens, dtype=np.int32), caps=np.array(caps, dtype=np.uint8),
        offsets=np.array(offsets, dtype=np.int64), spell=spell, strip_all=all_, strip_tone=notone, sound=tabs[0], tone=tabs[1],
        sound_any=tabs[2], tone_any=tabs[3], eng=np.array(eng, dtype=np.int32), eng_weight=np.array(weight) / sum(weight),
        vocab=np.array(vocab), chars=np.array(chars))
    print(f"{len(offsets) - 1} câu, {len(tokens)} từ, {F} dạng chữ, {len(chars)} chữ cái, {len(eng)} từ tiếng Anh", file=sys.stderr)


# ---------------------------------------------------------------------------------------------------------------------
def build_model(n_chars, n_classes, d=192, layers=4):
    import torch
    from torch import nn

    class Fixer(nn.Module):
        def __init__(self):
            super().__init__()
            self.chars = nn.Embedding(n_chars, 48, padding_idx=0)
            self.word = nn.Sequential(nn.Linear(48 * MAXLEN, d), nn.GELU(), nn.Linear(d, d))
            self.caps = nn.Embedding(2, d)
            self.pos = nn.Embedding(MAXWORDS, d)
            layer = nn.TransformerEncoderLayer(d, 4, 512, dropout=0.1, batch_first=True, norm_first=True, activation="gelu")
            self.encoder = nn.TransformerEncoder(layer, layers, enable_nested_tensor=False)
            self.norm = nn.LayerNorm(d)
            self.out = nn.Linear(d, n_classes)

        def forward(self, x, caps):  # x: [B, L, MAXLEN] mã chữ cái; caps: [B, L] 1 nếu từ viết hoa chữ đầu
            pad = x[:, :, 0] == 0
            h = self.word(self.chars(x).flatten(2)) + self.caps(caps)
            h = h + self.pos(torch.arange(x.shape[1], device=x.device))[None]
            h = self.encoder(h, src_key_padding_mask=pad)
            return self.out(self.norm(h))

    return Fixer()


# Xác suất cho mỗi từ theo kiểu lỗi của cả câu: (bỏ hết dấu, bỏ thanh, lẫn âm, lẫn thanh, lẫn âm ra âm tiết bất kỳ,
# sai thanh bất kỳ), rồi tới xác suất trượt phím (đảo / lặp / mất một chữ).
MODES = [
    (0.20, (1.00, 0.00, 0.00, 0.00, 0.00, 0.00), 0.00),  # câu gõ không dấu
    (0.04, (0.85, 0.05, 0.00, 0.00, 0.00, 0.00), 0.01),  # gần như không dấu
    (0.17, (0.22, 0.08, 0.00, 0.00, 0.00, 0.00), 0.01),  # thiếu dấu vài từ
    (0.10, (0.00, 0.00, 0.15, 0.00, 0.00, 0.00), 0.00),  # lẫn âm, ra từ có thật
    (0.07, (0.00, 0.00, 0.00, 0.20, 0.00, 0.00), 0.00),  # lẫn thanh, ra từ có thật
    (0.08, (0.00, 0.00, 0.00, 0.00, 0.10, 0.10), 0.00),  # lỗi ra chữ không phải từ có thật
    (0.04, (0.00, 0.00, 0.00, 0.00, 0.00, 0.00), 0.08),  # trượt phím
    (0.08, (0.10, 0.04, 0.05, 0.05, 0.05, 0.05), 0.02),  # lẫn lộn
    (0.22, (0.00, 0.00, 0.00, 0.00, 0.00, 0.00), 0.00),  # câu đúng: không được đổi gì
]
MODE_P = np.array([m[0] for m in MODES])
MODE_KIND = np.array([m[1] for m in MODES])
MODE_SLIP = np.array([m[2] for m in MODES])


def corrupt(rng, clean, d, V):
    """`clean`: [B, L] dạng chữ đúng (0 = đệm). Trả về (dạng chữ sau khi cấy lỗi, kiểu lỗi của từng câu)."""
    B, L = clean.shape
    mode = rng.choice(len(MODES), size=B, p=MODE_P)
    edges = np.cumsum(MODE_KIND[mode], axis=1)[:, None, :]
    kind = (rng.random((B, L, 1)) > edges).sum(-1)  # 0…5 = loại lỗi, 6 = không đổi
    word = np.where(clean <= V, clean, 0)  # chỉ âm tiết trong bảng mới bị cấy lỗi
    rows, colsx = np.arange(B)[:, None], np.arange(L)[None]
    out = clean.copy()
    out = np.where((kind == 0) & (word > 0), d["strip_all"][word], out)
    out = np.where((kind == 1) & (word > 0), d["strip_tone"][word], out)
    for k, name in ((2, "sound"), (3, "tone"), (4, "sound_any"), (5, "tone_any")):
        t = d[name][word]
        pick = t[rows, colsx, rng.integers(0, 1 << 30, (B, L)) % np.maximum((t >= 0).sum(-1), 1)]
        out = np.where((kind == k) & (pick >= 0), pick, out)
    return out, mode


def slip(rng, x, target, mode):
    """Trượt phím trên vài từ tiếng Việt: đảo hai chữ liền nhau, lặp một chữ, hoặc mất một chữ. Sửa `x` tại chỗ."""
    hit = (rng.random(target.shape) < MODE_SLIP[mode][:, None]) & (target > 0)
    for b, l in zip(*np.nonzero(hit)):
        w = [c for c in x[b, l] if c]
        if len(w) < 2:
            continue
        i, how = int(rng.integers(0, len(w) - 1)), int(rng.integers(0, 3))
        if how == 0:
            w[i], w[i + 1] = w[i + 1], w[i]
        elif how == 1:
            w.insert(i, w[i])
        elif len(w) > 2:
            del w[i + 1]
        w = w[:MAXLEN]
        x[b, l] = w + [0] * (MAXLEN - len(w))


def batch(rng, d, index, V):
    """Một lô: (mã chữ cái [B, L, MAXLEN], cờ viết hoa [B, L], lớp đúng [B, L] với -100 ở chỗ đệm)."""
    off, tok, cap = d["offsets"], d["tokens"], d["caps"]
    rows = []
    for i in index:
        ids, up = tok[off[i] : off[i + 1]], cap[off[i] : off[i + 1]]
        r = rng.random()
        if r < 0.03:
            # Cả câu tiếng Anh: không được đụng vào.
            n = int(rng.integers(3, 11))
            ids, up = rng.choice(d["eng"], n, p=d["eng_weight"]), np.zeros(n, dtype=np.uint8)
            up[0] = 1
        elif r < 0.20 and len(ids) < MAXWORDS - 3:
            # Chèn một cụm 1–3 từ tiếng Anh vào câu Việt.
            n, at = int(rng.integers(1, 4)), int(rng.integers(0, len(ids) + 1))
            ids = np.concatenate([ids[:at], rng.choice(d["eng"], n, p=d["eng_weight"]), ids[at:]])
            up = np.concatenate([up[:at], (rng.random(n) < 0.1).astype(np.uint8), up[at:]])
        rows.append((ids, up))
    L = max(len(r[0]) for r in rows)
    clean = np.zeros((len(rows), L), dtype=np.int64)
    caps = np.zeros((len(rows), L), dtype=np.int64)
    for r, (ids, up) in enumerate(rows):
        clean[r, : len(ids)] = ids
        caps[r, : len(ids)] = up
    typed, mode = corrupt(rng, clean, d, V)
    target = np.where(clean == 0, -100, np.where(clean <= V, clean, 0))
    x = d["spell"][typed].astype(np.int64)
    slip(rng, x, target, mode)
    return x, caps, target


def train(steps):
    import torch
    import torch.nn.functional as fn

    d = dict(np.load(os.path.join(WORK, "data.npz")))
    V = len(d["vocab"])
    n = len(d["offsets"]) - 1
    held = 5000  # các câu cuối kho: không train, chỉ để theo dõi
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    model = build_model(len(d["chars"]) + 2, V + 1).to(device)
    print(f"{sum(p.numel() for p in model.parameters()) / 1e6:.2f} triệu tham số, {n} câu, thiết bị {device}", flush=True)
    opt = torch.optim.AdamW(model.parameters(), lr=1e-3, weight_decay=0.01)
    warm = 1000
    sched = torch.optim.lr_scheduler.LambdaLR(
        opt, lambda s: min(1, (s + 1) / warm) * (0.5 * (1 + math.cos(math.pi * min(1, s / steps))) * 0.98 + 0.02))
    rng = np.random.default_rng(1)
    valid = [batch(np.random.default_rng(7 + i), d, np.arange(n - held + i, n - held + i + 500), V) for i in range(0, held, 500)]
    lengths = np.diff(d["offsets"])
    queue = []
    start, seen = time.time(), 0.0
    for step in range(1, steps + 1):
        if not queue:
            # Gom câu dài gần bằng nhau vào một lô để đỡ phải đệm: nhanh hơn vài lần.
            pool = rng.integers(0, n - held, 256 * 40)
            pool = pool[np.argsort(lengths[pool], kind="stable")]
            queue = [pool[i : i + 256] for i in range(0, len(pool), 256)]
            rng.shuffle(queue)
        x, c, y = (torch.from_numpy(a).to(device) for a in batch(rng, d, queue.pop(), V))
        loss = fn.cross_entropy(model(x, c).flatten(0, 1), y.flatten(), ignore_index=-100)
        opt.zero_grad(set_to_none=True)
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        opt.step()
        sched.step()
        seen = loss.item() if step == 1 else 0.98 * seen + 0.02 * loss.item()
        if step % 1000 == 0 or step == steps:
            model.eval()
            right = total = whole = 0
            with torch.no_grad():
                for vx, vc, vy in valid:
                    px, pc, py = (torch.from_numpy(a).to(device) for a in (vx, vc, vy))
                    ok = (model(px, pc).argmax(-1) == py) | (py == -100)
                    right += (ok & (py != -100)).sum().item()
                    total += (py != -100).sum().item()
                    whole += ok.all(1).sum().item()
            model.train()
            print(f"bước {step}: loss {seen:.4f}, giữ lại: từ đúng {100 * right / total:.2f}%, câu đúng {100 * whole / held:.1f}%, "
                  f"{(time.time() - start) / 60:.1f} phút", flush=True)
            torch.save({"model": model.state_dict(), "chars": [str(c) for c in d["chars"]], "vocab": [str(w) for w in d["vocab"]]},
                       os.path.join(WORK, "model.pt"))


# ---------------------------------------------------------------------------------------------------------------------
def pieces(text):
    """Như `SentenceFilter.pieces` của engine: từ là dãy chữ cái / chữ số."""
    out, cur, is_word = [], "", False
    for ch in text:
        w = ch.isalpha() or ch.isdigit()
        if cur and w != is_word:
            out.append((cur, is_word))
            cur = ""
        is_word = w
        cur += ch
    if cur:
        out.append((cur, is_word))
    return out


def predict(paths, scores=None, margin=0.0):
    import json

    import torch

    torch.set_num_threads(1)
    # Tệp do chính lệnh `train` ở trên ghi ra (không tải từ đâu về), nên đọc đầy đủ được.
    state = torch.load(os.path.join(WORK, "model.pt"), map_location="cpu", weights_only=False)
    vocab, char_id = state["vocab"], {c: i + 2 for i, c in enumerate(state["chars"])}
    by_key = {key(w): i + 1 for i, w in enumerate(vocab)}
    model = build_model(len(char_id) + 2, len(vocab) + 1)
    model.load_state_dict(state["model"])
    model.eval()
    times = []
    for path in paths:
        for line in open(path, encoding="utf-8"):
            if line.startswith("#") or not line.strip():
                continue
            typed = nfc(line.rstrip("\n").split("\t")[0])
            parts = pieces(typed)
            words = [i for i, p in enumerate(parts) if p[1]][:MAXWORDS]
            x = np.zeros((1, max(len(words), 1), MAXLEN), dtype=np.int64)
            caps = np.zeros((1, max(len(words), 1)), dtype=np.int64)
            for r, i in enumerate(words):
                caps[0, r] = parts[i][0][0].isupper()
                for j, c in enumerate(parts[i][0].lower()[:MAXLEN]):
                    x[0, r, j] = char_id.get(c, 1)
            begin = time.perf_counter()
            with torch.no_grad():
                logp = torch.log_softmax(model(torch.from_numpy(x), torch.from_numpy(caps))[0], -1)
            classes = logp.argmax(-1).tolist()
            if margin > 0:
                # Chỉ đổi khi mô hình tin ứng viên hơn hẳn việc để nguyên chữ đang viết (lớp "giữ nguyên", hoặc chính âm
                # tiết đó nếu nó có trong bảng).
                for r, i in enumerate(words):
                    own = by_key.get(key(parts[i][0].lower()), 0)
                    stay = max(logp[r, 0].item(), logp[r, own].item())
                    if classes[r] not in (0, own) and logp[r, classes[r]].item() - stay < margin:
                        classes[r] = 0
            times.append((time.perf_counter() - begin) * 1000)
            if scores:
                # Cho đường ghép với từ điển: 8 ứng viên đứng đầu của từng từ và điểm "giữ nguyên" (khoá rỗng).
                top = logp.topk(8, -1)
                rows = []
                for r in range(len(words)):
                    row = {"": round(logp[r, 0].item(), 3)}
                    for v, c in zip(top.values[r].tolist(), top.indices[r].tolist()):
                        if c:
                            row[vocab[c - 1]] = round(v, 3)
                    rows.append(row)
                scores.write(json.dumps({"typed": typed, "words": rows}, ensure_ascii=False) + "\n")
            out = [p[0] for p in parts]
            for r, i in enumerate(words):
                w = parts[i][0]
                if classes[r] == 0 or len(w) > MAXLEN:
                    continue
                new = vocab[classes[r] - 1]
                if key(new) == key(w.lower()):
                    continue  # chỉ khác chỗ đặt dấu thanh hoặc hoa thường: giữ cách viết của người gõ
                out[i] = new.upper() if w.isupper() and len(w) > 1 else new.capitalize() if w[0].isupper() else new
            print(f"{typed}\t{''.join(out)}")
    times.sort()
    print(f"{len(times)} câu, CPU một luồng (PyTorch): trung vị {times[len(times) // 2]:.1f} ms, p95 {times[int(len(times) * 0.95)]:.1f} ms",
          file=sys.stderr)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "prepare":
        prepare(sys.argv[2], sys.argv[3], sys.argv[4])
    elif cmd == "train":
        train(int(sys.argv[sys.argv.index("--steps") + 1]) if "--steps" in sys.argv else 40000)
    elif cmd == "predict":
        # `--scores <tệp>`: ghi thêm điểm từng ứng viên (JSON, mỗi dòng một câu) cho `vnkey-tool eval --engine hybrid:<tệp>`.
        args = sys.argv[2:]
        out = None
        if "--scores" in args:
            i = args.index("--scores")
            out = open(args[i + 1], "w", encoding="utf-8")
            del args[i : i + 2]
        margin = 0.0
        if "--margin" in args:
            i = args.index("--margin")
            margin = float(args[i + 1])
            del args[i : i + 2]
        predict(args, out, margin)
    else:
        print(__doc__)

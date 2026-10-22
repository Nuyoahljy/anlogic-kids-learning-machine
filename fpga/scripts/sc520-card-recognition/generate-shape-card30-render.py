"""Literal T030 display oracle using frozen font bitmaps and official RGBA."""
from pathlib import Path
import hashlib
import json
import re
import numpy as np
from PIL import Image


def generate(inputs):
    inputs = Path(inputs)
    glyphs = json.loads((inputs / "font-extension.json").read_text(encoding="utf-8"))["Glyphs"]
    font = {g["char"]: [int(v, 16) for v in g["rows_hex"]] for g in glyphs}
    tiny = {c: int(bits.replace("_", ""), 2) for c, bits in re.findall(
        r'"(.)":bitmap=35\'b([01_]+)', (inputs / "tiny-reference.sv").read_text(encoding="utf-8"))}
    assert len(tiny) >= 30
    tiny["K"] = int("10001_10010_10100_11000_10100_10010_10001".replace("_", ""), 2)
    logo = np.asarray(Image.open(inputs / "anlogic_logo_rgba.png").convert("RGBA"))
    assert logo.shape == (94, 146, 4)
    literal = [
        ["探索模式  题号 --/10   分数 00/10", "摄像来源：实时画面，待实物验收".ljust(24) + "原图",
         "语音未接入", "探索学习：放入积木或卡片认识物体",
         "K1模式 K2重播 K3切图 K4清分", "当前识别：圆形"],
        ["探索模式  题号 --/10   分数 00/10", "摄像来源：实时画面，待实物验收".ljust(24) + "处理图",
         "语音未接入", "探索学习：放入积木或卡片认识物体",
         "K1模式 K2重播 K3切图 K4清分", "当前识别：方形"],
        ["问答模式  题号 01/10   分数 00/10", "摄像来源：实时画面，待实物验收".ljust(24) + "处理图",
         "语音未接入", "请找出：三角形", "已确认移走，请放入答案", "当前识别：未知目标"],
        ["问答模式  题号 01/10   分数 00/10", "摄像来源：实时画面，待实物验收".ljust(24) + "处理图",
         "语音未接入", "请找出：三角形", "识别不可信：请移走物体，等待恢复", "当前识别：不可信"],
    ]
    diagnostics = []
    cases = []
    fields = [(64, 16, 0x456), (80, 16, 0x33), (48, 4, 10), (55, 1, 1),
              (56, 8, 3), (96, 4, 3), (100, 4, 15), (112, 11, 0x13),
              (123, 11, 0x45), (134, 11, 0x89), (145, 11, 0x21),
              (156, 11, 0x50), (167, 11, 0x3AA), (178, 4, 1), (182, 4, 1), (186, 1, 1)]
    for case, lines in enumerate(literal):
        packet = sum(value << bit for bit, width, value in fields)
        packet |= (0x12345678 + case) | (1 << 34) | (1 << 33) | (1 << 39)
        packet |= ([1, 2, 0, 3][case] << 40) | (1 << 52) | (1 << 44)
        if case != 2:
            packet |= 1 << 35
        if case == 3:
            packet &= ~((1 << 33) | (1 << 101))
            packet |= (1 << 36) | (0x20 << 104)
        mode = int(case != 0)
        business = (1 if case < 2 else 2) << 26
        business |= (0 if case < 2 else 1) << 24
        business |= (0 if case < 2 else 1) << 16
        business |= (0 if case < 2 else 3) << 12
        business |= [1, 2, 0, 3][case] << 8
        business |= (1 if case >= 2 else 0) << 3
        business |= 1
        cases.append(f"{business:07X} {packet:048X} 12 {mode} 1 0\n")
        diag = [[" "] * 96 for _ in range(6)]

        def put(row, col, text):
            diag[row][col:col + len(text)] = text

        for row, col, text in [
            (0, 0, "D0300"), (0, 6, f"F{0x12345678 + case:08X}"),
            (0, 16, "H0 " if case == 3 else "H1 "), (0, 20, "P1 "),
            (0, 24, "V0" if case >= 2 else "V1"), (0, 27, "R1" if case == 3 else "R0"),
            (0, 30, "INA" if case == 3 else f"I{[1, 2, 0, 3][case]:X} "),
            (0, 34, "A12"), (0, 38, "T0 "),
            (1, 0, "SC0456"), (1, 7, "GL0033"), (1, 14, "CL0 "), (1, 19, "B0 "),
            (1, 23, "P1 "), (1, 27, "AV5" if case == 3 else "AV7"), (1, 31, "K1"),
            (2, 0, "SHNA" if case == 3 else "SH1 "),
            (2, 5, "CNA " if case == 3 else "C013"),
            (2, 10, "QNA " if case == 3 else "Q045"),
            (2, 15, "TNA " if case == 3 else "T089"),
            (2, 20, "SINA" if case == 3 else "SI1 "),
            (3, 0, "CWA "), (3, 5, "CQ1 "), (3, 10, "B021"), (3, 15, "S050"), (3, 20, "FG3AA"),
            (4, 0, "AR3 "), (4, 4, "DN1"), (4, 8, "CN03"),
            (4, 13, "RS20" if case == 3 else "RS00"),
            (5, 0, "CAT1 "), (5, 6, "REV1 "), (5, 12, "FR1"),
        ]:
            put(row, col, text)
        diagnostics.append(["".join(row) for row in diag])
        image = np.zeros((720, 1280), dtype=np.uint32)
        raw = [(0xC0, 0x40, 0x20), (0xC0, 0xB0, 0x30), (0x30, 0x50, 0xC0), (0x60, 0x70, 0x80)]
        enhanced = []
        for r, g, b in raw:
            y = 77 * r + 150 * g + 29 * b
            values = [max(0, min(255, (1280 * c - y + 512) // 1024)) for c in (r, g, b)]
            enhanced.append((values[0] << 16) | (values[1] << 8) | values[2])
        segmented = []
        for channels in raw:
            total = sum(channels)
            classes = [i for i, value in enumerate(channels)
                       if (value - max(channels[j] for j in range(3) if j != i)) * 100 >= total * 3]
            segmented.append([0xFF0000, 0xFFFF00, 0x0000FF][classes[0]] if total and classes else 0)
        for i, color in enumerate(enhanced if case == 0 else segmented):
            image[:, i * 320:(i + 1) * 320] = color
        image[120, 160:1120] = image[599, 160:1120] = 0xFF0000
        image[120:600, 160] = image[120:600, 1119] = 0xFF0000
        image[8:112, 32:1248] = image[608:712, 32:1248] = 0x18242C
        tones = [1, 1, 0, 1 if case >= 2 else 0, 2 if case == 3 else 0, 2 if case == 3 else 0]
        inks = [0xF5F7FA, 0xABE8F2, 0xFFE3A3, 0x9EF0CC]
        for row, text in enumerate(lines):
            assert len(text) <= (30 if row < 3 else 37)
            oy = [12, 44, 76, 612, 644, 676][row]
            for col, char in enumerate(text):
                if char == " ":
                    continue
                for y, bits in enumerate(font[char]):
                    for x in range(16):
                        if bits & (1 << (15 - x)):
                            image[oy + y * 2:oy + y * 2 + 2, 48 + col * 32 + x * 2:50 + col * 32 + x * 2] = inks[tones[row]]
        image[520:592, 32:800] = 0x101820
        for row, text in enumerate(diagnostics[-1]):
            for col, char in enumerate(text):
                bits = tiny.get(char, 0)
                for y in range(7):
                    for x in range(5):
                        if bits & (1 << (34 - y * 5 - x)):
                            image[520 + row * 12 + y, 32 + col * 8 + x] = 0xFF9C9C if case == 3 else 0xFFFF80
        packed = (logo[:, :, 0].astype(np.uint32) << 16) | (logo[:, :, 1].astype(np.uint32) << 8) | logo[:, :, 2]
        target = image[24:118, 1008:1154]
        target[logo[:, :, 3] != 0] = packed[logo[:, :, 3] != 0]
        (inputs / f"golden-{case}.mem").write_text("".join(f"{v:06X}\n" for v in image.flat), encoding="ascii")
        rgb = np.stack(((image >> 16) & 255, (image >> 8) & 255, image & 255), axis=2).astype(np.uint8)
        Image.fromarray(rgb).save(inputs / f"golden-{case}.png")
    (inputs / "render-cases.txt").write_text("".join(cases), encoding="ascii")
    missing_rows = [
        "D0300 FNA       HNA PNA V0 R1 INA A63 TNA",
        "SCNA   GLNA   CLNA BNA PNA AV0 K0",
        "SHNA CNA  QNA  TNA  SINA",
        "CWNA CQNA BNA  SNA  FGNA ",
        "ARNA DN0 CNNA RSNA",
        "CATNA REVNA FR0",
    ]
    # Explicit column assignments are shared with the signed display contract,
    # not inferred from the selector in the production RTL.
    missing = [[" "] * 96 for _ in range(6)]
    missing_fields = [
        (0, 0, "D0300"), (0, 6, "FNA      "), (0, 16, "HNA"), (0, 20, "PNA"),
        (0, 24, "V0"), (0, 27, "R1"), (0, 30, "INA"), (0, 34, "A63"), (0, 38, "TNA"),
        (1, 0, "SCNA  "), (1, 7, "GLNA  "), (1, 14, "CLNA"), (1, 19, "BNA"),
        (1, 23, "PNA"), (1, 27, "AV0"), (1, 31, "K0"),
        (2, 0, "SHNA"), (2, 5, "CNA "), (2, 10, "QNA "), (2, 15, "TNA "), (2, 20, "SINA"),
        (3, 0, "CWNA"), (3, 5, "CQNA"), (3, 10, "BNA "), (3, 15, "SNA "), (3, 20, "FGNA "),
        (4, 0, "ARNA"), (4, 4, "DN0"), (4, 8, "CNNA"), (4, 13, "RSNA"),
        (5, 0, "CATNA"), (5, 6, "REVNA"), (5, 12, "FR0"),
    ]
    for row, col, text in missing_fields:
        missing[row][col:col + len(text)] = text
    missing_rows = ["".join(row) for row in missing]
    patch = np.full((72, 768), 0x101820, dtype=np.uint32)
    for row, text in enumerate(missing_rows):
        for col, char in enumerate(text):
            bitmap = tiny.get(char, 0)
            for y in range(7):
                for x in range(5):
                    if bitmap & (1 << (34 - y * 5 - x)):
                        patch[row * 12 + y, col * 8 + x] = 0xFF9C9C
    (inputs / "missing-diagnostic.mem").write_text("".join(f"{v:06X}\n" for v in patch.flat), encoding="ascii")
    (inputs / "render-oracle.json").write_text(json.dumps(dict(
        LiteralUI=literal, DiagnosticRows=diagnostics, Cases=4, PixelsPerCase=921600,
        MissingDiagnosticRows=missing_rows, MissingDiagnosticPixels=55296,
        Reference="Literal expected text/columns; frozen JSON font and old tiny-reference, official RGBA. No production RTL selector.",
        NewKGlyphReference="Literal conventional 5x7 letter K rows10001,10010,10100,11000,10100,10010,10001; independently authored, not extracted from DUT.",
        TinySHA256=hashlib.sha256((inputs / "tiny-reference.sv").read_bytes()).hexdigest().upper()
    ), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

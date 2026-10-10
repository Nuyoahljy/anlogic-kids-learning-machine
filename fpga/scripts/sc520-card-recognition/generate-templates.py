#!/usr/bin/env python3
"""Generate traceable prep-v1 model fixtures; never overwrite an existing run."""
from __future__ import annotations

import argparse
import hashlib
import json
import random
import subprocess
import sys
import traceback
from datetime import datetime, timezone, timedelta
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance

ITEMS = [(10, "apple", "苹果"), (11, "banana", "香蕉"),
         (12, "car", "汽车"), (13, "star", "星星"), (14, "umbrella", "雨伞")]
WHITE = (255, 255, 255)
THRESHOLDS = {"dark_min_exclusive": 180, "chroma_min_inclusive": 40,
              "max_distance": 120, "min_margin": 24,
              "min_foreground": 16, "max_foreground": 850}
FRAME = {"width": 320, "height": 180, "roi_x": 96, "roi_y": 26,
         "roi_size": 128, "sample_step": 4, "sample_offset": 2}
NODE_RENDERER = r"""
const fs = require('fs');
const path = require('path');
const sharp = require(path.join(process.argv[3], 'sharp'));
const entries = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
(async () => {
  for (const entry of entries) {
    await sharp(entry.source, {density: 96}).resize(256, 256)
      .flatten({background: '#ffffff'}).removeAlpha().png().toFile(entry.png);
  }
  process.stdout.write(JSON.stringify(sharp.versions));
})().catch(e => {process.stderr.write(String(e)); process.exit(1);});
"""


def write_text(path: Path, text: str) -> None:
    path.write_bytes(text.encode("utf-8"))


def write_json(path: Path, value: object) -> None:
    write_text(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fg(rgb: tuple[int, int, int]) -> int:
    return int(min(rgb) < 180 or max(rgb) - min(rgb) >= 40)


def mask(image: Image.Image, step: int, offset: int) -> list[int]:
    return [fg(image.getpixel((gx * step + offset, gy * step + offset)))
            for gy in range(32) for gx in range(32)]


def classify(bits: list[int], templates: list[list[int]]) -> dict:
    distances = [sum(a != b for a, b in zip(bits, t)) for t in templates]
    ranked = sorted((d, index + 10) for index, d in enumerate(distances))
    best, item = ranked[0]
    second = ranked[1][0]
    count = sum(bits)
    accepted = 16 <= count <= 850 and best <= THRESHOLDS["max_distance"] and second - best >= 24
    return {"distances_item_10_to_14": distances, "candidate_item_id": item,
            "accepted": accepted, "accepted_item_id": item if accepted else 0,
            "best_distance": best, "second_distance": second,
            "margin": second - best, "foreground_count": count}


def shifted(image: Image.Image, x: int, y: int) -> Image.Image:
    canvas = Image.new("RGB", (128, 128), WHITE)
    canvas.paste(image, (x, y))
    return canvas


def samples(canonical: dict[int, Image.Image]) -> list[tuple]:
    result = []
    for item, name, _ in ITEMS:
        image = canonical[item]
        result.append((f"canonical_{name}", "canonical", item, image.copy(),
                       "原SVG派生，接口自一致样本，不计作独立准确率"))
    for item, name, _ in ITEMS:
        image = canonical[item]
        for suffix, dx, dy in [("left", -4, 0), ("right", 4, 0), ("up", 0, -4), ("down", 0, 4)]:
            result.append((f"shift_{name}_{suffix}", "shift_one_cell", item,
                           shifted(image, dx, dy), f"整幅卡面平移({dx},{dy})像素，白色填充，无循环回绕"))
        for angle in [-5, 5]:
            result.append((f"rotate_{name}_{'minus' if angle < 0 else 'plus'}5", "rotate", item,
                           image.rotate(angle, resample=Image.Resampling.BILINEAR, fillcolor=WHITE),
                           f"围绕图心旋转{angle}度，双线性插值，白色填充"))
        for label, factor in [("dark", 0.65), ("bright", 1.20)]:
            result.append((f"brightness_{name}_{label}", "brightness", item,
                           ImageEnhance.Brightness(image).enhance(factor),
                           f"RGB及白背景统一乘{factor}；固定暗阈值可把暗背景误当前景"))
        rng = random.Random(20261010 + item)
        noisy = image.copy()
        points = rng.sample(range(128 * 128), 328)
        for index in points:
            noisy.putpixel((index % 128, index // 128), (0, 0, 0) if rng.randrange(2) else WHITE)
        result.append((f"noise_{name}", "salt_pepper_noise", item, noisy,
                       f"固定seed={20261010 + item}，328个不同RGB像素置黑或白"))
        hidden = image.copy()
        ImageDraw.Draw(hidden).rectangle((64, 0, 127, 127), fill=WHITE)
        result.append((f"occlusion_{name}", "half_occlusion", item, hidden,
                       "卡面右半幅由白色覆盖；观察拒识或误判，不要求仍识别"))
    result.append(("all_white", "negative_blank", 0, Image.new("RGB", (128, 128), WHITE), "全白背景"))
    result.append(("all_black", "negative_black", 0, Image.new("RGB", (128, 128), (0, 0, 0)), "全黑背景"))
    colors = [("red", (215, 61, 60)), ("yellow", (245, 205, 45)), ("blue", (50, 112, 205))]
    for name, rgb in colors:
        for shape in ["circle", "square", "triangle"]:
            image = Image.new("RGB", (128, 128), WHITE)
            draw = ImageDraw.Draw(image)
            if shape == "circle":
                draw.ellipse((26, 26, 102, 102), fill=rgb)
            elif shape == "square":
                draw.rectangle((26, 26, 102, 102), fill=rgb)
            else:
                draw.polygon([(64, 22), (22, 105), (106, 105)], fill=rgb)
            result.append((f"negative_{name}_{shape}", "negative_geometry", 0, image,
                           "独立Pillow几何负样本，非卡片；不是九积木实拍或仲裁验证"))
    mixed = canonical[10].copy()
    mixed.paste(canonical[14].crop((64, 0, 128, 128)), (64, 0))
    result.append(("unknown_apple_umbrella", "negative_mix", 0, mixed, "左苹果右雨伞合成的未知物"))
    image = Image.new("RGB", (128, 128), WHITE)
    draw = ImageDraw.Draw(image)
    for y in range(0, 128, 16):
        for x in range(0, 128, 16):
            if (x // 16 + y // 16) % 2 == 0:
                draw.rectangle((x, y, x + 15, y + 15), fill=(20, 20, 20))
    result.append(("unknown_checkerboard", "negative_unknown", 0, image, "8x8黑白棋盘格"))
    image = Image.new("RGB", (128, 128), WHITE)
    draw = ImageDraw.Draw(image)
    for x in range(0, 128, 4):
        draw.line((x, 0, x, 127), fill=(0, 0, 0), width=1)
    result.append(("between_sample_lines", "negative_unsampled", 0, image,
                   "每4像素在x=0画1像素竖线，x=2采样点全白但ROI有4096前景像素"))
    return result


def generate(args: argparse.Namespace) -> None:
    if not 0 <= args.max_distance <= 1024:
        raise ValueError("max-distance must be in 0..1024")
    THRESHOLDS["max_distance"] = args.max_distance
    root = args.output.resolve()
    if root.exists():
        raise FileExistsError(f"refusing to overwrite existing output: {root}")
    root.mkdir(parents=True)
    try:
        render_dir = root / "rendered"
        vector_dir = root / "vectors"
        render_dir.mkdir()
        vector_dir.mkdir()
        sources = []
        for item, name, label in ITEMS:
            source = args.source.resolve() / f"card_{item}_{name}.svg"
            sources.append({"item_id": item, "name": name, "label": label,
                            "source": source.as_posix(), "source_sha256": sha(source),
                            "png": (render_dir / f"card_{item}_{name}_256.png").as_posix()})
        jobs = root / "render-jobs.json"
        write_json(jobs, sources)
        call = [str(args.node), "-e", NODE_RENDERER, str(jobs), "unused", str(args.node_module_root)]
        rendered = subprocess.run(call, check=False, capture_output=True, text=True, encoding="utf-8")
        write_text(root / "renderer.stdout.txt", rendered.stdout)
        write_text(root / "renderer.stderr.txt", rendered.stderr)
        if rendered.returncode:
            raise RuntimeError(f"sharp renderer exited {rendered.returncode}: {rendered.stderr}")
        versions = json.loads(rendered.stdout)
        templates = []
        canonical = {}
        entries = []
        preview = Image.new("RGB", (5 * 256, 568), (235, 238, 242))
        draw = ImageDraw.Draw(preview)
        for col, source in enumerate(sources):
            image256 = Image.open(source["png"]).convert("RGB")
            bits = mask(image256, 8, 4)
            templates.append(bits)
            # Explicit integer coordinates avoid resize-filter/half-pixel ambiguities.
            image128 = Image.new("RGB", (128, 128))
            image128.putdata([image256.getpixel((2 * x, 2 * y)) for y in range(128) for x in range(128)])
            canonical[source["item_id"]] = image128
            assert mask(image128, 4, 2) == bits
            binary = Image.new("RGB", (32, 32))
            binary.putdata([(0, 0, 0) if b else WHITE for b in bits])
            binary_path = render_dir / f"card_{source['item_id']}_{source['name']}_mask.png"
            binary.resize((256, 256), Image.Resampling.NEAREST).save(binary_path)
            preview.paste(image256, (256 * col, 22))
            preview.paste(Image.open(binary_path), (256 * col, 306))
            draw.text((256 * col + 10, 4), f"{source['item_id']} {source['name']} - SVG", fill=(0, 0, 0))
            draw.text((256 * col + 10, 288), f"32x32: {sum(bits)} foreground", fill=(0, 0, 0))
            entry = {**source, "rendered_png": Path(source["png"]).relative_to(root).as_posix(),
                     "rendered_sha256": sha(Path(source["png"])), "foreground_count": sum(bits),
                     "mask_rows": ["".join(str(b) for b in bits[y * 32:(y + 1) * 32]) for y in range(32)]}
            entry.pop("png")
            entries.append(entry)
        preview.save(root / "templates-preview.png")
        packed = [sum(t[index] << k for k, t in enumerate(templates)) for index in range(1024)]
        write_text(root / "templates.mem", "".join(f"{word:02x}\n" for word in packed))
        template_info = {"schema": "sc520-card-templates-v1", "status": "software-model-only-not-camera-validated",
                         "source_version": "prep-v1", "grid": [32, 32], "thresholds": THRESHOLDS,
                         "sampling": "256x256: pixel (8*gx+4,8*gy+4), gy-major",
                         "packing": "1024 lines of 5-bit hex; bit0=item10,...,bit4=item14",
                         "templates_mem_sha256": sha(root / "templates.mem"),
                         "pairwise_hamming": [[sum(a != b for a, b in zip(x, y)) for y in templates] for x in templates],
                         "templates": entries}
        write_json(root / "templates.json", template_info)
        vectors = []
        metadata = []
        statements = []
        vector_list = []
        for index, (name, category, truth, image, note) in enumerate(samples(canonical)):
            stem = f"{index:03d}_{name}"
            rgb_file = vector_dir / f"{stem}.rgb.mem"
            bits_file = vector_dir / f"{stem}.bits.mem"
            image_file = vector_dir / f"{stem}.png"
            image.save(image_file)
            pixels = [image.getpixel((x, y)) for y in range(128) for x in range(128)]
            bits = mask(image, 4, 2)
            expected = classify(bits, templates)
            expected["roi_foreground_pixels"] = sum(fg(rgb) for rgb in pixels)
            write_text(rgb_file, "".join(f"{r:02x}{g:02x}{b:02x}\n" for r, g, b in pixels))
            write_text(bits_file, "".join(f"{b}\n" for b in bits))
            outcome = "correct_accept" if truth and expected["accepted_item_id"] == truth else (
                "reject" if not expected["accepted"] else ("false_accept" if truth == 0 else "confusion"))
            vectors.append({"index": index, "id": name, "category": category, "ground_truth_item_id": truth,
                            "note": note, "rgb_mem": rgb_file.relative_to(root).as_posix(),
                            "bits_mem": bits_file.relative_to(root).as_posix(),
                            "preview_png": image_file.relative_to(root).as_posix(), "expected": expected,
                            "model_outcome": outcome, "rgb_mem_sha256": sha(rgb_file), "bits_mem_sha256": sha(bits_file)})
            metadata.extend([index, truth, expected["candidate_item_id"], expected["accepted_item_id"],
                             expected["best_distance"], expected["second_distance"],
                             expected["foreground_count"], expected["roi_foreground_pixels"]])
            statements.append(f'vector_rgb_file[{index}] = "vectors/{stem}.rgb.mem";\nvector_bits_file[{index}] = "vectors/{stem}.bits.mem";')
            vector_list.append(f"{stem} {expected['accepted_item_id']} {expected['best_distance']} {expected['second_distance']} {expected['foreground_count']} {expected['roi_foreground_pixels']} {truth}")
        write_json(root / "vectors.json", {"schema": "sc520-card-vectors-v1", "frame": FRAME,
                                         "thresholds": THRESHOLDS, "count": len(vectors),
                                         "rgb_memory": "128x128 ROI only, row-major, 24-bit RGB888 hex RRGGBB; other frame pixels ffffff",
                                         "bits_memory": "1024 lines, bit per line in gy-major order",
                                         "meta_memory": ["index", "ground_truth_item_id", "candidate_item_id", "accepted_item_id", "best_distance", "second_distance", "foreground_count", "roi_foreground_pixels"],
                                         "vectors": vectors})
        write_text(root / "vectors.meta.mem", "".join(f"{v:08x}\n" for v in metadata))
        write_text(root / "vectors.list", "\n".join(vector_list) + "\n")
        write_text(root / "vectors-files.vh", "// Include inside an initial block; paths relative to this dataset root.\n" + "\n".join(statements) + "\n")
        write_text(root / "vectors-count.vh", f"`define CARD_VECTOR_COUNT {len(vectors)}\n")
        summary = {"total": len(vectors), "canonical": {}, "synthetic_variations": {}, "negatives": {}, "by_category": {}}
        for vector in vectors:
            group = "canonical" if vector["category"] == "canonical" else ("negatives" if not vector["ground_truth_item_id"] else "synthetic_variations")
            outcome = vector["model_outcome"]
            summary[group][outcome] = summary[group].get(outcome, 0) + 1
            counts = summary["by_category"].setdefault(vector["category"], {})
            counts[outcome] = counts.get(outcome, 0) + 1
        report = {"summary": summary,
                  "false_accepts": [{"id": v["id"], "expected": v["expected"]} for v in vectors if v["model_outcome"] == "false_accept"],
                  "confusions": [{"id": v["id"], "truth": v["ground_truth_item_id"], "expected": v["expected"]} for v in vectors if v["model_outcome"] == "confusion"],
                  "caveats": ["Canonical与模板同源，只证明坐标/序列/接口一致，不属于独立准确率。",
                              "平移、旋转、亮度、噪点和遮挡均为人工变换；这些结果不代表相机/打印/摆放实测。",
                              "不执行位移搜索、尺度归一化、透视校正或相机白平衡校准。",
                              "min RGB<180将暗灰白背景也视为前景；偏暗样本会拒识。",
                              "颜色被二值化后，九几何负样本每形状的三色成为同一个轮廓。",
                              "全白与白卡无图案的物理存在无法区分；采样外细线依赖全ROI前景存在信号。",
                              "unknown拒识只保证本组有限模型案例，不能推断任意未知物都拒识。"]}
        write_json(root / "model-report.json", report)
        lines = ["# 五卡软件模型数据", "", "状态：软件模型与RTL接口候选，尚未相机模板验收。", "",
                 "原稿为 `learning/sc520-next-stage-prep/cards/` 的 prep-v1 五个 SVG，本脚本只读输入，逐个记录源哈希。",
                 "`templates-preview.png` 上排为 256×256 渲染，下排为 32×32 二值模板放大图。", "",
                 "- 二值条件：`min(R,G,B)<180 || max(R,G,B)-min(R,G,B)>=40`。前景为1、背景为0。",
                 "- 模板点：256图的 `(8*gx+4,8*gy+4)`；按行存储，`templates.mem` bit0..4对应10..14。",
                 "- RGB激励：320×180帧，ROI左上角(96,26)、128×128；每格4像素、中心偏移2。",
                 "- canonical ROI每个像素(x,y)取256图的(2x,2y)，精确对应模板采样点。这里没有用双线性缩小，也没有相机过程。",
                 f"- 比较：1024位Hamming距离；`best<={args.max_distance}`、`second-best>=24`、前景16..850才输出候选ID；否则0。",
                 "- 距离平局的候选暂选较小ID，仅作为调试信息；margin=0使最终结果拒识。", "",
                 "## 文件接口", "", "`vectors.json`给每个样本输入文件、真实语义标签和软件模型输出。`ground_truth_item_id=0`表示负样本。模型输出不是语义标签。",
                 "`vectors/*.rgb.mem`是128×128 ROI，共16384行，RGB888十六进制RRGGBB；帧其余像素填FFFFFF。",
                 "`vectors/*.bits.mem`是32×32采样，共1024行0或1。`vectors.meta.mem`每样本8个32位hex：index、truth、candidate、accepted、best、second、sample_fg、roi_fg。",
                 "`vectors-files.vh`放入Verilog initial块，预先声明vector_rgb_file和vector_bits_file数组；路径相对数据集根目录。`vectors-count.vh`定义CARD_VECTOR_COUNT。", "",
                 "`vectors.list`每行是`stem accepted best second sample_fg roi_fg truth`，数字为十进制；stem加前缀`vectors/`和后缀`.rgb.mem`或`.bits.mem`得到文件路径。", "",
                 "## 本组模型结果", "", "```json", json.dumps(summary, ensure_ascii=False, indent=2), "```", "",
                 "每项结果见 `model-report.json`、`vectors.json`。测试不强迫所有扰动被识别；预期值用于比较RTL是否与这个明确模型一致。", "",
                 "## 复现", "", "使用已有Pillow的Python与已有sharp的Node，不下载或安装依赖。输出目录必须不存在，失败目录保留；新运行请换目录名。", "", "```powershell",
                 "& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' `",
                 "  fpga/scripts/sc520-card-recognition/generate-templates.py `",
                 "  --source E:/juan/FPGA/learning/sc520-next-stage-prep/cards `",
                 "  --output assets/templates/sc520-card-recognition/new-run `",
                 f"  --max-distance {args.max_distance}", "```", "",
                 "程序从bundled Python的相邻dependencies目录寻找Node和sharp，也可显式传入`--node`、`--node-module-root`。软件版本、源输入及输出哈希见`generation.json`和`manifest.json`。", "",
                 "## 边界", ""]
        lines.extend(f"- {note}" for note in report["caveats"])
        write_text(root / "README.md", "\n".join(lines) + "\n")
        for entry in sources:
            assert sha(Path(entry["source"])) == entry["source_sha256"], "source changed while rendering"
        write_json(root / "generation.json", {"status": "completed", "created_at": datetime.now(timezone(timedelta(hours=8))).isoformat(),
                    "python": sys.version, "script": Path(__file__).resolve().as_posix(), "script_sha256": sha(Path(__file__)),
                    "renderer": "sharp/libvips SVG rasterizer", "versions": versions,
                    "command": [sys.executable, *sys.argv], "source_hashes_unchanged": True, "vectors": len(vectors)})
        write_json(root / "manifest.json", {"files": [{"path": p.relative_to(root).as_posix(), "bytes": p.stat().st_size, "sha256": sha(p)}
                                                        for p in sorted(root.rglob("*")) if p.is_file()]})
        print(json.dumps({"output": root.as_posix(), "summary": summary}, ensure_ascii=False))
    except Exception:
        write_json(root / "generation-failure.json", {"status": "failed", "traceback": traceback.format_exc(), "command": sys.argv})
        raise


def main() -> None:
    deps = Path(sys.executable).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--node", type=Path, default=deps / "node/bin/node.exe")
    parser.add_argument("--node-module-root", type=Path, default=deps / "node/node_modules")
    parser.add_argument("--max-distance", type=int, default=120)
    generate(parser.parse_args())


if __name__ == "__main__":
    main()

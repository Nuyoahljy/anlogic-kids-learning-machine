"""Register only this task's authored files and actual generated output folders."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import json
import subprocess
import uuid

R = Path(__file__).resolve().parents[3]
W = Path("E:/juan/FPGA")
ap = argparse.ArgumentParser()
ap.add_argument("--summary", required=True)
ap.add_argument("--validation", required=True)
args = ap.parse_args()
now = datetime.now(timezone(timedelta(hours=8)))
tag = now.strftime("%Y%m%d-%H%M%S") + "-contour29-implementation-" + uuid.uuid4().hex[:6]
record = W / "workspace-records" / (tag + ".json")
files = []
for folder in ("fpga/rtl/sc520-contour29", "fpga/sim/sc520-contour29",
               "fpga/custom_project/sc520-contour29/overlay", "hardware/sc520-contour29",
               "assets/templates/sc520-contour29"):
    files += [p for p in (R / folder).rglob("*") if p.is_file()]
files += list((R / "fpga/scripts/sc520-card-recognition").glob("*contour29*"))
changes = [dict(Path=str(path), Action="observed",
                Purpose="本任务新增独立T029源/测试/工程/模型/工具，逐文件登记；不改D0270或AWB28",
                Status="进行中；实际通过与失败见本批Validation和各原生manifest") for path in files if path.is_file()]
changes.append(dict(Path=str(R / "memory/branches/sc520-color-integration.md"), Action="modified",
                    Purpose="同步本轮T029合同/实现/真实验证及未完项", Status="进行中"))
evidence = R / "evidence/sc520-contour29"
for folder in sorted(p for p in evidence.iterdir() if p.is_dir()):
    changes.append(dict(Path=str(folder), Action="generated",
                        Purpose="T029实际生成的输入/模型/仿真/原生缓存目录，确切命令和SHA见原始manifest",
                        Status="含通过/失败/在途，分清原生结果；硬件未验证"))
for path in sorted(evidence.glob("*.json")) + sorted(evidence.glob("runs/*/run-manifest.json")):
    changes.append(dict(Path=str(path), Action="observed",
                        Purpose="T029重要保护/运行清单，原字节与原生失败保留", Status="见原始JSON实际字段"))
changes.append(dict(Path=str(record), Action="added", Purpose="本轮独立实现批次登记", Status="实际登记"))
record.write_text(json.dumps(dict(Id=tag, UpdatedAt=now.isoformat(), Task="sc520-contour29",
    Owner="Codex /root/shape27_delivery", Workdir=str(R), Summary=args.summary, Validation=args.validation,
    NextStep="继续真实软件与独立审核；软件主接受前不启动TD，物理主审后再bitgen；不自动下载或Flash。",
    Changes=changes), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
for flags in ([], ["-Check"]):
    subprocess.run(["pwsh", "-NoProfile", "-File", str(W / "anlogic-kids-learning-machine/tools/update-workspace-index.ps1"), *flags], check=True)
print(tag)

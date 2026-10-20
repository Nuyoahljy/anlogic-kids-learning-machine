"""Build full-system fixed-truth matrices from all old and new RGB fixtures."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import importlib.util
import json
import numpy as np

R = Path(__file__).resolve().parents[3]
S = Path(__file__).parent
spec = importlib.util.spec_from_file_location("contour29_final_system", S / "model-contour29-final.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
spec = importlib.util.spec_from_file_location("contour29_system_utils", S / "evaluate-contour29.py")
e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e)


def main():
    bank = m.base.read_bank(e.A / "templates.mem")
    outputs = []
    for mode in ("new", "retained"):
        out = R / "evidence/sc520-contour29" / (mode + "-system-v1")
        out.mkdir(parents=True, exist_ok=False)
        selected = []
        if mode == "new":
            for case in json.loads((R / "evidence/sc520-contour29/fixtures-v1/manifest.json").read_text())["Cases"]:
                selected.append((case["Name"], Path(case["RGB"]["Path"]), case["TruthItem"]))
        else:
            for case in json.loads((e.A / "fixtures.json").read_text()):
                path = e.A / "vectors" / (case["prefix"] + ".rgb.mem")
                if not path.exists():
                    path = path.with_suffix("").with_suffix(".png")
                selected.append((case["prefix"], path, case["truth_item"]))
            for case in json.loads((R / "evidence/sc520-color-integration/scenes/manifest.json").read_text())["Cases"]:
                selected.append((case["Name"], Path(case["Path"]), case.get("Item", case.get("ExpectedItem"))))
        rows = []
        for i, (name, path, truth) in enumerate(selected):
            assert truth is not None, name
            rgb = e.read_rgb(path)
            result = m.recognize(m.base.sample_frame(rgb), bank)
            prefix = f"{mode[0]}{i:03d}"
            target = out / (prefix + ".rgb.mem")
            if path.suffix == ".mem":
                target.write_bytes(path.read_bytes())
            else:
                target.write_text("".join("%02X%02X%02X\n" % tuple(p) for p in rgb.reshape(-1, 3)), encoding="ascii")
            rows.append(dict(Name=name, Prefix=prefix, TruthItem=truth, ExpectedContractItem=result["item"],
                             Present=bool(result["present"]), KnownMiss=truth != 0 and result["item"] == 0,
                             Source=e.artifact(path), RGB=e.artifact(target)))
        (out / "cases.txt").write_text("".join(f"{r['ExpectedContractItem']} {int(r['Present'])} {r['Prefix']}\n" for r in rows), encoding="ascii")
        (out / "truth-cases.txt").write_text("".join(f"{r['TruthItem']} {int(r['Present'])} {r['Prefix']}\n" for r in rows), encoding="ascii")
        report = dict(At=datetime.now(timezone(timedelta(hours=8))).isoformat(),
                      Owner="Codex /root/shape27_delivery", Generator=e.artifact(__file__),
                      Model=e.artifact(S / "model-contour29-final.py"), Cases=rows,
                      TruthLabelPolicy="Original TruthItem is immutable. ExpectedContractItem records disclosed conservative unknowns separately. Legacy uses TruthItem and preserves complete failures.",
                      Counts=dict(Cases=len(rows), KnownMisses=sum(r["KnownMiss"] for r in rows)))
        (out / "manifest.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        outputs.append(report["Counts"])
    print(json.dumps(outputs))


if __name__ == "__main__":
    main()

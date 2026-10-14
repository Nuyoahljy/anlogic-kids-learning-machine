"""Replay dense mask-model failures at the exact bp sampling phase in full RGB."""
from __future__ import annotations
import argparse
from datetime import datetime,timezone,timedelta
import hashlib
import importlib.util
import json
from pathlib import Path
import numpy as np
from PIL import Image

HERE=Path(__file__).resolve().parent;REPO=HERE.parents[2]
spec=importlib.util.spec_from_file_location("generate_rotation",HERE/"generate-rotation-fixtures.py")
generator=importlib.util.module_from_spec(spec);spec.loader.exec_module(generator)
model=generator.model

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,default=REPO/"evidence/sc520-card-recognition/rotation-refusals-20261014")
    args=parser.parse_args();out=args.output.resolve()
    if out.exists():parser.error("refusing overwrite")
    out.mkdir(parents=True);(out/"vectors").mkdir()
    assets=REPO/"assets/templates/sc520-card-recognition/rotation-v1"
    dense=json.loads((assets/"angle-evaluation.json").read_text(encoding="utf-8"))["rows"]
    bank=model.read_bank(assets/"templates.mem")
    source=REPO/"assets/templates/sc520-card-recognition/prep-v1-max40/rendered"
    images={i:Image.open(source/f"card_{i}_{n}_256.png").convert("RGB") for i,n in generator.ITEMS}
    rows=[]
    for original in dense:
        if original["truth_satisfied"]:continue
        # A bp frame samples x=41+2k/y=31+2k. Therefore the local phase is
        # (1-left)%2/(1-top)%2, the inverse of the pasted image's parity.
        phase=(1-original["phase_x"])+2*(1-original["phase_y"])
        frame,recipe=generator.physical_frame(images[original["truth_item"]],original["angle"],original["size_bp"],"white",1,phase)
        local_phase=[(41-recipe["left"])%2,(31-recipe["top"])%2]
        if local_phase!=[original["phase_x"],original["phase_y"]]:raise AssertionError("sampling phase mismatch")
        result=model.recognize(frame,bank)
        prefix=f"q{len(rows):03d}_card_{original['truth_item']}_{original['size_bp']}_{str(original['angle']).replace('.','p')}_{original['phase_x']}{original['phase_y']}"
        row={"prefix":prefix,"truth_item":original["truth_item"],"truth_present":True,"recipe":recipe,
            "local_phase":local_phase,"dense_original":original,
            "expected":{k:v for k,v in result.items() if not isinstance(v,np.ndarray)},
            "truth_satisfied":result["item"]==original["truth_item"],
            "same_distances_as_dense":result["card_raw"]["distances"]==original["distances"]}
        rows.append(row);folder=out/"vectors"
        Image.fromarray(frame).save(folder/f"{prefix}.png")
        generator.fixtures_v2.rgbmem(folder/f"{prefix}.rgb.mem",frame)
        generator.fixtures_v2.rgbmem(folder/f"{prefix}.replay.mem",result["replay_rgb"])
        generator.fixtures_v2.bitmem(folder/f"{prefix}.mask.mem",result["mask"])
    generator.save(out/"fixtures.json",rows)
    (out/"system-cases.txt").write_text("".join(f"{r['prefix']} {r['expected']['item']} {int(r['expected']['present'])}\n" for r in rows),encoding="ascii")
    summary={"count":len(rows),"full_rgb_accepted":sum(r["truth_satisfied"] for r in rows),
        "full_rgb_refused":sum(not r["truth_satisfied"] for r in rows),
        "exact_dense_distance_matches":sum(r["same_distances_as_dense"] for r in rows),
        "note":"Model consistency list uses actual expected item; original physical truth remains in fixtures.json. Full scene flood-fill may remove pale chromatic edge cells that the direct dense-mask sweep retains; differences are recorded, not erased."}
    generator.save(out/"summary.json",summary)
    generator.save(out/"manifest.json",{"created_at":datetime.now(timezone(timedelta(hours=8))).isoformat(),
        "templates_sha256":generator.sha(assets/"templates.mem"),"source_model_sha256":generator.sha(HERE/"scene-rotation-model.py"),
        "source_generator_sha256":generator.sha(HERE/"generate-rotation-fixtures.py"),"script_sha256":generator.sha(Path(__file__)),
        "outputs":[{"path":str(p.relative_to(out)),"sha256":generator.sha(p)} for p in sorted(out.rglob("*")) if p.is_file()]})
    print(json.dumps(summary,ensure_ascii=False))
    return 0

if __name__=="__main__":raise SystemExit(main())

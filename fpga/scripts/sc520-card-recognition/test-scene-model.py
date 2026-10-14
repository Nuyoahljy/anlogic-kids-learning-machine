"""Check scene evidence hashes and independent geometry/protocol properties."""
from __future__ import annotations
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import numpy as np

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[2]
spec=importlib.util.spec_from_file_location("scene_model",HERE/"scene-model.py")
model=importlib.util.module_from_spec(spec);spec.loader.exec_module(model)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets",type=Path,default=REPO/"assets/templates/sc520-card-recognition/scene-v2")
    parser.add_argument("--report",type=Path,required=True)
    args=parser.parse_args()
    if args.report.exists():parser.error("refusing to overwrite an existing report")
    checks=[]
    def check(name,value):
        checks.append({"name":name,"passed":bool(value)})
    for name in ("scene-v1","scene-v2"):
        folder=args.assets if name=="scene-v2" else args.assets.parent/name
        manifest=json.loads((folder/"manifest.json").read_text(encoding="utf-8"))
        for entry in manifest["outputs"]:
            path=folder/entry["path"]
            check(f"{name} sha256 {entry['path']}",path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest().upper()==entry["sha256"])
    manifest=json.loads((args.assets/"manifest.json").read_text(encoding="utf-8"))
    for entry in manifest["scripts"]+manifest["sources"]:
        check("input sha256 "+entry["path"],hashlib.sha256(Path(entry["path"]).read_bytes()).hexdigest().upper()==entry["sha256"])
    fixtures=json.loads((args.assets/"fixtures.json").read_text(encoding="utf-8"))
    training=json.loads((args.assets/"training.json").read_text(encoding="utf-8"))
    train_sizes={c["size_bp"] for item in training for c in item["candidates"]}
    eval_sizes={int(r["prefix"].split("_")[-2]) for r in fixtures if r["category"]=="card"}
    check("template/evaluation sizes are disjoint",not train_sizes & eval_sizes)
    check("all declared required truths hold",all(r["truth_satisfied"] for r in fixtures if r["required"]))
    check("pressure failures remain recorded",any(not r["truth_satisfied"] for r in fixtures if not r["required"]))
    check("system cases cover 14 known identities",{r["truth_item"] for r in fixtures if r["system_default"] and r["truth_item"]}==set(range(1,15)))
    words=np.loadtxt(args.assets/"templates.mem",dtype=np.uint16,converters=lambda x:int(x,16)).reshape(32,32)
    check("packed ROM fits 15 bits",int(words.max())<32768)
    for ci,item in enumerate(training):
        for variant in range(3):
            fname=f"card_{item['item']}_{item['name']}_v{variant}.mem"
            bits=np.loadtxt(args.assets/"normalized"/fname,dtype=np.uint8).reshape(32,32)
            check("packed ROM bit ordering "+fname,np.array_equal(bits,(words>>(ci*3+variant))&1))
    # Geometry is constructed directly: exact areas and pixel bounds are known
    # without calling the fixture generator or looking at RTL implementation.
    for width,expected in ((3,False),(4,True)):
        frame=np.full((60,120,3),64,dtype=np.uint8);frame[20:23,40:40+width]=(220,40,40)
        result=model.analyze(frame)
        check(f"occupancy area {3*width}",result["present"]==expected and result["scene_count"]==3*width)
    frame=np.full((60,120,3),64,dtype=np.uint8);frame[20:24,0:4]=(220,40,40)
    result=model.analyze(frame)
    check("edge is healthy unknown representation",result["present"] and result["edge_contact"] and not result["mask"].any() and np.all(result["replay_rgb"]==255))
    frame=np.full((60,120,3),16,dtype=np.uint8);frame[30:]=240
    result=model.analyze(frame)
    check("even border takes lower median",result["background_rgb"]==[24,24,24])
    check("uncertain border cannot assert empty",result["present"] and not result["background_qualified"] and not result["mask"].any())
    mask=np.zeros((60,120),dtype=bool);mask[19:21,40:44]=1
    normalized=model.normalize(mask)
    expected=np.zeros((32,32),dtype=bool);expected[11:21,6:26]=1
    check("inclusive 4x2 bbox aspect ratio",np.array_equal(normalized,expected))
    translated=np.zeros_like(mask);translated[39:41,90:94]=1
    check("integer translation invariance",np.array_equal(model.normalize(translated),expected))
    templates=np.zeros((5,3,32,32),dtype=bool)
    for ci in range(5):templates[ci,:,6:26,6:10+ci*4]=1
    query=templates[2,0]
    prediction=model.classify(query,templates)
    check("margin excludes same-class duplicate templates",prediction["item"]==12 and prediction["best"]==0 and prediction["second"]==80)
    result={"created_at":datetime.now(timezone(timedelta(hours=8))).isoformat(),"command":sys.argv,
        "checks":len(checks),"failed":sum(not c["passed"] for c in checks),"details":checks,
        "boundary":"Python geometry/evidence checks only; no RTL, camera or hardware validation."}
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({k:v for k,v in result.items() if k!="details"},ensure_ascii=False))
    return int(result["failed"]>0)

if __name__=="__main__":raise SystemExit(main())

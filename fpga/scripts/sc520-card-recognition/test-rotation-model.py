"""Audit frozen rotation assets, geometric routing and exact refusal replays."""
from __future__ import annotations
import argparse
from datetime import datetime,timezone,timedelta
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
import numpy as np

HERE=Path(__file__).resolve().parent;REPO=HERE.parents[2]
spec=importlib.util.spec_from_file_location("rotation_model",HERE/"scene-rotation-model.py")
model=importlib.util.module_from_spec(spec);spec.loader.exec_module(model)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report",type=Path,required=True)
    args=parser.parse_args()
    if args.report.exists():parser.error("refusing overwrite")
    checks=[]
    def check(name,passed):checks.append({"name":name,"passed":bool(passed)})
    assets=REPO/"assets/templates/sc520-card-recognition/rotation-v1"
    refusals=REPO/"evidence/sc520-card-recognition/rotation-refusals-20261014"
    for name,folder in (("rotation-v1",assets),("refusals",refusals)):
        manifest=json.loads((folder/"manifest.json").read_text(encoding="utf-8"))
        for entry in manifest["outputs"]:
            path=folder/entry["path"];check(name+" hash "+entry["path"],path.exists() and sha(path)==entry["sha256"])
        for entry in manifest.get("scripts",[]):
            check(name+" source "+entry["path"],sha(Path(entry["path"]))==entry["sha256"])
            check(name+" snapshot "+entry["path"],sha(Path(entry["snapshot"]))==entry["sha256"])
        for entry in manifest.get("sources",[]):check(name+" artwork "+entry["path"],sha(Path(entry["path"]))==entry["sha256"])
    contract=json.loads((assets/"bank-contract.json").read_text())
    bank=model.read_bank(assets/"templates.mem")
    check("N256 fixed serial ROM",bank.shape==(5,256,20,20) and contract["depth"]==102400 and sha(assets/"templates.mem")==contract["templates_sha256"])
    words=np.loadtxt(assets/"templates.mem",dtype=np.uint8,converters=lambda x:int(x,16))
    for item in range(5):check(f"class {item+10} bit ordering",np.array_equal(bank[item].reshape(-1),(words>>item)&1))
    rows=json.loads((assets/"fixtures.json").read_text(encoding="utf-8"));by_prefix={r["prefix"]:r for r in rows}
    system=[]
    for line in (assets/"system-cases.txt").read_text().splitlines():
        prefix,item,present=line.split();r=by_prefix[prefix];system.append(r)
        check("system truth "+prefix,r["system_default"] and int(item)==r["truth_item"] and bool(int(present))==r["truth_present"] and r["truth_satisfied"])
    check("system covers all 14 item IDs",{r["truth_item"] for r in system if r["truth_item"]}==set(range(1,15)))
    check("system count is fixed 69",len(system)==69)
    business=dict(line.split() for line in (assets/"business-cases.txt").read_text().splitlines())
    check("business names",set(business)=={"empty","apple","unknown"})
    check("business empty",by_prefix[business["empty"]]["expected"]["item"]==0 and not by_prefix[business["empty"]]["expected"]["present"])
    check("business apple",by_prefix[business["apple"]]["expected"]["item"]==10)
    check("business unknown remains present",by_prefix[business["unknown"]]["expected"]["item"]==0 and by_prefix[business["unknown"]]["expected"]["present"])
    dense=json.loads((assets/"angle-evaluation.json").read_text())["rows"]
    check("4320 intermediate angles retain 28 rejects",len(dense)==4320 and sum(r["truth_satisfied"] for r in dense)==4292)
    check("no cross-class error in intermediate angles",all(r["item"] in (0,r["truth_item"]) for r in dense))
    check("no true-card simple shape hit",all(r["shape"]["shape_bits"]==0 for r in dense))
    check("MAX40 still enforced",all(r["item"]==0 for r in dense if r["best"]>40))
    exact=json.loads((refusals/"fixtures.json").read_text())
    check("28 physical refusals exactly reproduce distances",len(exact)==28 and all(r["same_distances_as_dense"] and r["expected"]["item"]==0 and r["expected"]["present"] for r in exact))
    for r in exact:
        original=r["dense_original"]
        check("refusal phase "+r["prefix"],r["local_phase"]==[original["phase_x"],original["phase_y"]])
    legacy=json.loads((assets/"legacy-joint-comparison.json").read_text())
    check("legacy complete joint truth",all(r["truth_satisfied"] for r in legacy if r["required"]))
    roc=json.loads((assets/"roc.json").read_text())
    check("raw circles overlap card bank",len(roc[0]["raw_false_accepts"])==30)
    check("geometric gate rejects all raw negative overlaps",all(not r["guarded_false_accepts"] for r in roc))
    before=[r for r in rows if r["category"]=="tone_stress"]
    after=[r for r in rows if r["category"]=="tone_joint"]
    check("dim source failures remain",len(before)==5 and all(r["expected"]["item"]==0 and r["expected"]["present"] for r in before))
    check("unit-WB tone joint five-card pass",len(after)==5 and all(r["truth_satisfied"] for r in after))
    # Verify the actual tone RTL knots/rounding used by the independent model.
    rtl=REPO/"fpga/custom_project/sc520-pixel14/overlay/pixel14_color_pipeline.v"
    text=rtl.read_text();tone_body=text.split("function [7:0] tone07;",1)[1].split("endfunction",1)[0]
    entries=[tuple(map(int,m)) for m in re.findall(r"(?:\d+|default):begin base=(\d+);delta=(\d+);end",tone_body)]
    if not entries:
        # The imaging task replaces constant products with equivalent shifts
        # to avoid DSP inference. Parse only this narrow arithmetic grammar.
        for base,expression in re.findall(r"(?:\d+|default):begin base=(\d+);interpolation=([^;]+);end",tone_body):
            coefficient=0
            for term in expression.replace("(","").replace(")","").split("+"):
                match=re.fullmatch(r"nibble(?:<<(\d+))?",term.strip())
                if not match:raise ValueError("unrecognized tone interpolation expression")
                coefficient+=1<<int(match.group(1) or 0)
            entries.append((int(base),coefficient))
    if len(entries)!=16:raise ValueError("tone parser must see all sixteen explicit segments")
    expected=[]
    for v in range(256):
        base,delta=entries[v>>4];expected.append(255 if v==255 else base+((delta*(v&15)+8)>>4))
    check("all 256 tone points match actual RTL",np.array_equal(model.tone07(np.arange(256,dtype=np.uint8)),np.asarray(expected,dtype=np.uint8)))
    check("paper white 165 maps to188",int(model.tone07(np.array(165,dtype=np.uint8)))==188)
    result={"created_at":datetime.now(timezone(timedelta(hours=8))).isoformat(),"command":sys.argv,
        "checks":len(checks),"failed":sum(not c["passed"] for c in checks),"details":checks,
        "tone_rtl_path":str(rtl),"tone_rtl_sha256":sha(rtl),
        "boundary":"Software/evidence checks. No new RTL, timing, camera or board qualification is claimed."}
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({k:v for k,v in result.items() if k not in ("details",)},ensure_ascii=False))
    return int(result["failed"]>0)

if __name__=="__main__":raise SystemExit(main())

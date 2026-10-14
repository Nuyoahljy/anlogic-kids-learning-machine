"""Compare rotated template banks against unseen intermediate-angle renderings.

Templates rotate the original print first, then resize. Evaluation resizes the
physical card first, then rotates. No held-out image enters template selection.
"""
from __future__ import annotations
import argparse
from datetime import datetime,timezone,timedelta
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[2]
spec=importlib.util.spec_from_file_location("scene_model",HERE/"scene-model.py")
model=importlib.util.module_from_spec(spec);spec.loader.exec_module(model)
ITEMS=((10,"apple"),(11,"banana"),(12,"car"),(13,"star"),(14,"umbrella"))
TRAIN_SIZES=(48,64,80,96)
EVAL_SIZES=(51,67,83)

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def mask_of(image,px,py):
    rgb=np.asarray(image)[py::2,px::2]
    return model.normalize(model.despeckle(model.threshold(rgb)))[6:26,6:26]

def training_bank(images,step,variants,budget=None,dual_order=False):
    bank=[];info=[]
    for item,name in ITEMS:
        selected_masks=[];selection=[];global_pool=[];global_metadata=[]
        for angle in range(0,360,step):
            rotated=images[item].rotate(angle,Image.Resampling.BICUBIC,expand=True,fillcolor="white")
            pool=[];metadata=[]
            for size in TRAIN_SIZES:
                width=round(rotated.width*size/images[item].width)
                height=round(rotated.height*size/images[item].height)
                methods=[("rotate_then_resize",rotated.resize((width,height),Image.Resampling.LANCZOS))]
                if dual_order:
                    methods.append(("resize_then_rotate",images[item].resize((size,size),Image.Resampling.LANCZOS).rotate(angle,Image.Resampling.BICUBIC,expand=True,fillcolor="white")))
                for method,resized in methods:
                    for py in range(2):
                        for px in range(2):
                            pool.append(mask_of(resized,px,py));metadata.append({"angle":angle,"size_bp":size,"phase_x":px,"phase_y":py,"method":method})
            pool=np.asarray(pool);ds=np.count_nonzero(pool[:,None]!=pool[None,:],axis=(2,3))
            picked=[int(np.argmin(ds.sum(0)))]
            for _ in range(variants-1):picked.append(int(np.argmax(ds[:,picked].min(1))))
            selected_masks.extend(pool[picked]);selection.append({"angle":angle,"selected":[metadata[p] for p in picked]})
            global_pool.extend(pool);global_metadata.extend(metadata)
        extra=[]
        if budget is not None:
            if len(selected_masks)>budget:raise ValueError("base bank exceeds budget")
            packed_pool=np.packbits(np.asarray(global_pool).reshape(len(global_pool),400),axis=1)
            packed_selected=np.packbits(np.asarray(selected_masks).reshape(len(selected_masks),400),axis=1)
            nearest=np.empty(len(global_pool),dtype=np.int32)
            for start in range(0,len(global_pool),128):
                nearest[start:start+128]=np.bitwise_count(packed_pool[start:start+128,None,:]^packed_selected[None,:,:]).sum(axis=2).min(axis=1)
            while len(selected_masks)<budget:
                pick=int(np.argmax(nearest));selected_masks.append(global_pool[pick]);extra.append(global_metadata[pick])
                nearest=np.minimum(nearest,np.bitwise_count(packed_pool^packed_pool[pick]).sum(axis=1))
        bank.append(selected_masks);info.append({"item":item,"name":name,"selection":selection,"extra_training_farthest_first":extra})
    return np.asarray(bank),info

def query_masks(images,angles,sizes=EVAL_SIZES):
    masks=[];metadata=[]
    for item,name in ITEMS:
        for size in sizes:
            card=images[item].resize((size,size),Image.Resampling.LANCZOS)
            for angle in angles:
                rotated=card.rotate(angle,Image.Resampling.BICUBIC,expand=True,fillcolor="white")
                for py in range(2):
                    for px in range(2):
                        masks.append(mask_of(rotated,px,py))
                        metadata.append({"truth_item":item,"size_bp":size,"angle":float(angle),"phase_x":px,"phase_y":py})
    return np.asarray(masks),metadata

def classify_many(masks,bank,metadata):
    packed=np.packbits(bank.reshape(5,bank.shape[1],400),axis=-1)
    queries=np.packbits(masks.reshape(len(masks),400),axis=-1)
    outputs=[]
    for start in range(0,len(masks),64):
        distances=np.bitwise_count(queries[start:start+64,None,None,:]^packed[None,...]).sum(axis=-1).min(axis=-1)
        for offset,ds in enumerate(distances):
            idx=start+offset;order=np.argsort(ds,kind="stable");best=int(ds[order[0]]);second=int(ds[order[1]])
            fg=int(masks[idx].sum());item=int(order[0]+10) if 16<=fg<=850 and best<=40 and second-best>=24 else 0
            outputs.append({**metadata[idx],"item":item,"best":best,"second":second,"foreground":fg,
                "distances":ds.astype(int).tolist(),"truth_satisfied":item==metadata[idx]["truth_item"]})
    per_class={}
    for item,name in ITEMS:
        subset=[r for r in outputs if r["truth_item"]==item]
        per_class[name]={"count":len(subset),"passed":sum(r["truth_satisfied"] for r in subset),
            "rejected":sum(r["item"]==0 for r in subset),"misclassified":sum(r["item"] not in (0,item) for r in subset),
            "maximum_best":max(r["best"] for r in subset),"minimum_margin":min(r["second"]-r["best"] for r in subset),
            "worst_cases":sorted(subset,key=lambda r:(r["best"],-(r["second"]-r["best"])),reverse=True)[:4]}
    return outputs,per_class

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--steps",type=int,nargs="+",default=[20,15,10,5])
    parser.add_argument("--variants",type=int,nargs="+",default=[2,3])
    parser.add_argument("--budget",type=int)
    parser.add_argument("--dual-order",action="store_true")
    args=parser.parse_args()
    if args.output.exists():parser.error("refusing overwrite")
    args.output.mkdir(parents=True)
    (args.output/"inputs").mkdir()
    for source_path in (Path(__file__),HERE/"scene-model.py"):
        (args.output/"inputs"/source_path.name).write_bytes(source_path.read_bytes())
    source=REPO/"assets/templates/sc520-card-recognition/prep-v1-max40/rendered"
    images={item:Image.open(source/f"card_{item}_{name}_256.png").convert("RGB") for item,name in ITEMS}
    summaries=[]
    for step in args.steps:
        masks,metadata=query_masks(images,np.arange(step/2,360,step))
        for variants in args.variants:
            bank,selection=training_bank(images,step,variants,args.budget,args.dual_order)
            rows,classes=classify_many(masks,bank,metadata)
            summary={"angle_step":step,"variants_per_angle":variants,"variants_per_class":bank.shape[1],
                "bits":int(bank.size),"dual_order":args.dual_order,"count":len(rows),"passed":sum(r["truth_satisfied"] for r in rows),"classes":classes}
            stem=f"step{step}-variants{variants}"
            (args.output/f"{stem}.json").write_text(json.dumps({"summary":summary,"selection":selection,"rows":rows},indent=2)+"\n",encoding="utf-8")
            summaries.append(summary)
            print(json.dumps({k:v for k,v in summary.items() if k!="classes"}),flush=True)
    (args.output/"summary.json").write_text(json.dumps(summaries,indent=2)+"\n",encoding="utf-8")
    manifest={"created_at":datetime.now(timezone(timedelta(hours=8))).isoformat(),"command":sys.argv,
        "sources":[{"path":str(source/f"card_{item}_{name}_256.png"),"sha256":sha(source/f"card_{item}_{name}_256.png")} for item,name in ITEMS],
        "scripts":[{"path":str(p),"snapshot":str(args.output/"inputs"/p.name),"sha256":sha(p)} for p in (Path(__file__),HERE/"scene-model.py")],
        "train_sizes":TRAIN_SIZES,"evaluation_sizes":EVAL_SIZES,
        "boundary":"Intermediate angles are disjoint from template angles; synthetic development data, not camera validation.",
        "outputs":[{"path":str(p.relative_to(args.output)),"sha256":sha(p)} for p in args.output.rglob("*") if p.is_file()]}
    (args.output/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    return 0

if __name__=="__main__":raise SystemExit(main())

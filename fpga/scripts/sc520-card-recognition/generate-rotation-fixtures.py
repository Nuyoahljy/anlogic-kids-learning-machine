"""Freeze the selected rotation bank and joint-recognition evidence, preserving failures."""
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

HERE=Path(__file__).resolve().parent;REPO=HERE.parents[2]
def load(name,filename):
    spec=importlib.util.spec_from_file_location(name,HERE/filename);mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod
model=load("rotation_model","scene-rotation-model.py")
experiment=load("rotation_experiment","experiment-scene-rotation.py")
fixtures_v2=load("fixtures_v2","generate-scene-fixtures.py")
ITEMS=experiment.ITEMS
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest().upper()
def save(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
def bits_sha(a):return hashlib.sha256(np.asarray(a,dtype=np.uint8).tobytes()).hexdigest().upper()

def rebuild_bank(images,selection):
    bank=[]
    for entry in selection:
        source=images[entry["item"]];masks=[]
        records=[v for angle in entry["selection"] for v in angle["selected"]]+entry["extra_training_farthest_first"]
        for v in records:
            size=v["size_bp"];angle=v["angle"]
            if v["method"]=="resize_then_rotate":
                image=source.resize((size,size),Image.Resampling.LANCZOS).rotate(angle,Image.Resampling.BICUBIC,expand=True,fillcolor="white")
            else:
                image=source.rotate(angle,Image.Resampling.BICUBIC,expand=True,fillcolor="white")
                image=image.resize((round(image.width*size/256),round(image.height*size/256)),Image.Resampling.LANCZOS)
            masks.append(experiment.mask_of(image,v["phase_x"],v["phase_y"]))
        bank.append(masks)
    return np.asarray(bank,dtype=bool)

def physical_frame(source,angle,size,bg,position=1,phase=0,soft_edge=False):
    card=source.resize((size,size),Image.Resampling.LANCZOS).convert("RGBA")
    rotated=card.rotate(angle,Image.Resampling.BICUBIC,expand=True,fillcolor=(255,255,255,0))
    left=(46,160-rotated.width//2,274-rotated.width)[position]
    top=(34,90-rotated.height//2,146-rotated.height)[position]
    left=left//2*2+(phase&1);top=top//2*2+(phase>>1)
    alpha=rotated.getchannel("A")
    if not soft_edge:alpha=alpha.point(lambda v:255 if v>=128 else 0)
    image=Image.fromarray(fixtures_v2.background(bg));image.paste(rotated.convert("RGB"),(left,top),alpha)
    return np.asarray(image).copy(),{"angle":float(angle),"size_bp":size,"background":bg,"left":left,"top":top,
        "phase":phase,"soft_paper_edge":soft_edge,"paper_bbox_size":[rotated.width,rotated.height]}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,default=REPO/"assets/templates/sc520-card-recognition/rotation-v1")
    args=parser.parse_args();out=args.output.resolve()
    if out.exists():parser.error("refusing overwrite")
    out.mkdir(parents=True);(out/"vectors").mkdir();(out/"inputs").mkdir()
    source=REPO/"assets/templates/sc520-card-recognition/prep-v1-max40/rendered"
    images={i:Image.open(source/f"card_{i}_{n}_256.png").convert("RGB") for i,n in ITEMS}
    design=REPO/"evidence/sc520-card-recognition/rotation-design-dense-20261014/step5-variants2.json"
    selected=json.loads(design.read_text(encoding="utf-8"));bank=rebuild_bank(images,selected["selection"])
    words=np.zeros((256,400),dtype=np.uint8)
    for ci in range(5):words|=bank[ci].reshape(256,400).astype(np.uint8)<<ci
    (out/"templates.mem").write_text("".join(f"{int(w):02x}\n" for w in words.flat),encoding="ascii")
    if not np.array_equal(model.read_bank(out/"templates.mem"),bank):raise AssertionError("ROM round trip")
    save(out/"training.json",selected["selection"])
    save(out/"bank-contract.json",{"variants_per_class":256,"word_bits":5,"depth":102400,"active_side":20,
        "address":"variant*400+y*20+x","bit_order":"bit0..4=item10..14","normalized_source":"mask[6:26,6:26]",
        "max_distance":40,"min_margin":24,"angle_step":5,"translation_search":False,
        "templates_sha256":sha(out/"templates.mem"),"selected_design_sha256":sha(design)})
    # Reproduce all 4320 intermediate-angle model rows and retain the 28 rejects.
    masks,metadata=experiment.query_masks(images,np.arange(2.5,360,5))
    dense,classes=experiment.classify_many(masks,bank,metadata)
    for actual,old in zip(dense,selected["rows"]):
        if actual["distances"]!=old["distances"]:raise AssertionError("selected bank reconstruction changed distances")
    min_shape={i:1024 for i,_ in ITEMS}
    for mask,row in zip(masks,dense):
        full=np.zeros((32,32),dtype=bool);full[6:26,6:26]=mask
        shape=model.shape_classify(full);row["shape"]=shape
        min_shape[row["truth_item"]]=min(min_shape[row["truth_item"]],min(shape["distances"]))
        row["joint_card_item"]=row["item"] if shape["shape_bits"]==0 else 0
    save(out/"angle-evaluation.json",{"classes":classes,"minimum_simple_shape_distance":min_shape,"rows":dense})
    # Legacy corpus is rechecked with complete joint arbitration, correcting
    # scene-v2's per-path truth_satisfied omission without editing that evidence.
    old_dir=REPO/"assets/templates/sc520-card-recognition/scene-v2"
    old_rows=json.loads((old_dir/"fixtures.json").read_text(encoding="utf-8"));joint=[];roc=[]
    for old in old_rows:
        frame=np.asarray(Image.open(old_dir/"vectors"/f"{old['prefix']}.png").convert("RGB"));r=model.recognize(frame,bank)
        matched=r["present"]==old["truth_present"] and r["item"]==old["truth_item"]
        joint.append({"prefix":old["prefix"],"category":old["category"],"required":old["required"],
            "truth_item":old["truth_item"],"old_per_path_truth_satisfied":old["truth_satisfied"],
            "paper_route":r["paper_route"],"card_raw":r["card_raw"],"shape":r["shape"],
            "block_raw":r["block_raw"],"block_item":r["block_item"],"item":r["item"],"truth_satisfied":bool(matched)})
    for maximum in (40,44,48):
        positive_pass=sum(r["best"]<=maximum and r["second"]-r["best"]>=24 and r["shape"]["shape_bits"]==0 for r in dense)
        negatives=[r for r in joint if r["required"] and not r["category"].startswith("card")]
        raw_accept=[r["prefix"] for r in negatives if r["card_raw"]["best"]<=maximum and r["card_raw"]["second"]-r["card_raw"]["best"]>=24 and r["card_raw"]["foreground"]>=16]
        guarded_accept=[r["prefix"] for r in negatives if r["prefix"] in raw_accept and r["shape"]["shape_bits"]==0]
        roc.append({"max_distance":maximum,"positive_pass":positive_pass,"positive_count":len(dense),
            "negative_count":len(negatives),"raw_false_accepts":raw_accept,"guarded_false_accepts":guarded_accept})
    save(out/"legacy-joint-comparison.json",joint);save(out/"roc.json",roc)
    cases=[]
    def add(name,category,item,present,frame,recipe=None,system=False,refusal=False):
        cases.append({"name":name,"category":category,"truth_item":item,"truth_present":present,
            "frame":frame,"recipe":recipe or {},"system_default":system,"expected_refusal_probe":refusal})
    for bg in ("dark","white","red"):
        add(f"empty_{bg}","empty",0,False,fixtures_v2.background(bg),system=True)
    angles=(0,90,180,270,2.5,87.5,177.5,267.5)
    for item,name in ITEMS:
        for ai,angle in enumerate(angles):
            bg=("white","dark","wood")[ai%3];position=ai%3
            frame,recipe=physical_frame(images[item],angle,75,bg,position,ai%4)
            add(f"card_{item}_angle_{str(angle).replace('.','p')}","rotation_card",item,True,frame,recipe,True)
        # Added placements/sizes are different from the dense model sweep.
        for size in (53,69,77):
            for angle in (17.5,62.5,152.5,242.5,332.5):
                frame,recipe=physical_frame(images[item],angle,size,"dark",1,1)
                add(f"card_{item}_size_{size}_angle_{str(angle).replace('.','p')}","rotation_extra",item,True,frame,recipe)
        frame,recipe=physical_frame(images[item],32.5,75,"dark",1,1,soft_edge=True)
        add(f"card_{item}_soft_paper_edge","paper_edge_stress",item,True,frame,recipe)
    for old in old_rows:
        if old["system_default"] and not old["category"].startswith("card") and old["category"]!="empty":
            frame=np.asarray(Image.open(old_dir/"vectors"/f"{old['prefix']}.png").convert("RGB"))
            add("legacy_"+old["prefix"],old["category"],old["truth_item"],old["truth_present"],frame,{"legacy_prefix":old["prefix"]},True)
    for old in old_rows:
        if old["prefix"].endswith("unknown_circle_dark"):
            frame=np.asarray(Image.open(old_dir/"vectors"/f"{old['prefix']}.png").convert("RGB"))
            add("unknown_gray_circle","unknown",0,True,frame,system=True)
        if old["category"]=="photometric_stress":
            frame=np.asarray(Image.open(old_dir/"vectors"/f"{old['prefix']}.png").convert("RGB"))
            add(f"card_{old['truth_item']}_gain65_before","tone_stress",old["truth_item"],True,frame)
            add(f"card_{old['truth_item']}_gain65_after","tone_joint",old["truth_item"],True,model.tone07(frame),{"tone07":True,"wb_gain":256},True)
    for row in dense:
        if not row["truth_satisfied"]:
            frame,recipe=physical_frame(images[row["truth_item"]],row["angle"],row["size_bp"],"white",1,row["phase_x"]+2*row["phase_y"])
            add(f"refusal_{row['truth_item']}_{row['size_bp']}_{str(row['angle']).replace('.','p')}_{row['phase_x']}{row['phase_y']}",
                "dense_refusal_replay",row["truth_item"],True,frame,{**recipe,"dense_original":row},refusal=True)
    records=[]
    for index,case in enumerate(cases):
        frame=case.pop("frame");prefix=f"r{index:03d}_{case.pop('name')}";r=model.recognize(frame,bank)
        record={"prefix":prefix,**case,"expected":{k:v for k,v in r.items() if not isinstance(v,np.ndarray)},
            "truth_satisfied":bool(r["present"]==case["truth_present"] and r["item"]==case["truth_item"]),
            "input_rgb_sha256":bits_sha(frame),"mask_sha256":bits_sha(r["mask"]),"replay_rgb_sha256":bits_sha(r["replay_rgb"])}
        records.append(record);folder=out/"vectors";Image.fromarray(frame).save(folder/f"{prefix}.png")
        # All system/default/refusal inputs have full raster RGB and independent
        # expected scene outputs, suitable for both pixel and system testbenches.
        if case["system_default"] or case["expected_refusal_probe"]:
            fixtures_v2.rgbmem(folder/f"{prefix}.rgb.mem",frame)
            fixtures_v2.rgbmem(folder/f"{prefix}.replay.mem",r["replay_rgb"])
            fixtures_v2.bitmem(folder/f"{prefix}.mask.mem",r["mask"])
    save(out/"fixtures.json",records)
    (out/"system-cases.txt").write_text("".join(f"{r['prefix']} {r['truth_item']} {int(r['truth_present'])}\n" for r in records if r["system_default"]),encoding="ascii")
    (out/"refusal-cases.txt").write_text("".join(f"{r['prefix']} {r['expected']['item']} {int(r['expected']['present'])}\n" for r in records if r["expected_refusal_probe"]),encoding="ascii")
    business={"empty":next(r["prefix"] for r in records if r["prefix"].endswith("empty_dark")),
        "apple":next(r["prefix"] for r in records if r["prefix"].endswith("card_10_angle_0")),
        "unknown":next(r["prefix"] for r in records if r["prefix"].endswith("unknown_gray_circle"))}
    (out/"business-cases.txt").write_text("".join(f"{key} {value}\n" for key,value in business.items()),encoding="ascii")
    summary={"variants_per_class":256,"templates_sha256":sha(out/"templates.mem"),"dense_count":len(dense),
        "dense_passed":sum(r["truth_satisfied"] for r in dense),"classes":classes,"minimum_simple_shape_distance":min_shape,
        "legacy_joint_required_count":sum(r["required"] for r in joint),
        "legacy_joint_required_failed":[r["prefix"] for r in joint if r["required"] and not r["truth_satisfied"]],
        "system_count":sum(r["system_default"] for r in records),
        "system_failures":[r["prefix"] for r in records if r["system_default"] and not r["truth_satisfied"]],
        "physical_frame_failures":[r["prefix"] for r in records if not r["truth_satisfied"]],"roc":roc}
    save(out/"summary.json",summary)
    scripts=[Path(__file__),HERE/"scene-rotation-model.py",HERE/"scene-model.py",HERE/"experiment-scene-rotation.py",HERE/"generate-scene-fixtures.py"]
    for path in scripts:(out/"inputs"/path.name).write_bytes(path.read_bytes())
    (out/"README.md").write_text("# Rotation-v1 joint candidate\n\n"
        "五张工程配套原卡的0–360°平面角度搜索候选。不是任意苹果照片分类器。用户报告当前五卡均不能识别；本文件只记录合成模型，不能代替摄像头复测。\n\n"
        "N=256/类；ROM102400行，每行5bit，variant*400+y*20+x，bit0..4=item10..14。有效20×20来自32×32的6..25；MAX40/MARGIN24，不用±1平移。5°训练角，两基础变体再按训练残差补齐256；验证中间2.5°偏移和未用于训练的51/67/83尺寸，原28拒识逐项保存。\n\n"
        "单独旋转bank会把圆块误作苹果，禁止脱离对称几何分流使用：卡片要求simple_shape_bits==0；块要求对应shape_ok，且paper_route抑制RGB重放。解析简单形状距离≤20，真实旋转卡最小35，负例圆形命中形状。paper_count为filtered_scene且非原始glyph阈值的点；occupied且glyph_count≥12且4*paper_count>scene_count时只走卡片。此规则不按待回答题目或卡片得分优先选类别。\n\n"
        "旧scene-v2的truth_satisfied仅分路验收，漏了138个联立冲突/误判。本目录完整重算旧帧与最终item并保留旧证据，不修改真值。所有模型/参考一致性仍不同于实物准确率。\n\n"
        "physical_frame采用先缩放真实卡面再旋转，硬边Alpha代表理想点采样纸边；另保留软Alpha纸边压力，不能宣称真实模糊边缘已解决。system-cases固定配方选取；refusal-cases按实际模型item核RTL，而fixtures中的物理truth仍是原卡类，不冒充识别成功。\n\n"
        "gain0.65前后使用单位白平衡与tone07整数曲线，来自imaging候选；先抑制纸面块误路再做几何分流。透视/任意背景/硬件性能不在本模型已验证范围。\n",encoding="utf-8")
    save(out/"manifest.json",{"created_at":datetime.now(timezone(timedelta(hours=8))).isoformat(),"command":sys.argv,
        "sources":[{"path":str(source/f"card_{i}_{n}_256.png"),"sha256":sha(source/f"card_{i}_{n}_256.png")} for i,n in ITEMS],
        "scripts":[{"path":str(p),"snapshot":str(out/"inputs"/p.name),"sha256":sha(p)} for p in scripts],
        "selected_design":{"path":str(design),"sha256":sha(design)},
        "bank":{"variants_per_class":256,"word_bits":5,"depth":102400,"templates_sha256":sha(out/"templates.mem")},
        "outputs":[{"path":str(p.relative_to(out)),"sha256":sha(p)} for p in sorted(out.rglob("*")) if p.is_file()]})
    print(json.dumps({k:v for k,v in summary.items() if k not in ("classes","roc")},ensure_ascii=False),flush=True)
    return 0

if __name__=="__main__":raise SystemExit(main())

"""Generate scene-v2 development fixtures; retain truth and never overwrite evidence."""
from __future__ import annotations
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
spec = importlib.util.spec_from_file_location("scene_model", HERE / "scene-model.py")
model = importlib.util.module_from_spec(spec)
spec.loader.exec_module(model)
ITEMS = [(10, "apple"), (11, "banana"), (12, "car"), (13, "star"), (14, "umbrella")]
TRAIN_SIZES = (48, 64, 80, 96)
EVAL_SIZES = (51, 59, 67, 75, 83, 91, 99, 103)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def array_sha(array):
    return hashlib.sha256(np.asarray(array, dtype=np.uint8).tobytes()).hexdigest().upper()

def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

def rgbmem(path, rgb):
    path.write_text("".join(f"{int(r):02x}{int(g):02x}{int(b):02x}\n" for r,g,b in rgb.reshape(-1,3)), encoding="ascii")

def bitmem(path, bits):
    path.write_text("".join(f"{int(bit):x}\n" for bit in bits.flat), encoding="ascii")

def background(kind):
    y,x = np.mgrid[0:180,0:320]
    if kind == "wood":
        delta = ((x//7 + y//43)%5 - 2)*6
        return np.stack([105+delta,86+delta,66+delta],axis=-1).astype(np.uint8)
    colors = {"white":(255,255,255),"light":(210,210,210),"dark":(64,64,64),
              "black":(0,0,0),"red":(200,35,35),"blue":(30,70,200)}
    return np.full((180,320,3),colors[kind],dtype=np.uint8)

def card_frame(source,bg,size,left,top,*,gain=1.,shade=0,noise=False):
    image=Image.fromarray(background(bg))
    image.paste(source.resize((size,size),Image.Resampling.LANCZOS),(left,top))
    rgb=np.asarray(image).copy()
    if gain != 1.: rgb=np.clip(np.floor(rgb.astype(np.float64)*gain),0,255).astype(np.uint8)
    if shade: rgb[55:118,62:242]=np.maximum(rgb[55:118,62:242].astype(np.int16)-shade,0).astype(np.uint8)
    if noise:
        for x,y in ((55,43),(93,53),(257,71),(197,133),(81,119),(151,85)): rgb[y,x]=0
    return rgb

def build_templates(images):
    """Choose three training aliases, without consulting evaluation inputs."""
    templates,training=[],[]
    for item,name in ITEMS:
        candidates,entries=[],[]
        for size in TRAIN_SIZES:
            for py in range(2):
                for px in range(2):
                    frame=card_frame(images[item],"white",size,100+px,40+py)
                    result=model.analyze(model.sample_frame(frame))
                    candidates.append(result["mask"])
                    entries.append({"size_bp":size,"left":100+px,"top":40+py,
                        "rgb_sha256":array_sha(frame),"mask_sha256":array_sha(result["mask"])})
        candidates=np.asarray(candidates)
        distances=np.count_nonzero(candidates[:,None]!=candidates[None,:],axis=(2,3))
        selected=[int(np.argmin(distances.sum(axis=0)))]
        for _ in range(model.TEMPLATES_PER_CLASS-1):
            selected.append(int(np.argmax(distances[:,selected].min(axis=1))))
        templates.append(candidates[selected])
        training.append({"item":item,"name":name,"candidates":entries,"selected_indices":selected,
            "selection":"sum-distance medoid, then farthest-first; lowest index wins ties"})
    return np.asarray(templates),training

def trapezoid(source, direction):
    """Project a square to an 8%-inset trapezoid using inverse pixel mapping."""
    edge=source.width-1
    src=((0,0),(edge,0),(edge,edge),(0,edge))
    inset=edge*.08
    dst=((inset,0),(edge-inset,0),(edge,edge),(0,edge)) if direction=="top" else ((0,0),(edge,0),(edge-inset,edge),(inset,edge))
    matrix=[];values=[]
    for (x,y),(u,v) in zip(dst,src):
        matrix += [[x,y,1,0,0,0,-u*x,-u*y],[0,0,0,x,y,1,-v*x,-v*y]]
        values += [u,v]
    coeff=np.linalg.solve(np.asarray(matrix),np.asarray(values))
    return source.transform(source.size,Image.Transform.PERSPECTIVE,coeff,Image.Resampling.BICUBIC,fillcolor="white")

def fixtures(images):
    rows=[]
    def add(name,category,item,present,rgb,rtl=False,required=True):
        rows.append({"name":name,"category":category,"truth_item":item,"truth_present":present,
                     "frame":rgb,"rtl_default":rtl,"required":required})
    for bg in ("white","light","dark","black","wood","red","blue"):
        add(f"empty_{bg}","empty",0,False,background(bg),True)
        rgb=background(bg)
        for x,y in ((55,43),(93,53),(257,71),(197,133),(81,119)): rgb[y,x]=0
        add(f"empty_{bg}_noise","noise",0,False,rgb,bg in ("dark","wood"))
        rgb=background(bg)
        rgb[60:110,90:230]=np.maximum(rgb[60:110,90:230].astype(np.int16)-24,0)
        add(f"empty_{bg}_soft_shadow","shadow",0,False,rgb,bg in ("dark","wood"))
    for item,name in ITEMS:
        for bg in ("white","dark","wood"):
            for si,size in enumerate(EVAL_SIZES):
                for phase in range(4):
                    pos=(si+phase)%3
                    left=(46,160-size//2,274-size)[pos]
                    top=(34,90-size//2,146-size)[pos]
                    left=left//2*2+(phase&1); top=top//2*2+(phase>>1)
                    add(f"card_{item}_{bg}_{size}_{phase}","card",item,True,
                        card_frame(images[item],bg,size,left,top),
                        bg=="dark" and size in (51,75,103) and phase==0)
        for effect,kwargs in (("noise",{"noise":True}),("shadow",{"shade":24}),
                              ("gain90",{"gain":.9}),("gain65",{"gain":.65})):
            add(f"card_{item}_{effect}","photometric_stress" if effect=="gain65" else "card_perturbed",
                item,True,card_frame(images[item],"wood",75,123,53,**kwargs),
                effect in ("shadow","gain65"),effect!="gain65")
        for edge,left,top in (("left",12,56),("right",252,56),("top",134,2),("bottom",134,122)):
            add(f"card_{item}_cut_{edge}","edge",0,True,
                card_frame(images[item],"dark",56,left,top),item==10)
        for angle in (-15,-10,-5,0,5,10,15,90,180):
            rotated=images[item].rotate(angle,Image.Resampling.BICUBIC,expand=False,fillcolor="white")
            add(f"card_{item}_rotate_{angle:+d}".replace("+","p").replace("-","m"),
                "card_rotation_stress",item,True,card_frame(rotated,"dark",83,118,48),
                item==10 and angle in (-5,5,90),False)
        for direction in ("top","bottom"):
            add(f"card_{item}_trapezoid_{direction}","card_perspective_stress",item,True,
                card_frame(trapezoid(images[item],direction),"wood",83,118,48),item==10,False)
    colors=[("red",(215,61,60)),("yellow",(245,205,45)),("blue",(50,112,205))]
    for ci,(color,rgb) in enumerate(colors):
        for si,shape in enumerate(("circle","square","triangle")):
            for bg in ("white","dark","wood"):
                for size in (36,52,68):
                    frame=Image.fromarray(background(bg));d=ImageDraw.Draw(frame)
                    left,top=160-size//2,90-size//2
                    if shape=="circle":d.ellipse((left,top,left+size-1,top+size-1),fill=rgb)
                    elif shape=="square":d.rectangle((left,top,left+size-1,top+size-1),fill=rgb)
                    else:d.polygon(((160,top),(left,top+size-1),(left+size-1,top+size-1)),fill=rgb)
                    add(f"block_{color}_{shape}_{bg}_{size}","block",ci*3+si+1,True,np.asarray(frame).copy(),bg=="dark" and size==52)
    # Independently drawn negatives. Gray shapes cannot get a block-color label.
    for shape in ("circle","square","triangle","ring","cross","x","checker","two_squares","letter_h"):
        for bg in ("white","dark","wood"):
            frame=Image.fromarray(background(bg));d=ImageDraw.Draw(frame)
            d.rectangle((116,46,204,134),fill=(245,245,245));fill=(18,18,18)
            if shape=="circle":d.ellipse((132,64,187,117),fill=fill)
            elif shape=="square":d.rectangle((132,64,187,117),fill=fill)
            elif shape=="triangle":d.polygon(((160,62),(130,118),(190,118)),fill=fill)
            elif shape=="ring":
                d.ellipse((129,60,191,122),fill=fill);d.ellipse((144,75,176,107),fill=(245,245,245))
            elif shape=="cross":
                d.rectangle((152,59,168,122),fill=fill);d.rectangle((128,82,192,99),fill=fill)
            elif shape=="x":
                d.line((130,61,190,121),fill=fill,width=15);d.line((190,61,130,121),fill=fill,width=15)
            elif shape=="two_squares":
                d.rectangle((126,68,147,113),fill=fill);d.rectangle((174,68,195,113),fill=fill)
            elif shape=="letter_h":
                d.rectangle((130,60,143,122),fill=fill);d.rectangle((177,60,190,122),fill=fill)
                d.rectangle((140,84,180,99),fill=fill)
            else:
                for y in range(61,121,10):
                    for x in range(130,190,10):
                        if (x//10+y//10)%2:d.rectangle((x,y,x+9,y+9),fill=fill)
            add(f"unknown_{shape}_{bg}","unknown",0,True,np.asarray(frame).copy(),bg=="dark")
    # These are different synthetic apple drawings, not the supplied printed
    # artwork and not a substitute for the user's still-unseen phone picture.
    for variant in ("outline","striped"):
        art=Image.new("RGB",(256,256),"white");d=ImageDraw.Draw(art)
        d.polygon(((54,76),(90,56),(127,72),(166,50),(206,76),(210,126),(181,194),(146,213),(128,201),(100,216),(70,182),(46,124)),
                  fill=(218,45,35),outline=(20,20,20),width=6)
        d.polygon(((126,70),(140,27),(180,26),(157,53)),fill=(35,145,45))
        if variant=="outline":
            d.ellipse((80,92,177,178),fill="white");d.line((90,181,169,82),fill=(25,25,25),width=9)
        else:
            for x in range(60,205,20):d.rectangle((x,85,x+8,184),fill="white")
        add(f"different_apple_{variant}","unknown_card_art",0,True,card_frame(art,"dark",83,118,48),True)
    rgb=background("dark");rgb[5:175,0:40]=(200,35,35);rgb[5:175,280:320]=(30,70,200)
    add("outside_roi_interference","outside",0,False,rgb,True)
    for edge,bounds in (("left",(40,65,70,115)),("right",(250,65,280,115)),
                         ("top",(135,30,185,60)),("bottom",(135,120,185,150))):
        rgb=background("dark");x0,y0,x1,y1=bounds;rgb[y0:y1,x0:x1]=(200,35,35)
        add(f"block_touching_{edge}","edge",0,True,rgb,True)
    for name,colors2 in (("red_blue",((200,35,35),(30,70,200))),("light_dark",((230,230,230),(30,30,30)))):
        rgb=background("white");rgb[:,:160]=colors2[0];rgb[:,160:]=colors2[1]
        add(f"unqualified_border_{name}","background_unknown",0,True,rgb,True)
    return rows

def evaluate(frame,templates):
    result=model.analyze(model.sample_frame(frame))
    return result,model.classify(result["mask"],templates,result["present"]),model.block_classify(result["replay_rgb"],result["present"])

def legacy_audit(templates):
    folder=REPO/"assets/templates/sc520-card-recognition/scene-v1"
    previous=json.loads((folder/"fixtures.json").read_text(encoding="utf-8"))
    old_words=np.loadtxt(folder/"templates.mem",dtype=np.uint8,converters=lambda x:int(x,16)).reshape(32,32)
    old_templates=np.asarray([(old_words>>i)&1 for i in range(5)],dtype=bool)
    rows=[]
    for r in previous:
        frame=np.asarray(Image.open(folder/"vectors"/f"{r['prefix']}.png").convert("RGB"))
        old=model.analyze(model.sample_frame(frame),active_side=28,conservative_guards=False)
        old_card=model.classify(old["mask"],old_templates,old["present"])
        for key in ("distances","best","second","foreground","valid","item"):
            if old_card[key]!=r["card"][key]:raise AssertionError(f"legacy oracle changed: {r['prefix']} {key}")
        result,card,block=evaluate(frame,templates)
        matched=result["present"]==r["truth_present"] and (card["item"]==r["truth_item"] if r["category"]=="card" else card["item"]==0)
        if r["category"]=="block":matched &= block==r["truth_item"]
        rows.append({"prefix":r["prefix"],"category":r["category"],"truth_item":r["truth_item"],
            "old_truth_satisfied":r["truth_satisfied"],"old_best":old_card["best"],
            "new_truth_satisfied":bool(matched),"new_card":card,"new_block":block})
    return {"source_manifest_sha256":sha(folder/"manifest.json"),"source_fixtures_sha256":sha(folder/"fixtures.json"),
        "old_card_pass":sum(r["old_truth_satisfied"] for r in rows if r["category"]=="card"),
        "new_card_pass":sum(r["new_truth_satisfied"] for r in rows if r["category"]=="card"),"rows":rows}

def dense_sweep(images,templates):
    # Development sweep, not an untouched/photographic accuracy claim.
    rows=[]
    for item,_ in ITEMS:
        for size in range(48,108):
            resized=np.asarray(images[item].resize((size,size),Image.Resampling.LANCZOS))
            for py in range(2):
                for px in range(2):
                    mask=model.normalize(model.despeckle(model.threshold(resized[py::2,px::2])))
                    card=model.classify(mask,templates)
                    rows.append({"item":item,"size_bp":size,"phase_x":px,"phase_y":py,
                        "best":card["best"],"margin":card["second"]-card["best"],
                        "predicted_item":card["item"],"truth_satisfied":card["item"]==item})
    return {"count":len(rows),"passed":sum(r["truth_satisfied"] for r in rows),
        "worst_distance":max(r["best"] for r in rows),"minimum_margin":min(r["margin"] for r in rows),"rows":rows}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,default=REPO/"assets/templates/sc520-card-recognition/scene-v2")
    parser.add_argument("--probe",action="store_true",help="evaluate in memory; create no files")
    args=parser.parse_args();output=args.output.resolve()
    if not args.probe and output.exists():parser.error("refusing to overwrite an existing evidence/asset directory")
    source_dir=REPO/"assets/templates/sc520-card-recognition/prep-v1-max40/rendered"
    images,sources={},[]
    for item,name in ITEMS:
        path=source_dir/f"card_{item}_{name}_256.png"
        images[item]=Image.open(path).convert("RGB")
        sources.append({"path":str(path),"sha256":sha(path),"item":item})
    templates,training=build_templates(images);sweep=dense_sweep(images,templates);old=legacy_audit(templates)
    if not args.probe:
        output.mkdir(parents=True);(output/"vectors").mkdir();(output/"normalized").mkdir()
        words=np.zeros((32,32),dtype=np.uint16)
        for ci,(item,name) in enumerate(ITEMS):
            for variant in range(model.TEMPLATES_PER_CLASS):
                template=templates[ci,variant];words|=template.astype(np.uint16)<<(ci*model.TEMPLATES_PER_CLASS+variant)
                stem=output/"normalized"/f"card_{item}_{name}_v{variant}"
                bitmem(stem.with_suffix(".mem"),template)
                Image.fromarray(np.where(template,0,255).astype(np.uint8)).resize((256,256),Image.Resampling.NEAREST).save(stem.with_suffix(".png"))
        (output/"templates.mem").write_text("".join(f"{int(word):04x}\n" for word in words.flat),encoding="ascii")
    records=[]
    for index,row in enumerate(fixtures(images)):
        frame=row.pop("frame");prefix=f"{index:03d}_{row.pop('name')}"
        result,card,block=evaluate(frame,templates)
        matched=card["item"]==row["truth_item"] if row["category"].startswith("card") or row["category"]=="photometric_stress" else card["item"]==0
        if row["category"]=="block":matched &= block==row["truth_item"]
        if row["category"] in ("unknown","edge","background_unknown"):matched &= block==0
        # The system subset is chosen by fixed physical recipe, never by result.
        card_system={10:("dark",51,0),11:("wood",75,1),12:("white",103,0),13:("dark",75,0),14:("wood",99,3)}
        system_default=(row["category"]=="card" and any(prefix.endswith(f"card_{item}_{bg}_{size}_{phase}") for item,(bg,size,phase) in card_system.items()))
        if row["category"]=="block":
            item=row["truth_item"];ci=(item-1)//3;si=(item-1)%3
            system_default=prefix.endswith(f"block_{('red','yellow','blue')[ci]}_{('circle','square','triangle')[si]}_{('white','dark','wood')[si]}_{(36,52,68)[ci]}")
        system_default |= row["category"] in ("empty","outside","background_unknown","unknown_card_art")
        system_default |= prefix.endswith(("empty_wood_noise","empty_dark_soft_shadow","unknown_checker_dark","unknown_ring_white","block_touching_left","card_10_cut_right"))
        record={"index":index,"prefix":prefix,**row,"system_default":bool(system_default),
            "expected":{k:v for k,v in result.items() if not isinstance(v,np.ndarray)},"card":card,"block_item":block,
            "input_rgb_sha256":array_sha(frame),"mask_sha256":array_sha(result["mask"]),"replay_rgb_sha256":array_sha(result["replay_rgb"]),
            "truth_satisfied":bool(result["present"]==row["truth_present"] and matched)}
        records.append(record)
        if not args.probe:
            folder=output/"vectors";Image.fromarray(frame).save(folder/f"{prefix}.png")
            if row["rtl_default"] or system_default:
                rgbmem(folder/f"{prefix}.rgb.mem",frame);rgbmem(folder/f"{prefix}.replay.mem",result["replay_rgb"])
                bitmem(folder/f"{prefix}.mask.mem",result["mask"])
                Image.fromarray(np.where(result["scene"],0,255).astype(np.uint8)).save(folder/f"{prefix}.scene.png")
                Image.fromarray(np.where(result["mask"],0,255).astype(np.uint8)).save(folder/f"{prefix}.mask.png")
    groups={}
    for r in records:
        group=groups.setdefault(r["category"],{"count":0,"truth_satisfied":0})
        group["count"]+=1;group["truth_satisfied"]+=int(r["truth_satisfied"])
    failures=[{"prefix":r["prefix"],"category":r["category"],"required":r["required"],"present":r["expected"]["present"],
               "card":r["card"],"block":r["block_item"]} for r in records if not r["truth_satisfied"]]
    summary={"groups":groups,"rtl_default_count":sum(r["rtl_default"] for r in records),
        "required_failures":sum(r["required"] for r in failures),"failures":failures,
        "legacy_card_pass":[old["old_card_pass"],old["new_card_pass"],135],
        "dense_sweep":{k:v for k,v in sweep.items() if k!="rows"},
        "dense_sweep_failures":[r for r in sweep["rows"] if not r["truth_satisfied"]]}
    if not args.probe:
        save(output/"fixtures.json",records);save(output/"training.json",training);save(output/"legacy-comparison.json",old)
        save(output/"dense-sweep.json",sweep);save(output/"summary.json",summary)
        (output/"fixtures.txt").write_text("".join(
            f"{r['prefix']} {int(r['expected']['present'])} {r['expected']['scene_count']} {r['expected']['glyph_count']} "
            f"{int(r['card']['valid'])} {r['card']['item']} {r['card']['best']} {r['card']['second']} {r['card']['foreground']} {r['block_item']}\n"
            for r in records if r["rtl_default"]),encoding="ascii")
        (output/"system-cases.txt").write_text("".join(
            f"{r['prefix']} {r['truth_item']} {int(r['truth_present'])}\n" for r in records if r["system_default"]),encoding="ascii")
        (output/"README.md").write_text(
            "# Scene-v2 开发候选\n\n"
            "来源是五张已哈希的打印图稿，不是相机照片。scene-v1原件保留；legacy-comparison.json回放旧模型并逐字段核对原记录。\n\n"
            "320×180 bp输入，ROI为(40,30)起240×120，即可见960×480。采样(41+2x,31+2y)为120×60。边界每通道16档下中位数，档中心16b+8，L∞差≤48，四连通背景洪泛；原中心有效且3×3至少3点保留。存在门槛12点及至少3×3 bbox。边界相似点不足75%，或物体满足存在门槛且触边，保持present=1但卡片mask清零、积木重放白化；仍是健康未知。\n\n"
            "20格位于32×32的6..25；side=max(inclusive width,height)，x=floor((20*(2*xmin+width-side)+(2*(gx-6)+1)*side)/40)，负数或bbox外为0。每类3模板取最小Hamming，再在不同类间计算second/margin。ROM1024行×15bit，bit=class*3+variant。\n\n"
            "训练48/64/80/96 bp像素×4相位；选总距离最小，再两次选距已选集最远的训练项。评价51/59/67/75/83/91/99/103不参与模板选择；dense-sweep为开发期间48..107扫描，不是盲测。MAX40/MARGIN24数值保持，但有效面积从784降到400，允许错误比例提高，不能宣称和0109判别严格度相同。\n\n"
            "真值先于模型赋予，失败原样保存。gain65为曝光压力观测，不纳入可识别契约，未改其类别真值。所有输入存PNG；rtl_default另存RGB/replay/mask文本。模型一致不等于识别正确。\n\n"
            "system-cases.txt按绘图配方固定选择14类及空场/未知/边界代表，列为prefix truth_item truth_present；不依据模型结果筛选。旋转0/±5/±10/±15/90/180°及8%梯形是独立压力集，不承诺旋转透视鲁棒；两个不同苹果图是脚本另绘的负例，不是用户手机图。\n\n"
            "局限：glyph仍为minRGB<180或色差≥40；纸白165时整张纸可能成为图案。复杂/低对比背景、旋转透视及相机成像未验证；同色物与背景或整ROI同色遮挡在单帧中不可观测。没有实物准确率或上板结论。\n\n"
            +json.dumps({k:v for k,v in summary.items() if k!="failures"},ensure_ascii=False,indent=2)+"\n\n逐例结果及所有失败见fixtures.json和summary.json。\n",encoding="utf-8")
        save(output/"manifest.json",{"created_at":datetime.now(timezone(timedelta(hours=8))).isoformat(),
            "command":sys.argv,"sources":sources,"scripts":[{"path":str(p),"sha256":sha(p)} for p in (Path(__file__),HERE/"scene-model.py")],
            "grid":{"width":120,"height":60,"bp_first_x":41,"bp_first_y":31,"bp_step":2},
            "thresholds":{"background_linf":48,"border_similar_min_fraction":"3/4","denoise_neighborhood_min":3,
                "occupancy_min":12,"bbox_min":3,"normalized_side":20,"templates_per_class":3,"max_distance":40,"min_margin":24},
            "groups":groups,"rtl_default_count":summary["rtl_default_count"],
            "boundary":"Synthetic development evidence; no camera-photo accuracy or hardware validation.",
            "outputs":[{"path":str(p.relative_to(output)),"sha256":sha(p)} for p in sorted(output.rglob("*")) if p.is_file()]})
    print(json.dumps(summary,ensure_ascii=False))
    return 1 if summary["required_failures"] else 0

if __name__=="__main__":raise SystemExit(main())

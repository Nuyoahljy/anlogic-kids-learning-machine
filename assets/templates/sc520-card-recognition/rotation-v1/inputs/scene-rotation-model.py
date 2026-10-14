"""Joint scene/paper/shape/rotation-bank oracle; scene-v2 remains unchanged."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import numpy as np

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("scene_v2",HERE/"scene-model.py")
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
sample_frame=base.sample_frame
threshold=base.threshold
normalize=base.normalize
despeckle=base.despeckle

def shape_classify(mask):
    yy,xx=np.mgrid[:20,:20];dx=2*xx+1-20;dy=2*yy+1-20
    templates=np.zeros((3,32,32),dtype=bool)
    templates[0,6:26,6:26]=dx*dx+dy*dy<=400
    templates[1,6:26,6:26]=True
    templates[2,6:26,6:26]=2*np.abs(dx)<=2*yy+1
    distances=np.count_nonzero(templates!=np.asarray(mask,dtype=bool),axis=(1,2)).astype(int).tolist()
    bits=sum(int(d<=20)<<i for i,d in enumerate(distances))
    return {"distances":distances,"shape_bits":bits}

def analyze(rgb):
    result=base.analyze(rgb)
    paper_count=int(np.count_nonzero(result["scene"] & ~threshold(rgb)))
    bounds=result["scene_bbox"]
    occupied=bool(result["scene_count"]>=12 and bounds and bounds[2]-bounds[0]>=2 and bounds[3]-bounds[1]>=2)
    paper_route=bool(occupied and result["glyph_count"]>=12 and paper_count*4>result["scene_count"])
    result.update(paper_count=paper_count,paper_route=paper_route)
    if paper_route:result["replay_rgb"]=np.full_like(result["replay_rgb"],255)
    return result

def classify(mask,bank,present=True):
    mask=np.asarray(mask,dtype=bool)
    if mask.shape==(32,32):active=mask[6:26,6:26]
    elif mask.shape==(20,20):active=mask
    else:raise ValueError("mask must be 32x32 or the inner 20x20")
    bank=np.asarray(bank,dtype=bool)
    if bank.ndim!=4 or bank.shape[0]!=5 or bank.shape[2:]!=(20,20):raise ValueError("bank must be [5,variants,20,20]")
    distances=np.count_nonzero(bank!=active,axis=(2,3)).min(axis=1).astype(int).tolist()
    order=sorted(range(5),key=lambda i:(distances[i],i));best=distances[order[0]];second=distances[order[1]];fg=int(active.sum())
    valid=bool(present and 16<=fg<=850 and best<=40 and second-best>=24)
    return {"distances":distances,"best":best,"second":second,"foreground":fg,"valid":valid,"item":order[0]+10 if valid else 0}

def recognize(frame,bank):
    result=analyze(sample_frame(frame));shape=shape_classify(result["mask"])
    card_raw=classify(result["mask"],bank,result["present"])
    card_item=card_raw["item"] if shape["shape_bits"]==0 else 0
    block_raw=base.block_classify(result["replay_rgb"],result["present"])
    block_item=block_raw if block_raw and shape["shape_bits"]&(1<<((block_raw-1)%3)) else 0
    conflict=bool(card_item and block_item)
    result.update(card_raw=card_raw,card_item=card_item,block_raw=block_raw,block_item=block_item,
                  shape=shape,conflict=conflict,item=0 if conflict else card_item or block_item)
    return result

def tone07(rgb):
    values=np.asarray(rgb,dtype=np.uint16)
    knots=np.array([0,37,60,79,97,113,129,143,157,171,184,197,209,221,233,244,255],dtype=np.uint16)
    index=values>>4
    mapped=knots[index]+(((knots[index+1]-knots[index])*(values&15)+8)>>4)
    return np.where(values==255,255,mapped).astype(np.uint8)

def read_bank(path,variants=256):
    words=np.loadtxt(path,dtype=np.uint8,converters=lambda x:int(x,16))
    if len(words)!=variants*400 or int(words.max())>=32:raise ValueError("rotation ROM layout mismatch")
    return np.asarray([((words>>i)&1).reshape(variants,20,20) for i in range(5)],dtype=bool)

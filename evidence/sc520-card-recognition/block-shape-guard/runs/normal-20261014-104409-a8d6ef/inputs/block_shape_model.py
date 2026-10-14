"""Integer contract for normalized solid-shape qualification; no color decision."""
import numpy as np

MAX_DISTANCE=20
def templates():
    result=np.zeros((3,32,32),dtype=bool)
    yy,xx=np.mgrid[0:20,0:20]
    dx=2*xx+1-20;dy=2*yy+1-20
    result[0,6:26,6:26]=dx*dx+dy*dy<=400
    result[1,6:26,6:26]=True
    result[2,6:26,6:26]=2*np.abs(dx)<=2*yy+1
    return result

def classify(mask,max_distance=MAX_DISTANCE):
    mask=np.asarray(mask,dtype=bool)
    if mask.shape!=(32,32):raise ValueError('normalized glyph must be 32x32')
    distance=np.count_nonzero(templates()!=mask,axis=(1,2)).astype(int).tolist()
    shape_ok=[d<=max_distance for d in distance]
    return {'distance':distance,'shape_ok':shape_ok,'shape_bits':sum(int(x)<<i for i,x in enumerate(shape_ok))}

def gate(block_item,mask,max_distance=MAX_DISTANCE):
    if not 1<=block_item<=9:return 0
    return block_item if classify(mask,max_distance)['shape_ok'][(block_item-1)%3] else 0

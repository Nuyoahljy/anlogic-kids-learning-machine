"""Derive only additional business/default tests; retain earlier input hashes."""
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
for test in ('business','default'):
    source=ROOT/f'fpga/sim/sc520-card-recognition/audio22/tb_audio22_{test}.sv'
    target=ROOT/f'fpga/sim/sc520-card-recognition/timing23/tb_timing23_{test}.sv'
    assert not target.exists()
    s=source.read_text(encoding='utf-8-sig').replace('tb_audio22_','tb_timing23_')
    s=s.replace('pixel22_compositor','pixel23_compositor')
    target.write_text(s,encoding='utf-8')
runner=HERE/'simulate-timing23-extended.py';assert not runner.exists()
s=(HERE/'simulate-timing23.py').read_text(encoding='utf-8-sig')
s=s.replace("choices=('render','pipeline','reset')","choices=('business','default')")
s=s.replace("if args.test in ('business','pipeline'):","if args.test in ('business','default'):")
runner.write_text(s,encoding='utf-8')
print('Added business/default new-DUT tests and separate runner')

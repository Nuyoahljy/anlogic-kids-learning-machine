"""Preserve the first stream test and add values to its exact failed assertion."""
from pathlib import Path
R = Path(__file__).resolve().parents[3]
source = R / "fpga/sim/sc520-contour29/tb_contour29_fps.sv"
text = source.read_text(encoding="utf-8").replace("tb_contour29_fps", "tb_contour29_fpsdiag")
text = text.replace("if(obs_revoke)revoke_events++;",
                    'if(obs_revoke)begin revoke_events++;$display("REVOKE time=%0t cycle=%0d stress=%0d link_fault=%0d quarantine=%0d",$time,capture_cycles,stress,link_fault,quarantined);end')
needle = '    ck(revoke_events==0 && !link_fault && !quarantined,"no revoke, overflow or mailbox fault at supported rate");'
assert text.count(needle) == 1
text = text.replace(needle,
    '    $display("NORMAL_WINDOW_END revokes=%0d link_fault=%0d quarantined=%0d cycles=%0d",revoke_events,link_fault,quarantined,capture_cycles);\n' + needle)
with source.with_name("tb_contour29_fpsdiag.sv").open("x", encoding="utf-8", newline="\n") as stream:
    stream.write(text)

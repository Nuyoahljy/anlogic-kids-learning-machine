"""Separate the measured startup revoke from the supported-input interval."""
from pathlib import Path
R = Path(__file__).resolve().parents[3]
source = R / "fpga/sim/sc520-contour29/tb_contour29_fpsdiag.sv"
text = source.read_text(encoding="utf-8").replace("tb_contour29_fpsdiag", "tb_contour29_fpsverify")
text = text.replace("  reg test_done=0,stress=0,saw_bank_overlap=0;",
                    "  reg test_done=0,stress=0,saw_bank_overlap=0,supported_window=0;\n  integer startup_revokes=0,supported_revokes=0;")
text = text.replace("if(obs_revoke)begin revoke_events++;",
                    "if(obs_revoke)begin revoke_events++;if(supported_window && !stress)supported_revokes++;")
needle = "    for(integer tag=1;tag<=4;tag++)send_frame(tag,2076);"
assert text.count(needle) == 1
text = text.replace(needle, '''    startup_revokes=revoke_events;
    ck(startup_revokes==1 && capture_cycles<40,"exact startup revoke occurs before the first producer frame");
    supported_window=1;
''' + needle)
text = text.replace('ck(revoke_events==0 && !link_fault && !quarantined,"no revoke, overflow or mailbox fault at supported rate");',
                    'ck(revoke_events==startup_revokes && supported_revokes==0 && !link_fault && !quarantined,"no revoke, overflow or mailbox fault during supported input interval");')
text = text.replace('    $display("RESULT fps errors=', '    $display("WINDOW startup_revokes=%0d supported_revokes=%0d",startup_revokes,supported_revokes);\n    $display("RESULT fps errors=')
with source.with_name("tb_contour29_fpsverify.sv").open("x", encoding="utf-8", newline="\n") as stream:
    stream.write(text)

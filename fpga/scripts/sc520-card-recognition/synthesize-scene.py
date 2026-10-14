"""Measure the snapshotted scene kernel in TD 6.2.1; synthesis only, no board top."""
from __future__ import annotations
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import time
import uuid
from xml.sax.saxutils import escape

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("scene_synth_common", HERE / "simulate.py")
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
REPO = common.REPO


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=REPO / "fpga/rtl/sc520-card-recognition/pixel14/pixel14_scene_preprocess.v")
    parser.add_argument("--tag", default="kernel")
    args = parser.parse_args()
    if not args.tag.replace("-", "").isalnum():
        parser.error("tag must be ASCII letters, numbers or hyphens")
    tool = Path("D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe")
    if not tool.is_file():
        parser.error("TD 6.2.1 executable missing")
    tag = common.now().replace("-", "").replace(":", "").replace("T", "-")[:15]
    run = REPO / "evidence/sc520-card-recognition/builds" / f"scene-{args.tag}-{tag}-{uuid.uuid4().hex[:6]}"
    run.mkdir(parents=True, exist_ok=False)
    source = args.source.resolve()
    frozen = run / "pixel14_scene_preprocess.v"
    sha = common.digest(source)
    frozen.write_bytes(source.read_bytes())
    if common.digest(frozen) != sha or common.digest(source) != sha:
        raise RuntimeError("source changed during snapshot")
    (run / Path(__file__).name).write_bytes(Path(__file__).read_bytes())
    wrapper = run / "scene_synthesis_wrapper.v"
    wrapper.write_text('''// Registered input and observable signature wrapper for resource measurement.
module scene_synthesis_wrapper(input wire clk,rst_n,flush,in_valid,in_sof,in_eol,
 input wire [10:0] in_x,input wire [9:0] in_y,input wire [23:0] in_rgb,
 input wire in_frame_end,in_frame_good,input wire [31:0] in_frame_id,input wire in_source_test,
 output reg [31:0] signature);
 reg flush_q,valid_q,sof_q,eol_q,end_q,good_q,source_q;
 reg [10:0] x_q;reg [9:0] y_q;reg [23:0] rgb_q;reg [31:0] id_q;
 always @(posedge clk) begin
   flush_q<=flush;valid_q<=in_valid;sof_q<=in_sof;eol_q<=in_eol;x_q<=in_x;y_q<=in_y;
   rgb_q<=in_rgb;end_q<=in_frame_end;good_q<=in_frame_good;id_q<=in_frame_id;source_q<=in_source_test;
 end
 wire replay_valid,replay_sof,replay_eol,replay_end,replay_good,replay_present,replay_source;
 wire [10:0] replay_x;wire [9:0] replay_y;wire [23:0] replay_rgb;wire [31:0] replay_id;
 wire card_start,card_valid,card_fg,card_end,card_good,card_present,card_source,out_revoke;
 wire [9:0] card_index;wire [31:0] card_id;wire [15:0] dbg_scene_count,dbg_glyph_count;
 pixel14_scene_preprocess dut(.clk(clk),.rst_n(rst_n),.flush(flush_q),.in_valid(valid_q),.in_sof(sof_q),.in_eol(eol_q),
 .in_x(x_q),.in_y(y_q),.in_rgb(rgb_q),.in_frame_end(end_q),.in_frame_good(good_q),.in_frame_id(id_q),.in_source_test(source_q),
 .replay_valid(replay_valid),.replay_sof(replay_sof),.replay_eol(replay_eol),.replay_x(replay_x),.replay_y(replay_y),
 .replay_rgb(replay_rgb),.replay_end(replay_end),.replay_good(replay_good),.replay_present(replay_present),.replay_id(replay_id),.replay_source(replay_source),
 .card_start(card_start),.card_valid(card_valid),.card_index(card_index),.card_fg(card_fg),.card_end(card_end),.card_good(card_good),
 .card_present(card_present),.card_id(card_id),.card_source(card_source),.out_revoke(out_revoke),.dbg_scene_count(dbg_scene_count),.dbg_glyph_count(dbg_glyph_count));
 wire [165:0] observed={replay_valid,replay_sof,replay_eol,replay_x,replay_y,replay_rgb,replay_end,replay_good,replay_present,replay_id,replay_source,
 card_start,card_valid,card_index,card_fg,card_end,card_good,card_present,card_id,card_source,out_revoke,dbg_scene_count,dbg_glyph_count};
 always @(posedge clk or negedge rst_n) if(!rst_n)signature<=0;
 else signature<={signature[30:0],signature[31]}^observed[31:0]^observed[63:32]^observed[95:64]^observed[127:96]^observed[159:128]^{26'd0,observed[165:160]};
endmodule
''', encoding="ascii")
    (run / "scene.prj").write_text(f'''<Project Version="3" Minor="2">
<TD_Encoding>UTF-8</TD_Encoding><TD_Version>6.2.168116</TD_Version><Name>scene</Name>
<HardWare><Family>PH1</Family><Device>PH1P35MDG324</Device><Speed>-3</Speed></HardWare>
<Source_Files><Verilog><File Path="{escape(frozen.as_posix())}"><FileInfo>
<Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/>
<Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="1"/>
</FileInfo></File><File Path="{escape(wrapper.as_posix())}"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="2"/></FileInfo></File></Verilog></Source_Files>
<TOP_MODULE><LABEL>scene_synthesis_wrapper</LABEL><MODULE>scene_synthesis_wrapper</MODULE><CREATEINDEX>user</CREATEINDEX></TOP_MODULE>
<FileSets><FileSet Name="design_1" Type="DesignFiles"/><FileSet Name="constraint_1" Type="ConstrainFiles"/></FileSets>
<Property/><Device_Settings/>
</Project>\n''', encoding="utf-8")
    (run / "scene.sdc").write_text("create_clock -name SCENE_CLK -period 9.660 [get_ports {clk}]\n", encoding="ascii")
    launch = run / "launch.tcl"
    launch.write_text('''if {[catch {
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
open_project scene.prj
commit_param -step design
elaborate -top scene_synthesis_wrapper
read_sdc scene.sdc
export_db scene_elaborate.db
commit_param -step rtl
optimize_rtl
report_area -file scene_rtl.area
export_db scene_rtl.db
commit_param -step gate
optimize_gate -packarea scene_gate.area
legalize_phy_inst
update_timing
report_timing_summary -file scene_gate.timing
export_db scene_gate.db
write_verilog scene_gate.v
} failure]} {puts stderr $failure; exit 1}
puts "SCENE_SYNTHESIS_COMPLETED"
exit 0
''', encoding="utf-8")
    # TD interprets its script argument as Tcl text; POSIX separators prevent
    # Windows backslashes from becoming Tcl escapes before the file is opened.
    command = [tool.as_posix(), launch.as_posix()]
    report = {"StartedAt": common.now(), "Source": str(source), "SourceSHA256": sha, "Snapshot": str(frozen),
              "Tool": str(tool), "ToolSHA256": common.digest(tool), "Command": command, "Workdir": str(run),
              "Scope": "Synthesis-only kernel plus registered input/signature wrapper resource measurement; no place, route, bit or board access",
              "Owner": "01a13561-2629-7fa2-86a0-4087ad34cc7c /root/scene_rtl"}
    common.save(run / "run-start.json", report)
    start = time.monotonic()
    with (run / "stdout.log").open("wb") as stdout, (run / "stderr.log").open("wb") as stderr:
        process = subprocess.Popen(command, cwd=run, stdout=stdout, stderr=stderr,
                                   creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        report["PID"] = process.pid
        common.save(run / "running.json", report)
        code = process.wait()
    report.update({"CompletedAt": common.now(), "ExitCode": code, "ElapsedSeconds": round(time.monotonic()-start, 3),
                   "SourceUnchanged": common.digest(source) == sha, "SnapshotUnchanged": common.digest(frozen) == sha,
                   "SynthesisCompleted": code == 0 and "SCENE_SYNTHESIS_COMPLETED" in (run / "stdout.log").read_text(errors="replace"),
                   "Artifacts": [{"path": str(p), "sha256": common.digest(p), "bytes": p.stat().st_size}
                                 for p in sorted(run.iterdir()) if p.is_file() and p.suffix not in (".db",)]})
    common.save(run / "run-manifest.json", report)
    print(json.dumps({"run": str(run), "exit": code, "synthesis_completed": report["SynthesisCompleted"], "seconds": report["ElapsedSeconds"]}))
    return 0 if report["SynthesisCompleted"] and report["SnapshotUnchanged"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

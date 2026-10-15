"""Snapshot and run real color-to-scene-to-business RTL with original dark cards."""
from __future__ import annotations
import argparse
from datetime import datetime,timezone,timedelta
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
import uuid
import numpy as np
from PIL import Image

HERE=Path(__file__).resolve().parent;REPO=HERE.parents[2]
def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()
def now():return datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="milliseconds")
def save(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
def tcl(path):
    value=str(path).replace("\\","/")
    if any(c in value for c in "{}\r\n"):raise ValueError("unsupported Tcl path")
    return "{"+value+"}"
def rgbmem(path,rgb):path.write_text("".join(f"{int(r):02x}{int(g):02x}{int(b):02x}\n" for r,g,b in rgb.reshape(-1,3)),encoding="ascii")

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    modes=parser.add_mutually_exclusive_group()
    modes.add_argument("--negative",action="store_true");modes.add_argument("--watchdog-probe",action="store_true")
    parser.add_argument("--timeout-seconds",type=int,default=1200)
    parser.add_argument("--observation",action="store_true")
    parser.add_argument("--simulator",type=Path,default=Path("D:/modeltech64_10.7/win64/vsim.exe"))
    args=parser.parse_args()
    mode="negative" if args.negative else "watchdog" if args.watchdog_probe else "normal"
    base=REPO/"fpga/rtl/sc520-card-recognition";pixel=base/"pixel14"
    vendor=REPO.parent/"sc520-fixed-roi/fpga/custom_project/sc520-board-keys/user_source/hdl_source/signal_delay.v"
    behavioral=REPO/"evidence/sc520-card-recognition/imaging-audit/ip_behavioral_models.sv"
    color=REPO/"fpga/custom_project/sc520-pixel14/overlay/pixel14_color_pipeline.v"
    rtl=[color,vendor,behavioral]+[pixel/name for name in (
        "capture_rgb96.v","block_frame_recognizer.v","pixel14_card_matcher.v","pixel14_result_cdc.v",
        "pixel14_pipeline.v","pixel14_card_template_rom.v","pixel14_scene_preprocess.v",
        "pixel14_rotation_matcher.v","pixel14_block_shape_guard.v","pixel14_block_filter.v")]
    rtl += [base/name for name in ("card_matcher.v","card_template_rom.v","card_result_filter.v")]
    rtl += sorted((base/"items14").glob("*.v"))
    rtl += sorted((base/"color_diag").glob("*.v"))
    top="tb_pixel14_observation_system" if args.observation else "tb_pixel14_color_scene"
    tb=REPO/"fpga/sim/sc520-card-recognition"/(top+".sv")
    assets=REPO/"assets/templates/sc520-card-recognition/rotation-v1"
    fixtures=json.loads((assets/"fixtures.json").read_text(encoding="utf-8"))
    card_pairs=[]
    for item in range(10,15):
        before=next(r for r in fixtures if r["category"]=="tone_stress" and r["truth_item"]==item)
        after=next(r for r in fixtures if r["category"]=="tone_joint" and r["truth_item"]==item)
        card_pairs.append((item,assets/"vectors"/f"{before['prefix']}.png",assets/"vectors"/f"{after['prefix']}.png"))
    sources=rtl+[tb,Path(__file__).resolve(),assets/"templates.mem",assets/"manifest.json",assets/"fixtures.json"]
    sources += [path for _,before,after in card_pairs for path in (before,after)]
    ini=args.simulator.parent.parent/"modelsim.ini"
    if not all(p.is_file() for p in sources+[args.simulator,ini]):parser.error("missing source/reference or ModelSim installation")
    stamp=datetime.now(timezone(timedelta(hours=8))).strftime("%Y%m%d-%H%M%S")
    run=REPO/"evidence/sc520-card-recognition/runs"/f"p14-color-scene-{mode}-{stamp}-{uuid.uuid4().hex[:8]}"
    snapshot=run/"inputs";snapshot.mkdir(parents=True,exist_ok=False);(snapshot/"mem").mkdir();(snapshot/"pictures").mkdir();(run/"tmp").mkdir()
    inputs=[];paths={}
    for source in sources:
        destination=snapshot/"pictures"/source.name if source.suffix==".png" else snapshot/source.name
        before=digest(source);destination.write_bytes(source.read_bytes())
        if digest(destination)!=before:raise RuntimeError("source changed during snapshot")
        inputs.append({"path":str(source),"snapshot":str(destination),"sha256_before":before});paths[source]=destination
    conversions=[];case_lines=[]
    knots=np.array([0,37,60,79,97,113,129,143,157,171,184,197,209,221,233,244,255],dtype=np.int16)
    for item,before,after in card_pairs:
        raw=np.asarray(Image.open(paths[before]).convert("RGB"));reference=np.asarray(Image.open(paths[after]).convert("RGB"))
        if raw.shape!=(180,320,3) or reference.shape!=raw.shape:raise ValueError("unexpected source PNG geometry")
        values=raw.astype(np.int16);index=values>>4
        expected=np.where(values==255,255,knots[index]+(((knots[index+1]-knots[index])*(values&15)+8)>>4)).astype(np.uint8)
        if not np.array_equal(expected,reference):raise ValueError("supplied after PNG differs from independent unit-WB tone mapping")
        lo=values.min(axis=-1);hi=values.max(axis=-1)
        neutral=int(np.count_nonzero((lo>=64)&(hi<=247)&((hi-lo)<=(hi>>2))))*16
        before_mem=snapshot/"mem"/f"card{item}_before.mem";after_mem=snapshot/"mem"/f"card{item}_after.mem"
        rgbmem(before_mem,raw);rgbmem(after_mem,reference)
        case_lines.append(f"{item} {before_mem.name} {after_mem.name} {neutral}\n")
        conversions.append({"item":item,"input_png":str(before),"input_png_sha256":digest(before),
            "reference_png":str(after),"reference_png_sha256":digest(after),"raw_mem":str(before_mem),
            "raw_mem_sha256":digest(before_mem),"reference_mem":str(after_mem),"reference_mem_sha256":digest(after_mem),
            "full_resolution_neutral_samples":neutral,"input_transform":"PNG RGB bytes serialized unchanged; HDL repeats each bp pixel four horizontal lanes and four rows. Tone is applied only by the actual color DUT."})
    (snapshot/"cards.txt").write_text("".join(case_lines),encoding="ascii")
    save(snapshot/"conversions.json",conversions)
    (run/"modelsim.ini").write_bytes(ini.read_bytes());(run/"templates.mem").write_bytes((assets/"templates.mem").read_bytes())
    command_text="""onerror {quit -force -code 2}
onbreak {resume}
vlib work
vmap work work
vlog -sv %s
vsim -voptargs=+acc -wlf wave.wlf work.%s +ASSET_ROOT=%s +INJECT_FAULT=%d
onfinish stop
%s
set errors [examine -radix decimal /%s/errors]
set checks [examine -radix decimal /%s/checks]
set scenarios [examine -radix decimal /%s/scenarios]
set done [examine -radix unsigned /%s/test_done]
set injected [examine -radix decimal /%s/injected]
set frames [examine -radix decimal /%s/frames_sent]
set fd [open summary.json w]
puts $fd [format {{"errors":%%d,"checks":%%d,"scenarios":%%d,"done":%%d,"injected":%%d,"frames":%%d}} $errors $checks $scenarios $done $injected $frames]
close $fd
if {!$done} {quit -force -code 2}
if {$errors != 0} {quit -force -code 1}
quit -force -code 0
""" % (" ".join(tcl(paths[p]) for p in rtl+[tb]),top,str(snapshot).replace("\\","/"),int(args.negative),
          "run 500 ns" if args.watchdog_probe else "run -all",top,top,top,top,top,top)
    (run/"run.do").write_text(command_text,encoding="utf-8")
    command=[str(args.simulator),"-modelsimini",str(run/"modelsim.ini"),"-c","-l","transcript.log","-do","do run.do"]
    report={"StartedAt":now(),"Mode":mode,"Command":command,"WorkingDirectory":str(run),"Inputs":inputs,
        "Conversions":conversions,"TimeoutSeconds":args.timeout_seconds,
        "Scope":"Actual pixel14_color_pipeline to capture/scene/rotation matcher/shape filter/result transport/business controller. Original dark PNG inputs, supplied after PNGs used only as references. Qualified external EOF after observed output drain, no CSI/RAW/DDR/PHY/board qualification. Vendor signal_delay is unchanged; dual-port memory is an explicit behavioral boundary; its unused divider model is not instantiated by the new color path."}
    save(run/"run-start.json",report);start=time.monotonic();native=None;timed_out=False;summary=None
    import os
    environment=os.environ.copy();environment["TEMP"]=str(run/"tmp");environment["TMP"]=str(run/"tmp")
    try:
        with (run/"stdout.log").open("wb") as stdout,(run/"stderr.log").open("wb") as stderr:
            process=subprocess.Popen(command,cwd=run,stdout=stdout,stderr=stderr,env=environment);report["PID"]=process.pid
            try:native=process.wait(timeout=args.timeout_seconds)
            except subprocess.TimeoutExpired:
                timed_out=True
                if sys.platform=="win32":subprocess.run(["taskkill","/PID",str(process.pid),"/T","/F"],capture_output=True)
                else:process.kill()
                native=process.wait(timeout=10)
        if (run/"summary.json").exists():summary=json.loads((run/"summary.json").read_text(encoding="utf-8"))
    except Exception as error:report["RunError"]=f"{type(error).__name__}: {error}"
    for entry in inputs:
        entry["sha256_after"]=digest(Path(entry["path"]));entry["snapshot_sha256"]=digest(Path(entry["snapshot"]))
    unchanged=all(e["sha256_before"]==e["sha256_after"]==e["snapshot_sha256"] for e in inputs)
    transcript=(run/"transcript.log").read_text(encoding="utf-8",errors="replace") if (run/"transcript.log").exists() else ""
    clean=not any(t in transcript for t in ("** Error:","** Fatal:","WATCHDOG"))
    expected=(2,0,0,0) if args.watchdog_probe else (int(args.negative),1,int(args.negative),int(args.negative))
    observed=(native,summary.get("done"),summary.get("errors"),summary.get("injected")) if summary else None
    qualified=unchanged and clean and not timed_out and expected==observed and (args.watchdog_probe or summary.get("checks",0)>0)
    if qualified and mode=="normal":qualified=summary["frames"]==(28 if args.observation else 24)
    report.update(ObservationEnabled=args.observation,FinishedAt=now(),ElapsedSeconds=time.monotonic()-start,NativeExitCode=native,TimedOut=timed_out,
        InputsUnchanged=unchanged,Summary=summary,Qualified=bool(qualified))
    report["GeneratedInputs"]=[{"path":str(p),"sha256":digest(p)} for p in sorted((snapshot/"mem").iterdir())]+[
        {"path":str(snapshot/name),"sha256":digest(snapshot/name)} for name in ("cards.txt","conversions.json")]
    report["Outputs"]=[{"path":str(p),"sha256":digest(p)} for p in sorted(run.iterdir()) if p.is_file() and p.name not in ("wave.wlf","modelsim.ini")]
    save(run/"run-manifest.json",report)
    print(json.dumps({"run":str(run),"qualified":bool(qualified),"native_exit":native,"summary":summary}))
    return 0 if qualified else 1

if __name__=="__main__":raise SystemExit(main())

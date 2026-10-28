"""Run the same real hierarchy against frozen R4B (must fail) and R4C."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
J316 = ROOT / "evidence/sc520-system-integration/j316"
SIM = Path(__file__).resolve().parent
TOOLS = Path("D:/modeltech64_10.7/win64")

def bind(p):
    b = p.read_bytes()
    return {"Path":p.as_posix(), "SHA256":hashlib.sha256(b).hexdigest().upper(), "Bytes":len(b)}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args=parser.parse_args()
    out=args.output.resolve()
    out.relative_to((ROOT/"evidence/sc520-system-integration").resolve())
    out.mkdir(parents=True, exist_ok=False)
    manifest=json.loads((J316/"preparation-result.json").read_text())
    files=[J316/r["Relative"] for r in manifest["CompileEntries"]]
    modules={}
    text={}
    for p in files:
        # Declarations are ASCII; some unchanged vendor comments use GBK.
        text[p]=p.read_bytes().decode("latin-1")
        for name in re.findall(r"(?m)^\s*module\s+(\w+)",text[p]):
            if name in modules: raise RuntimeError("Duplicate compiled module: "+name)
            modules[name]=p
    needed=set()
    def visit(p):
        if p in needed:return
        needed.add(p)
        src=re.sub(r"//[^\n]*|/\*.*?\*/","",text[p],flags=re.S)
        for name,q in modules.items():
            if re.search(r"\b"+re.escape(name)+r"\s*(?:#\s*\(|[A-Za-z_$]\w*\s*\()",src):visit(q)
    visit(modules["pixel310_pipeline"])
    visit(modules["pixel286_color_observer"])
    sources=[p for p in files if p in needed]
    for p in sources:
        expected=manifest["Files"][p.relative_to(J316).as_posix()]
        if bind(p)!=expected:raise RuntimeError("Frozen source changed: "+str(p))
    tb=SIM/"tb_pipeline_calibration.sv"
    original=ROOT/"fpga/rtl/sc520-system-integration-i0310/pixel310_pipeline.v"
    candidate=ROOT/"fpga/rtl/sc520-system-integration-i0310-r4c/pixel310_pipeline.v"
    if bind(original)["SHA256"] != "9431CFB307007088D9E3BB5BB46463A9621A524D0C10320435E9B6B559409250":
        raise RuntimeError("R4B original changed")
    headers=sorted(J316.rglob("*.vh"))
    # A retained ancestor packet include is absolute in the prepared sources.
    # Bind that actual dependency as well as the current manifest headers.
    for p in sources:
        for literal in re.findall(r'(?m)^\s*`include\s+"([^"]+)"',text[p]):
            header=Path(literal)
            if not header.is_absolute():
                header=p.parent/header
            if header.is_file() and header not in headers:
                headers.append(header)
    template=J316/"owned/assets/templates/sc520-card-recognition/rotation-v1/templates.mem"
    protected={p.as_posix():bind(p) for p in sources+[tb,original,candidate,Path(__file__).resolve(),template]+headers}
    snapshots={}
    for index,row in enumerate(protected.values()):
        p=Path(row["Path"])
        target=out/"inputs"/str(index)/p.name
        target.parent.mkdir(parents=True,exist_ok=False)
        shutil.copyfile(p,target)
        frozen=bind(target)
        if (frozen["SHA256"],frozen["Bytes"])!=(row["SHA256"],row["Bytes"]):
            raise RuntimeError("Input changed during snapshot: "+str(p))
        snapshots[p]=target
    includes=sorted({snapshots[p].parent.as_posix() for p in headers})
    summary={"At":datetime.now().astimezone().isoformat(),"Sources":list(protected.values()),
             "Snapshots":[{"Original":row,"Snapshot":bind(snapshots[Path(row["Path"])])} for row in protected.values()],"Cases":[],
             "Boundary":"Real pipeline, capture, scene, matcher, CDC, business system and observer; RGB and AWB-statistics public inputs are stimulated. Renderer disabled; no force, stubs, sensor or full ISP simulation."}
    summary["Failure"]=None
    try:
        for label,dut in (("old-r4b",original),("new-r4c",candidate)):
            case=out/label;case.mkdir()
            shutil.copyfile(snapshots[template],case/"templates.mem")
            srcs=[snapshots[dut] if p==modules["pixel310_pipeline"] else snapshots[p] for p in sources]+[snapshots[tb]]
            calls=[]
            entry={"Case":label,"ExpectedFailure":label=="old-r4b","PassedExpectation":False,"Commands":calls}
            summary["Cases"].append(entry)
            def run(name,command,timeout=120):
                start=time.monotonic()
                with (case/(name+".stdout.log")).open("wb") as so,(case/(name+".stderr.log")).open("wb") as se:
                    result=subprocess.run(command,cwd=case,stdout=so,stderr=se,timeout=timeout)
                call={"Name":name,"Command":command,"Cwd":case.as_posix(),"Exit":result.returncode,"Seconds":round(time.monotonic()-start,3)}
                calls.append(call)
                return result.returncode
            if run("vlib",[str(TOOLS/"vlib.exe"),"work"]):raise RuntimeError("vlib failed")
            if run("vlog",[str(TOOLS/"vlog.exe"),"-sv","-work","work"]+["+incdir+"+p for p in includes]+[p.as_posix() for p in srcs]):raise RuntimeError("vlog failed: "+label)
            if run("vopt",[str(TOOLS/"vopt.exe"),"work.tb_pipeline_calibration","-o","tb_pipeline_calibration_opt","+acc"]):raise RuntimeError("vopt failed: "+label)
            macro="onerror {quit -f -code 3}\nonbreak {if {[examine -radix decimal sim:/tb_pipeline_calibration/test_done] == 1} {quit -f -code 0} else {quit -f -code 2}}\nrun -all\nquit -f -code 4\n"
            (case/"run.do").write_text(macro,encoding="ascii")
            exit_code=run("vsim",[str(TOOLS/"vsim.exe"),"-c","-onfinish","stop","work.tb_pipeline_calibration_opt","-l","vsim.log","-do","do run.do"],180)
            log=(case/"vsim.log").read_text(errors="replace")
            if label=="old-r4b":
                okay=exit_code!=0 and "FAIL R4C busy must permit a complete trustworthy calibration frame" in log
            else:
                okay=exit_code==0 and "PASS R4C pipeline" in log and "FAIL R4C" not in log
            entry["PassedExpectation"]=okay
            entry["Logs"]=[bind(p) for p in sorted(case.glob("*.log"))]+[bind(case/"run.do")]
            if not okay:raise RuntimeError("Unexpected result: "+label)
    except Exception as exc:
        summary["Failure"]=str(exc)
    finally:
        summary["ChangedInputs"]=[p for p,row in protected.items() if not Path(p).is_file() or bind(Path(p))!=row]
        summary["Pass"]=summary["Failure"] is None and len(summary["Cases"])==2 and all(c["PassedExpectation"] for c in summary["Cases"]) and not summary["ChangedInputs"]
        (out/"result.json").write_text(json.dumps(summary,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"Pass":summary["Pass"],"Result":bind(out/"result.json"),"Sources":len(protected)}))
    return 0 if summary["Pass"] else 1

if __name__=="__main__":raise SystemExit(main())

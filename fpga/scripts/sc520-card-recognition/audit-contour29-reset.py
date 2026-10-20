"""Reuse the frozen ten-partition reset audit, binding this T029 adapter too."""
from pathlib import Path
import argparse
import importlib.util
import hashlib
import json

LEGACY = Path(__file__).with_name("audit-shape27-reset.py")
assert hashlib.sha256(LEGACY.read_bytes()).hexdigest().upper() == "6E946B86EC44F77EAC8B481F02038A314006DF076DE3E912CDD8798EC0E823E9"
spec = importlib.util.spec_from_file_location("contour29_reset_base", LEGACY)
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("run", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = base.audit(args.run.resolve())
    result["LegacyAudit"] = base.base.artifact(LEGACY)
    result["T029Adapter"] = base.base.artifact(__file__)
    result["Task"] = "sc520-contour29"
    base.base.emit(args.output, result)
    print(json.dumps(dict(Qualified=result["Qualified"], Branches=result["SecondStageCount"],
                          MaximumFanout=result["MaximumBranchFanout"])))

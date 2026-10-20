"""Prepare a T029 overlay with immutable hardware-default audio and ROM inputs."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil

SOURCE = Path(__file__).with_name("prepare-timing23.py")
R = Path(__file__).resolve().parents[3]
PROJECT = R / "fpga/custom_project/sc520-contour29"
text = SOURCE.read_text(encoding="utf-8")
text = text.replace("PROJECT=REPO/'fpga/custom_project/sc520-timing23'",
                    "PROJECT=REPO/'fpga/custom_project/sc520-contour29'")
text = text.replace("    sources += sorted((RTL/'timing23').glob('*.v'))",
                    """    sources += sorted((RTL/'timing23').glob('*.v'))
    sources += sorted((REPO/'fpga/rtl/sc520-color-integration').glob('*.v'))
    sources += sorted((REPO/'fpga/rtl/sc520-shape27').glob('*.v'))
    sources += sorted((REPO/'fpga/rtl/sc520-contour29').glob('*.v'))""")
text = text.replace("('prepare-timing23.py','build-timing23.ps1','audit-timing23-reset.py')",
                    "('prepare-contour29.py','build-contour29.ps1','audit-contour29-reset.py','prepare-timing23.py','audit-shape27-reset.py')")
text = text.replace("('offline-test.json' if snapshot else 'hardware-default.json')", "'hardware-default.json'")
start = text.index("    if snapshot:\n        assert profile['TestOnly']")
end = text.index("    save(destination/'profile.json'", start)
text = text[:start] + "    assert not profile['TestOnly'] and profile['TRACKS']==[]\n" + text[end:]
text = text.replace('T023 forbids bitgen', 'T029 forbids bitgen until main review')
text = text.replace("01a144c7-e802-7272-a29d-a8159f5ec84b /root T023", "Codex /root/shape27_delivery T029")
scope = {"__name__": "contour29_writer", "__file__": str(Path(__file__).resolve())}
exec(compile(text, str(SOURCE), "exec"), scope)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--snapshot", type=Path)
    args = parser.parse_args()
    target = args.snapshot or PROJECT
    if args.snapshot:
        target.mkdir(parents=True, exist_ok=False)
    scope["make"](target, bool(args.snapshot))
    manifest = json.loads((target / "inputs.json").read_text(encoding="utf-8"))
    asset = R / "assets/templates/sc520-contour29/contour29-shapes.mem"
    digest = hashlib.sha256(asset.read_bytes()).hexdigest().upper()
    # TD synthesis evaluates readmemh relative to the native stage cwd.
    # All three copies are explicitly bound; no ROM path relies on an old run.
    locations = [target / "contour29-shapes.mem"] + [
        target / f"td_project/camera_to_dsi_display_Runs/{stage}/contour29-shapes.mem"
        for stage in ("syn_1", "phy_1")]
    for location in locations:
        assert not location.exists()
        shutil.copyfile(asset, location)
    manifest["Files"].append(dict(Path=str(asset), SHA256=digest,
                                 Snapshot=str(locations[0]), SnapshotSHA256=digest))
    for location in locations[1:]:
        manifest["Files"].append(dict(Path=str(location.resolve()), SHA256=digest))
    manifest["GeometryROM"] = dict(Source=str(asset), SHA256=digest, Copies=[str(p.resolve()) for p in locations],
                                  Width=16, Words=1024, NativeReadPath="contour29-shapes.mem in each stage cwd")
    (target / "inputs.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(dict(Prepared=str(target), GeometryCopies=len(locations), Hashes=len(manifest["Files"]))))


if __name__ == "__main__":
    main()

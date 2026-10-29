"""Assemble or verify the frozen I0310R4C delivery ZIP without FPGA tools."""
import argparse
import hashlib
import json
import struct
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path, PurePosixPath


COMMIT = "435d5df612d7611e5d97837302b718ea34666e5d"
PINNED = {
    "sc520_i0310r4c_sources.zip": (
        "ADEF639CB90DC41A1C23595ADC2D20978C881C7ADBD7A5D4F6A172312A05E96A", 1464220),
    "firmware/sc520_i0310r4c.bit": (
        "E52E799C15F0507F22E69DEF6036EF218CDBF05EFC47D4EB53D5B1C1FC8DB87B", 1789539),
    "firmware/source-release-manifest.json": (
        "22EC8849CD4E36971A7AC595CC4D2E8DC53667DE0D99E1897737DA26845C81DA", 7886),
    "media/AUDIO.PAK": (
        "1F0DBF08B0215384941E40AE2A4343A0BCD27831A1E177B296B4B014C835C925", 8711680),
    "media/media-manifest.json": (
        "3E02D672688C3C7254A7960C1B6670DBB7AA9113B13ABB53EABC6167512B447C", 38019),
}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest().upper()


def binding(raw):
    return {"SHA256": digest(raw), "Bytes": len(raw)}


def verify_payload(payload, inventory):
    require(inventory["BaselineCommit"] == COMMIT, "Wrong frozen source commit")
    require(set(payload) == set(inventory["Files"]), "Delivery inventory differs")
    for name, raw in payload.items():
        require(binding(raw) == inventory["Files"][name], "Delivery binding mismatch: " + name)
    for name, (expected_sha, expected_bytes) in PINNED.items():
        require(binding(payload[name]) == {"SHA256": expected_sha, "Bytes": expected_bytes},
                "Frozen payload changed: " + name)
    require(struct.unpack_from("<8s6I", payload["media/AUDIO.PAK"]) ==
            (b"KIDPCM01", 2, 48000, 32, 12, 1, 16), "Media format differs from frozen player")
    preparation = json.loads(payload["evidence/path-preparation.json"])
    require(preparation["Prepared"] is True and preparation["ProjectFiles"] == 360
            and preparation["NonPathBytesUnchanged"] is True
            and preparation["PrepareScriptSHA256"] == digest(payload["prepare.py"]),
            "Preparation evidence does not bind the shipped tool")
    require(preparation["Archive"]["SHA256"] == PINNED["sc520_i0310r4c_sources.zip"][0],
            "Preparation evidence does not bind the frozen snapshot")


def verify_archive(path):
    with zipfile.ZipFile(path) as archive:
        require(archive.testzip() is None, "Delivery ZIP CRC failure")
        names = archive.namelist()
        require(len(names) == len({name.casefold() for name in names}), "Duplicate ZIP member")
        for name in names:
            member = PurePosixPath(name)
            require(not member.is_absolute() and ".." not in member.parts
                    and "\\" not in name and ":" not in name, "Unsafe ZIP member")
        inventory = json.loads(archive.read("MANIFEST.json"))
        payload = {name: archive.read(name) for name in names if name != "MANIFEST.json"}
    verify_payload(payload, inventory)
    return {
        "Verified": True, "Archive": str(path.resolve()), **binding(path.read_bytes()),
        "PayloadFiles": len(payload), "BaselineCommit": COMMIT,
        "NativeToolExecuted": False, "HardwareValidated": False,
    }


def assemble(repo, workspace, preparation, output):
    repo = repo.resolve(strict=True)
    workspace = workspace.resolve(strict=True)
    output = output.resolve()
    require(not output.exists(), "Output already exists; use a new delivery filename")
    package = repo / "fpga/package/sc520-i0310r4c"
    release = repo / "fpga/release/sc520-i0310r4c"
    evidence = workspace / "learning/sc520-system-integration"
    sources = {
        "README.md": package / "DELIVERY.md",
        "prepare.py": package / "prepare.py",
        "sc520_i0310r4c_sources.zip": release / "sc520_i0310r4c_sources.zip",
        "firmware/sc520_i0310r4c.bit": release / "sc520_i0310r4c.bit",
        "firmware/source-release-manifest.json": release / "manifest.json",
        "media/AUDIO.PAK": repo / "assets/sc520-system-integration/media-v2/AUDIO.PAK",
        "media/media-manifest.json": repo / "assets/sc520-system-integration/media-v2/media-manifest.json",
        "evidence/software-review.json": evidence / "i0310r4c-software-review-20261028.json",
        "evidence/physical-review.json": evidence / "i0310r4c-physical-candidate-reviewed-20261028.json",
        "evidence/freeze.json": evidence / "frozen-i0310r4c/freeze.json",
        "evidence/github-upload-20261029.json": evidence / "frozen-i0310r4c/github-upload-20261029.json",
        "evidence/path-preparation.json": preparation.resolve(strict=True),
    }
    payload = {name: path.read_bytes() for name, path in sources.items()}
    inventory = {
        "Version": "I0310R4C-delivery-v1",
        "At": datetime.now(timezone(timedelta(hours=8))).isoformat(),
        "Owner": "Codex /root local/01a18534-9515-79d0-8443-217f618fd923",
        "BaselineCommit": COMMIT,
        "FrozenTag": "sc520-i0310r4c-submission-v1",
        "Files": {name: binding(raw) for name, raw in payload.items()},
        "Production": {"ShapeEnable": False, "TrackEnable": True, "CardItems": [10, 11, 12, 13, 14]},
        "Media": {"Version": 2, "SampleRate": 48000, "Slots": 32, "Channels": 1, "Bits": 16},
        "HardwareValidated": False,
        "Notes": [
            "Only prepare.py and the pinned source ZIP are required to materialize a new project.",
            "Historical evidence and media manifests retain provenance paths; they are not runtime dependencies.",
            "Original bit and source ZIP bytes are unchanged. New place/route results are not claimed.",
        ],
    }
    verify_payload(payload, inventory)
    payload["MANIFEST.json"] = (json.dumps(inventory, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, raw in sorted(payload.items()):
            entry = zipfile.ZipInfo(name, date_time=(2026, 10, 29, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, raw)
    for name, path in sources.items():
        require(path.read_bytes() == payload[name], "An assembly input changed: " + name)
    return verify_archive(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", type=Path)
    parser.add_argument("--repo", type=Path)
    parser.add_argument("--workspace", type=Path)
    parser.add_argument("--preparation", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.verify is not None:
        require(all(value is None for value in (args.repo, args.workspace, args.preparation, args.output)),
                "--verify is a separate operation")
        result = verify_archive(args.verify)
    else:
        require(all(value is not None for value in (args.repo, args.workspace, args.preparation, args.output)),
                "Supply --repo, --workspace, --preparation and --output")
        result = assemble(args.repo, args.workspace, args.preparation, args.output)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

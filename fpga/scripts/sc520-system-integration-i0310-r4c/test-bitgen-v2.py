"""Pure bitgen approval and virtual lifecycle tests; never materialize b320."""
import argparse
import copy
import hashlib
import io
import json
import stat
import unittest
from contextlib import ExitStack, redirect_stdout
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

HERE = Path(__file__).absolute().parent
SCRIPT = HERE / "run-bitgen-v2.py"
ORIGINAL = HERE / "run-bitgen.py"
ORIGINAL_SHA = "331A5B05B053FC26F06133F5389F539FB4A621BFCB9BBAC6FCEF426E343BF6F5"


def bind(path, raw=None):
    raw = path.read_bytes() if raw is None else raw
    return {"Path": path.as_posix(), "SHA256": hashlib.sha256(raw).hexdigest().upper(), "Bytes": len(raw)}


def load():
    ns = {"__name__": "bitgen_v2_pure", "__file__": str(SCRIPT)}
    exec(compile(SCRIPT.read_bytes(), str(SCRIPT), "exec"), ns)
    return ns


class BitgenTests(unittest.TestCase):
    def setUp(self):
        self.api = load()
        a = self.api
        self.rows = [bind(HERE / (name + ".json"), name.encode()) for name in ("manifest", "route", "runner", "evidence")]
        self.approval = {"Operation": "I0310R4C candidate bitgen once", "BitgenAllowed": True,
                         "HardwareActionsAllowed": False, "OutputRoot": a["RUN"].as_posix(),
                         "Manifest": self.rows[0], "RouteResult": self.rows[1], "Runner": self.rows[2],
                         "RootCreatorID": a["ROOT_CREATOR_ID"], "RootReviewedCode": True,
                         "RootAcceptedPhysicalEvidence": True, "BudgetSeconds": 600,
                         "AcceptedEvidence": [self.rows[3]]}

    def approve(self, value):
        return self.api["approve"](value, *self.rows[:3])

    def test_approval_requires_exact_scope_and_real_evidence(self):
        self.assertEqual(self.approve(self.approval), [self.rows[3]])
        for field in self.approval:
            wrong = copy.deepcopy(self.approval)
            del wrong[field]
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                self.approve(wrong)
        for value in (None, [], {}, [self.rows[3], self.rows[3]], [{**self.rows[3], "Bytes": 0}],
                      [{**self.rows[3], "Path": (self.api["RUN"] / "circular.json").as_posix()}]):
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                self.approve({**self.approval, "AcceptedEvidence": value})
        for field, value in (("BudgetSeconds", True), ("BudgetSeconds", 601),
                             ("RootCreatorID", "local/old-root"), ("RootReviewedCode", 1),
                             ("HardwareActionsAllowed", True), ("BitgenAllowed", 1)):
            with self.subTest(field=field, value=value), self.assertRaises(RuntimeError):
                self.approve({**self.approval, field: value})

    def test_alias_and_binding_shapes_rejected(self):
        a = self.api
        row = self.rows[3]
        for value in ({**row, "Path": "relative.json"}, {**row, "Path": "E:/x/../x.json"},
                      {**row, "Path": "E:/x.json:stream"}, {**row, "Bytes": True},
                      {**row, "SHA256": "invalid"}, {**row, "Extra": True}):
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                a["validate_row"](value)
        with self.assertRaisesRegex(RuntimeError, "Conflicting"):
            a["unique_rows"]([row, {**row, "Path": row["Path"].upper()}])

    def test_duplicate_and_nonfinite_json(self):
        for raw in ('{"a":1,"a":2}', '{"a":NaN}', '{"a":Infinity}', '[]'):
            with self.subTest(raw=raw), self.assertRaises(RuntimeError):
                self.api["json_document"](raw)

    def test_identity_refuses_hardlinks_and_nonregular_files(self):
        self.assertEqual(self.api["identity"](SCRIPT), bind(SCRIPT))
        for mode, links in ((stat.S_IFREG, 2), (stat.S_IFDIR, 1)):
            with self.subTest(mode=mode, links=links), patch.dict(self.api, no_reparse=lambda p: None), \
                    patch.object(Path, "lstat", lambda p: SimpleNamespace(st_mode=mode, st_nlink=links)), \
                    self.assertRaisesRegex(RuntimeError, "Nonregular or hard-linked"):
                self.api["identity"](SCRIPT)

    def native(self, command):
        return {**{field: True for field in ("RootCreated", "RootResumed", "JobAssignedBeforeResume",
                 "JobMembershipVerified", "ExpectedResumeVerified", "NaturalNativeExit", "TreeCleanVerified")},
                "NativeExit": 0, "TimedOut": False, "TerminationRequested": False, "Error": None,
                "CleanupErrors": [], "StdioUnclosedHandles": [], "FinalAccounting": {"ActiveProcesses": 0},
                "Command": command, "Cwd": self.api["RUN"].as_posix(), "PID": 123,
                "CreationFileTime100ns": 100000000, "ElapsedSeconds": 1.0}

    def test_native_identity_lifecycle_and_budget(self):
        command = ["td", "fixed.tcl"]
        row = self.native(command)
        self.api["native_clean"](row, command, 1.0, {"created": 1, "started": 1})
        for field in row:
            if field == "ElapsedSeconds":
                continue
            wrong = copy.deepcopy(row)
            del wrong[field]
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                self.api["native_clean"](wrong, command, 1.0, {"created": 1, "started": 1})
        for elapsed in (600, 601, -1, float("nan"), True):
            with self.subTest(elapsed=elapsed), self.assertRaises(RuntimeError):
                self.api["native_clean"](row, command, elapsed, {"created": 1, "started": 1})
        with self.assertRaises(RuntimeError):
            self.api["native_clean"](row, command, 1.0, {"created": 0, "started": 1})

    def virtual_execute(self, mutation=None, approval_change=None, preexisting=False):
        a = self.api
        fs, directories, native_calls = {}, set(), []
        helper_raw = a["HELPER"].read_bytes()
        runner_raw = SCRIPT.read_bytes()
        tool_row = {"Path": a["TOOL"].as_posix(), "SHA256": a["FIXED"][a["TOOL"]], "Bytes": 76680976}
        def put(path, raw):
            fs[path] = raw
            return bind(path, raw)
        def document(path, obj):
            return put(path, (json.dumps(obj) + "\n").encode())
        def identity(path, raw=None):
            if path == a["TOOL"]:
                return tool_row
            return bind(path, fs[path] if raw is None else raw)
        source = put(HERE / "virtual-source.v", b"module x; endmodule\n")
        evidence = put(HERE / "virtual-evidence.json", b'{"Accepted": true}\n')
        database = put(a["ROUTE"] / "td/pl_1/camera_to_dsi_display_route.db", b"route database")
        project = put(a["ROUTE"] / "td/pl_1/camera_to_dsi_display.prj", b"project")
        manifest = document(a["MANIFEST"], {"Version": "I0310R4C", "Prepared": True, "Inputs": [source], "Files": {}})
        route = document(a["ROUTE"] / "route-result.json", {"Stage": "route", "ExecutionComplete": True,
            "Failure": None, "ChangedInputs": [], "TimingObservation": {"Confidence": "Routed", "Corners": "Both",
            "NonnegativeUnderCurrentConstraints": True}, "AreaObservation": {"Fits": True},
            "DebuggerMode": "no-chip-debugger", "Database": database,
            "OutputFiles": {"camera_to_dsi_display_route.db": database, "camera_to_dsi_display.prj": project}})
        runner = put(SCRIPT, runner_raw)
        put(a["HELPER"], helper_raw)
        approval_obj = {**self.approval, "Manifest": manifest, "RouteResult": route, "Runner": runner,
                        "Database": database, "AcceptedEvidence": [evidence]}
        if approval_change:
            approval_change(approval_obj)
        approval = document(a["APPROVAL"], approval_obj)
        if preexisting:
            directories.add(a["RUN"])
        class VirtualBytes(io.BytesIO):
            def __init__(self, path):
                super().__init__(); self.path = path
            def close(self):
                if not self.closed:
                    fs[self.path] = self.getvalue()
                super().close()
        class VirtualText(io.StringIO):
            def __init__(self, path, encoding):
                super().__init__(); self.path = path; self.codec = encoding
            def close(self):
                if not self.closed:
                    fs[self.path] = self.getvalue().encode(self.codec)
                super().close()
        def opened(path, mode="r", encoding=None, newline=None):
            self.assertIn(mode, ("x", "xb"))
            if path in fs:
                raise FileExistsError(str(path))
            fs[path] = b""
            return VirtualBytes(path) if mode == "xb" else VirtualText(path, encoding or "utf-8")
        def mkdir(path, **kwargs):
            if path in directories:
                raise FileExistsError(str(path))
            self.assertEqual(path, a["RUN"])
            directories.add(path)
        def owned(command, cwd, stdout, stderr, budget, env, on_started, on_created, wall_deadline):
            native_calls.append(command)
            self.assertEqual(cwd, a["RUN"]); self.assertEqual(budget, 600)
            row = self.native(command)
            on_created(row); on_started(row)
            stdout.write(b"I0310R4C_BITGEN_NATIVE_COMPLETE\n")
            put(cwd / "bitgen.started", b"123\n")
            put(cwd / "bitgen.finished", b"I0310R4C_BITGEN_NATIVE_COMPLETE\n")
            put(cwd / "bitgen-parameters.txt", b"bitgen parameters\n")
            put(cwd / "i0310r4c_candidate.bit", b"candidate bits")
            if mutation:
                mutation(fs, row)
            return row
        def harmless_exec(code, namespace):
            self.assertEqual(namespace["__file__"], a["HELPER"].as_posix())
            namespace["run_owned_process"] = owned
        args = SimpleNamespace(runner_sha=runner["SHA256"], manifest_sha=manifest["SHA256"],
                               route_result_sha=route["SHA256"], approval_sha=approval["SHA256"])
        with ExitStack() as stack:
            stack.enter_context(patch.dict(a, identity=identity, no_reparse=lambda p: None, exec=harmless_exec))
            for name, fn in {"read_bytes": lambda p: fs[p],
                             "read_text": lambda p, encoding="utf-8", errors="strict": fs[p].decode(encoding, errors),
                             "open": opened, "mkdir": mkdir,
                             "stat": lambda p: SimpleNamespace(st_size=len(fs[p])),
                             "is_file": lambda p: p in fs,
                             "rglob": lambda p, pattern: iter(sorted(x for x in fs if x.is_relative_to(p)))}.items():
                stack.enter_context(patch.object(Path, name, fn))
            with redirect_stdout(io.StringIO()):
                rc = a["execute"](args)
        result = json.loads(fs[a["RUN"] / "bitgen-result.json"])
        return rc, result, fs, native_calls, evidence

    def test_virtual_complete_evidence_and_request_protected(self):
        rc, result, fs, calls, evidence = self.virtual_execute()
        self.assertEqual(rc, 0); self.assertEqual(len(calls), 1)
        self.assertTrue(result["BitgenExecutionComplete"])
        self.assertEqual(result["ChangedInputs"], [])
        self.assertEqual(result["InputsBefore"], result["InputsAfter"])
        self.assertIn(evidence, result["InputsBefore"])
        self.assertEqual(result["AcceptedEvidence"], [evidence])
        self.assertEqual(result["RootCreatorID"], self.api["ROOT_CREATOR_ID"])
        paths = {row["Path"] for row in result["InputsBefore"]}
        self.assertIn((self.api["RUN"] / "bitgen-request.json").as_posix(), paths)
        self.assertFalse(result["HardwareValidated"] or result["Downloaded"] or result["FlashWritten"])

    def test_virtual_changed_evidence_and_request_fail(self):
        for target in (HERE / "virtual-evidence.json", self.api["RUN"] / "bitgen-request.json"):
            with self.subTest(target=target):
                rc, result, _, calls, _ = self.virtual_execute(lambda fs, row: fs.__setitem__(target, b"changed"))
                self.assertEqual(rc, 1); self.assertEqual(len(calls), 1)
                self.assertFalse(result["BitgenExecutionComplete"])
                self.assertIn(target.as_posix(), {row["Path"] for row in result["ChangedInputs"]})

    def test_virtual_scope_and_consumed_root_fail_before_native(self):
        with self.assertRaisesRegex(RuntimeError, "database differs"):
            self.virtual_execute(approval_change=lambda d: d.__setitem__("Database", self.rows[3]))
        with self.assertRaises(FileExistsError):
            self.virtual_execute(preexisting=True)

    def test_virtual_missing_empty_unexpected_bits_and_pid(self):
        run = self.api["RUN"]
        variants = [lambda fs, row: fs.__setitem__(run / "i0310r4c_candidate.bit", b""),
                    lambda fs, row: fs.__setitem__(run / "i0310r4c_candidate_compress.bit", b""),
                    lambda fs, row: fs.__setitem__(run / "other.bit", b"x"),
                    lambda fs, row: fs.__setitem__(run / "sub/i0310r4c_candidate.bit", b"x"),
                    lambda fs, row: fs.__setitem__(run / "bitgen.started", b"999\n"),
                    lambda fs, row: row.__setitem__("NativeExit", 1)]
        for index, mutation in enumerate(variants):
            with self.subTest(index=index):
                rc, result, _, calls, _ = self.virtual_execute(mutation)
                self.assertEqual(rc, 1); self.assertFalse(result["BitgenExecutionComplete"])
                self.assertEqual(len(calls), 1)

    def test_literal_scope_and_original_preserved(self):
        self.assertEqual(bind(ORIGINAL)["SHA256"], ORIGINAL_SHA)
        old = {"__name__": "old_bitgen_readonly", "__file__": str(ORIGINAL)}
        exec(compile(ORIGINAL.read_bytes(), str(ORIGINAL), "exec"), old)
        self.assertEqual(self.api["launcher"](), old["launcher"]())
        self.assertEqual(self.api["FIXED"], old["FIXED"])
        self.assertEqual(self.api["SELF"], SCRIPT)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.report.absolute().parent != HERE or args.report.exists():
        parser.error("report must be a new direct member of the owned script directory")
    roots = {name: (load()["EV"] / name).exists() for name in ("j319", "q320", "r320", "u320", "b320")}
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(BitgenTests))
    after = {name: (load()["EV"] / name).exists() for name in roots}
    report = {"At": datetime.now(timezone(timedelta(hours=8))).isoformat(),
              "Owner": "Codex /root/export_review; parent local/01a18186-78f4-7101-93d9-0f77a7041af9",
              "PurePassed": result.wasSuccessful() and roots == after, "Tests": result.testsRun,
              "Failures": len(result.failures), "Errors": len(result.errors),
              "FailedTests": [{"Test": str(test), "Traceback": trace} for test, trace in result.failures + result.errors],
              "Inputs": [bind(p) for p in (SCRIPT, Path(__file__), ORIGINAL)],
              "RootsBefore": roots, "RootsAfter": after, "NativeExecuted": False,
              "ActualB320Materialized": False, "BitgenAllowed": False,
              "Limit": "Only pure validation and in-memory fake filesystem/native lifecycle. No real prepare, bitgen, TD or hardware."}
    with args.report.open("x", encoding="utf-8", newline="\n") as out:
        json.dump(report, out, ensure_ascii=True, indent=2); out.write("\n")
    print(json.dumps({"Passed": report["PurePassed"], "Tests": result.testsRun,
                      "Failures": len(result.failures), "Errors": len(result.errors), "Report": bind(args.report)}))
    return 0 if report["PurePassed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

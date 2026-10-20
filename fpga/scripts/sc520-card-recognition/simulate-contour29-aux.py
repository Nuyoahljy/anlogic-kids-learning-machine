"""Extend system input selection without changing earlier run-bound runners."""
from pathlib import Path
import ast

SOURCE = Path(__file__).with_name("simulate-contour29-system.py")
tree = ast.parse(SOURCE.read_text(encoding="utf-8"))
text = next(ast.literal_eval(node.value) for node in tree.body
            if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "adapted" for t in node.targets))
text = text.replace('    refs += list((R / "evidence/sc520-color-integration/fixtures").glob("*.mem"))',
                    '    refs += [p for p in (R / "evidence/sc520-color-integration/fixtures").glob("*.mem") if args.test != "render" or not p.name.startswith("golden-")]\n    refs += [S / "simulate-contour29-system.py"]')
text = text.replace("+CASE_FILE=cases.txt", '+CASE_FILE={"truth-cases.txt" if args.legacy else "cases.txt"}')
# The system TB reads a fixed cases.txt; the snapshot selects the true-label
# list for the legacy run without changing the immutable source case files.
text = text.replace('    simulator = Path("D:/modeltech64_10.7/win64/vsim.exe")',
                    '''    if args.legacy and (snap / "truth-cases.txt").exists():
        (snap / "cases.txt").write_bytes((snap / "truth-cases.txt").read_bytes())
        items = [item for item in items if Path(item["Path"]).name != "cases.txt"]
        for item in items:
            if Path(item["Path"]).name == "truth-cases.txt":
                item["Snapshot"] = str(snap / "cases.txt")
    simulator = Path("D:/modeltech64_10.7/win64/vsim.exe")''')
scope = {"__name__": "__main__", "__file__": str(Path(__file__).resolve())}
exec(compile(text, str(SOURCE), "exec"), scope)

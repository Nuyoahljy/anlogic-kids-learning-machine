"""Independent continuous-input entry point; prior runners remain immutable."""
from pathlib import Path
SOURCE = Path(__file__).with_name("simulate-contour29-aux.py")
text = SOURCE.read_text(encoding="utf-8")
needle = 'scope = {"__name__": "__main__", "__file__": str(Path(__file__).resolve())}'
assert text.count(needle) == 1
extra = '''text = text.replace('choices=["scene", "scenes",', 'choices=["scene", "fps", "scenes",')
text = text.replace('refs += [S / "simulate-contour29-system.py"]', 'refs += [S / "simulate-contour29-system.py", S / "simulate-contour29-aux.py"]')
'''
text = text.replace(needle, extra + needle)
scope = {"__name__": "__main__", "__file__": str(Path(__file__).resolve())}
exec(compile(text, str(SOURCE), "exec"), scope)

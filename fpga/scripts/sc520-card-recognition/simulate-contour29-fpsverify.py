"""Check an explicit supported-rate window and the unchanged overspeed guard."""
from pathlib import Path
SOURCE = Path(__file__).with_name("simulate-contour29-aux.py")
text = SOURCE.read_text(encoding="utf-8")
needle = 'scope = {"__name__": "__main__", "__file__": str(Path(__file__).resolve())}'
extra = '''text = text.replace('choices=["scene", "scenes",', 'choices=["scene", "fpsverify", "scenes",')
text = text.replace('refs += [S / "simulate-contour29-system.py"]', 'refs += [S / "simulate-contour29-system.py", S / "simulate-contour29-aux.py"]')
'''
assert text.count(needle) == 1
text = text.replace(needle, extra + needle)
exec(compile(text, str(SOURCE), "exec"), {"__name__": "__main__", "__file__": str(Path(__file__).resolve())})

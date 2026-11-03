from pathlib import Path

source = Path(__file__).resolve().parent.parent / 'remaining/capture.py'
program = source.read_text().replace("(OUTPUT.parent / 'android/stop-audit.json')", "(OUTPUT.parent / 'remaining/final-retained.json')").replace('all69Unchanged', 'all70Unchanged').replace('original69Unchanged', 'original70Unchanged')
exec(compile(program, str(source), 'exec'))

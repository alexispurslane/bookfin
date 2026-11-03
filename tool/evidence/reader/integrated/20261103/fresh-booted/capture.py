from pathlib import Path

source = Path(__file__).resolve().parent.parent / 'remaining/capture.py'
program = source.read_text().replace("'emulator-5554'", "'emulator-5556'")
program = program.replace("json.loads((OUTPUT.parent / 'android/stop-audit.json').read_text())['actions']", '[]')
program = program.replace('all69Unchanged', 'emptyBaseline').replace('original69Unchanged', 'emptyBaseline')
exec(compile(program, str(source), 'exec'))

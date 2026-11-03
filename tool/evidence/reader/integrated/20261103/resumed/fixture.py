from pathlib import Path

source = Path.cwd() / 'tool/evidence/reader/integrated/20261103/remaining/fixture.py'
program = source.read_text().replace("PRIVATE = ROOT / '.cache/remaining-acceptance'", "PRIVATE = ROOT / '.cache/resumed-acceptance'")
exec(compile(program, str(source), 'exec'))

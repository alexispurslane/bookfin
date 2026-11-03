from pathlib import Path

source = Path(__file__).resolve().parent.parent / 'remaining/server_readback.py'
program = source.read_text().replace('.cache/remaining-acceptance', '.cache/resumed-acceptance')
program = program.replace("'stop-server.json'", "f'{sys.argv[1]}.json'")
exec(compile(program, str(source), 'exec'))

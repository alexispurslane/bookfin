from pathlib import Path
import sys

source = Path(__file__).resolve().parent.parent / 'remaining/server_readback.py'
program = source.read_text().replace('.cache/remaining-acceptance', '.cache/fresh-booted-acceptance')
program = program.replace("'stop-server.json'", "f'{sys.argv[1]}.json'")
if len(sys.argv) > 2:
    assert sys.argv[2] in ('alice', 'bob')
    program = program.replace("accounts['alice']", f"accounts['{sys.argv[2]}']")
    program = program.replace('accounts["alice"]', f'accounts["{sys.argv[2]}"]')
exec(compile(program, str(source), 'exec'))

from pathlib import Path

source = Path.cwd() / 'tool/evidence/reader/integrated/20261103/remaining/fixture.py'
program = source.read_text().replace('.cache/remaining-acceptance', '.cache/fresh-booted-acceptance')
program = program.replace('800 0 0 343 {column * 800}', '1400 0 0 343 {column * 800 + 100}').replace('column in range(2)', 'column in range(1)')
program = program.replace('Acceptance dense English', 'Fresh single English').replace('Acceptance blank', 'Fresh blank')
program = program.replace("'densePage'", "'singleColumnPage'").replace("'imageDraws': 22", "'imageDraws': 11").replace("'referenceWords': 814", "'referenceWords': 407")
exec(compile(program, str(source), 'exec'))

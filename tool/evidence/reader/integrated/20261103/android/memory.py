import json
from pathlib import Path
import re
import subprocess
import time


samples = []
started = time.monotonic()
for sample_number in range(60):
    output = subprocess.check_output(['adb', '-s', 'emulator-5554', 'shell', 'dumpsys', 'meminfo', 'dev.bookfin.bookfin'], text=True)
    pss = re.search(r'TOTAL PSS:\s+(\d+)', output)
    rss = re.search(r'TOTAL RSS:\s+(\d+)', output)
    samples.append({'seconds': round(time.monotonic() - started, 3), 'pssKiB': int(pss[1]) if pss else None,
                    'rssKiB': int(rss[1]) if rss else None})
    time.sleep(0.5)
result = {'samples': samples, 'limit': 'Android dumpsys samples, not continuous or allocator peak memory',
          'maximumSampledPssKiB': max(sample['pssKiB'] or 0 for sample in samples),
          'maximumSampledRssKiB': max(sample['rssKiB'] or 0 for sample in samples)}
(Path(__file__).resolve().parent / 'first-ocr-memory.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({key: value for key, value in result.items() if key != 'samples'}))

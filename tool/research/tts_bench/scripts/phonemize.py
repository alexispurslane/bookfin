"""Turn each line of a text file into espeak-ng IPA, one line out per line in.

Usage: python3 -I phonemize.py IN.txt OUT.txt [MAX_LINES]
The phone run feeds these phonemes to Kokoro and Kitten, so the phone
measures the model alone, as a Bookfin-owned front end would. espeak-ng
runs only here on the Mac. espeak-ng prints one line per clause and drops
punctuation, so the clauses are joined with ", " and the sentence's final
mark is put back, which keeps Kokoro's pauses.
"""
import subprocess
import sys

src, dst = sys.argv[1], sys.argv[2]
limit = int(sys.argv[3]) if len(sys.argv) > 3 else None
lines = [l.strip() for l in open(src) if l.strip()][:limit]
out = []
for line in lines:
    ipa = subprocess.run(
        ["espeak-ng", "-q", "--ipa", "-v", "en-us"],
        input=line, capture_output=True, text=True, check=True,
    ).stdout
    clauses = [c.strip() for c in ipa.splitlines() if c.strip()]
    end = line.rstrip("\"'”’)")[-1:]
    out.append(", ".join(clauses) + (end if end in ".!?" else "."))
with open(dst, "w") as f:
    f.write("\n".join(out) + "\n")
print(len(out), "lines")

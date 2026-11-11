# Tool code for the boo-z3is design measurement, not part of Bookfin. Fetches LibriVox's public
# section lists (title, playtime, readers) for works in the EPUB corpus.
import json, sys, time, urllib.parse, urllib.request, pathlib
out = pathlib.Path(sys.argv[1])
works = {
  'moby-dick': ('Moby Dick', 'Melville'),
  'pride-and-prejudice': ('Pride and Prejudice', 'Austen'),
  'frankenstein': ('Frankenstein', 'Shelley'),
  'alice': ("Alice's Adventures in Wonderland", 'Carroll'),
  'christmas-carol': ('Christmas Carol', 'Dickens'),
  'sherlock-holmes': ('Adventures of Sherlock Holmes', 'Doyle'),
  'tale-of-two-cities': ('Tale of Two Cities', 'Dickens'),
  'emma': ('Emma', 'Austen'),
  'jane-eyre': ('Jane Eyre', 'Bront'),
  'wuthering-heights': ('Wuthering Heights', 'Bront'),
  'huckleberry-finn': ('Adventures of Huckleberry Finn', 'Twain'),
  'time-machine': ('Time Machine', 'Wells'),
  'dracula': ('Dracula', 'Stoker'),
  'heart-of-darkness': ('Heart of Darkness', 'Conrad'),
  'treasure-island': ('Treasure Island', 'Stevenson'),
  'great-gatsby': ('Great Gatsby', 'Fitzgerald'),
  'wind-in-the-willows': ('Wind in the Willows', 'Grahame'),
  'jungle-book': ('Jungle Book', 'Kipling'),
  'walden': ('Walden', 'Thoreau'),
  'war-of-the-worlds': ('War of the Worlds', 'Wells'),
  'dorian-gray': ('Picture of Dorian Gray', 'Wilde'),
  'peter-pan': ('Peter Pan', 'Barrie'),
  'wizard-of-oz': ('Wonderful Wizard of Oz', 'Baum'),
  'looking-glass': ('Through the Looking-Glass', 'Carroll'),
  'metamorphosis': ('Metamorphosis', 'Kafka'),
  'crime-and-punishment': ('Crime and Punishment', 'Dostoyevsky'),
  'mrs-dalloway': ('Mrs. Dalloway', 'Woolf'),
  'origin-of-species': ('Origin of Species', 'Darwin'),
  'bleak-house': ('Bleak House', 'Dickens'),
}
for key, (title, author) in works.items():
    target = out / f'{key}.json'
    if target.exists():
        continue
    query = urllib.parse.urlencode({'title': '^' + title, 'extended': 1, 'format': 'json', 'limit': 20})
    url = f'https://librivox.org/api/feed/audiobooks/?{query}'
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'curl/8.7.1'}), timeout=40) as response:
            data = json.load(response)
    except Exception as error:
        print(key, 'failed', error)
        continue
    books = [b for b in data.get('books', [])
             if any(author.lower() in (a.get('last_name', '') + a.get('first_name', '')).lower()
                    for a in b.get('authors', []))]
    keep = [{
        'id': b['id'], 'title': b['title'], 'language': b.get('language'),
        'totaltimesecs': b.get('totaltimesecs'),
        'sections': [{'n': s.get('section_number'), 'title': s.get('title'),
                      'seconds': int(s.get('playtime') or 0),
                      'readers': [r.get('reader_id') for r in s.get('readers', [])]}
                     for s in b.get('sections', [])],
    } for b in books]
    target.write_text(json.dumps(keep))
    print(key, len(keep), [len(b['sections']) for b in keep])
    time.sleep(1)

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import xml.etree.ElementTree as ElementTree
import zipfile
import posixpath


ROOT = Path(__file__).resolve().parents[3]
SELECTED = {
    "prose": "se-pride-and-prejudice",
    "long": "se-moby-dick",
    "illustrated": "se-alices-adventures-in-wonderland",
}


def copy_tree(source, target):
    def copy_file(original, destination):
        destination = Path(destination)
        if destination.exists():
            destination.chmod(0o644)
        shutil.copyfile(original, destination)
        destination.chmod(0o644)

    shutil.copytree(source, target, dirs_exist_ok=True, copy_function=copy_file)


def describe(path):
    with zipfile.ZipFile(path) as archive:
        container = ElementTree.fromstring(archive.read("META-INF/container.xml"))
        package_path = next(node.attrib["full-path"] for node in container.iter()
                            if node.tag.endswith("}rootfile"))
        package = ElementTree.fromstring(archive.read(package_path))
        manifest = {node.attrib["id"]: node.attrib for node in package.iter()
                    if node.tag.endswith("}item")}
        titles = {}
        for item in manifest.values():
            if "nav" not in item.get("properties", "").split():
                continue
            nav_path = posixpath.normpath(posixpath.join(posixpath.dirname(package_path), item["href"]))
            navigation = ElementTree.fromstring(archive.read(nav_path))
            for link in navigation.iter():
                if link.tag.endswith("}a") and "href" in link.attrib:
                    destination = posixpath.normpath(posixpath.join(posixpath.dirname(nav_path), link.attrib["href"].split("#")[0]))
                    titles.setdefault(destination, " ".join(" ".join(link.itertext()).split()))
        sections = []
        for node in package.iter():
            if not node.tag.endswith("}itemref"):
                continue
            item = manifest[node.attrib["idref"]]
            section_path = posixpath.normpath(posixpath.join(posixpath.dirname(package_path), item["href"]))
            document = ElementTree.fromstring(archive.read(section_path))
            body = next((element for element in document.iter() if element.tag.endswith("}body")), document)
            text = " ".join(" ".join(body.itertext()).split())
            headings = [" ".join(" ".join(element.itertext()).split()) for element in body.iter()
                        if element.tag.rsplit("}", 1)[-1] in ("h1", "h2", "h3")]
            sections.append({"index": len(sections), "href": item["href"], "path": section_path,
                             "characters": len(text), "heading": " ".join(headings),
                             "toc_title": titles.get(section_path),
                             "text_prefix": text[:240],
                             "images": sum(element.tag.rsplit("}", 1)[-1] in ("img", "image") for element in body.iter())})
    return sections


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--sources", type=Path, required=True)
    args = parser.parse_args()
    assets = ROOT / ".cache/epub-engines/assets"
    assets.mkdir(parents=True, exist_ok=True)
    corpus = {entry["id"]: entry for entry in json.loads((ROOT / "tool/reader/epub_corpus.json").read_text())["books"]}
    books = {}
    for name, identity in SELECTED.items():
        entry = corpus[identity]
        original = args.corpus / f"{identity}.epub"
        digest = hashlib.sha256(original.read_bytes()).hexdigest()
        if digest != entry["sha256"]:
            raise ValueError(f"{identity}: public corpus digest mismatch; do not replace the pinned corpus")
        sections = describe(original)
        candidates = [section for section in sections if section["characters"] >= 5000]
        target = (max(candidates, key=lambda section: section["characters"]) if name == "long" else
                  next(section for section in candidates if name != "illustrated" or section["images"]))
        books[name] = {**entry, "file": f"{name}.epub", "sections": sections, "target": target,
                       "section_count": len(sections), "actual_bytes": original.stat().st_size}
        shutil.copyfile(original, assets / f"{name}.epub")
    shutil.copyfile(ROOT / "assets/fonts/SourceSerif4.ttf", assets / "SourceSerif4.ttf")
    shutil.copyfile(ROOT / "assets/fonts/OFL-Source-Serif-4.txt", assets / "OFL-Source-Serif-4.txt")
    copy_tree(args.sources / "web", assets / "web")
    copy_tree(args.sources / "ko/data", assets / "ko-data")
    library_directory = ROOT / ".cache/epub-engines/jni/arm64-v8a"
    library_directory.mkdir(parents=True, exist_ok=True)
    for library in (args.sources / "native").glob("*.so"):
        shutil.copyfile(library, library_directory / library.name)
    manifest = {"books": books, "viewport_css_px": [360, 640], "font_css_px": 18,
                "font_sha256": hashlib.sha256((assets / "SourceSerif4.ttf").read_bytes()).hexdigest(),
                "font_file": "SourceSerif4.ttf", "sources": str(args.sources),
                "bookfin_commit": "6ba37d9a4a23be07f857d369da73115fedcc53fb",
                "koreader_release": "v2026.07.1", "koreader_base": "6e4bc81af4e04f78d81677a323a780a71b29702a",
                "koreader_crengine": "74bd5a1e2b924bced7513f39562f8fb95d7138e5",
                "epubjs": "0.3.93", "jszip": "3.10.1"}
    (assets / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (Path(__file__).parent / "evidence/corpus.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({name: {"sha256": entry["sha256"], "section_count": entry["section_count"],
                              "target": entry["target"]} for name, entry in books.items()}, indent=2))


if __name__ == "__main__":
    main()

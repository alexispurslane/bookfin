import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile


ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "plugin/Bookfin.Storage/Bookfin.Storage.csproj"
SOURCES = (
    "plugin/Bookfin.Storage/Bookfin.Storage.csproj",
    "plugin/Bookfin.Storage/Directory.Build.props",
    "plugin/Bookfin.Storage/Plugin.cs",
    "plugin/Bookfin.Storage/ObjectStore.cs",
    "plugin/Bookfin.Storage/StorageController.cs",
    "plugin/Bookfin.Storage/README.md",
    "tool/plugin/package.py",
    "tool/research/sync/flake.nix",
    "tool/research/sync/flake.lock",
    "tool/research/sync/sources.json",
)


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def digest(contents):
    return hashlib.sha256(contents).hexdigest()


def metadata():
    version = ET.parse(PROJECT).findtext("PropertyGroup/Version") + ".0"
    return {
        "name": "Bookfin Storage", "guid": "55fb5a92-7fbd-411c-9838-6ee4c88d168b",
        "version": version, "targetAbi": "12.0.0.0", "status": "Active",
        "description": "Private per-user immutable storage for Bookfin personal records",
        "owner": "Bookfin",
    }


def assemble(dll, sources, runtime):
    contents = {"Bookfin.Storage.dll": dll, "meta.json": encoded(metadata())}
    contents["manifest.json"] = encoded({
        "format": 1, "api": "/BookfinStorage/v1/objects",
        "additiveApi": "/BookfinStorage/v2/objects", "database": "bookfin-storage-v1.sqlite",
        "plugin": metadata(), "runtime": runtime,
        "sourceSha256": {name: digest(payload) for name, payload in sources.items()},
        "filesSha256": {name: digest(payload) for name, payload in contents.items()},
        "status": "Local deployment candidate; not a published or signed release",
    })
    return contents


def write_archive(destination, contents):
    with zipfile.ZipFile(destination, "w") as archive:
        for name, payload in sorted(contents.items()):
            entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, payload, compress_type=zipfile.ZIP_STORED)


def compile_project(project, destination, intermediates, server):
    subprocess.run([
        "dotnet", "build", str(project), "-c", "Release", "--nologo", "--disable-build-servers",
        "-p:JellyfinDir=" + str(server), "-p:BaseIntermediateOutputPath=" + str(intermediates) + "/",
        "-p:PathMap=" + str(project.parent) + "=/_/Bookfin.Storage",
        "-o", str(destination),
    ], cwd=ROOT, check=True)
    return destination / "Bookfin.Storage.dll"


def build(destination):
    if os.environ.get("BOOKFIN_SYNC_SHELL") != "1":
        raise RuntimeError("Run through nix develop ./tool/research/sync")
    server = Path(os.environ["BOOKFIN_SYNC_SERVER"])
    sdk = subprocess.check_output(["dotnet", "--version"], text=True).strip()
    if sdk != "10.0.401":
        raise RuntimeError("The package requires the pinned SDK 10.0.401")
    pins = json.loads((ROOT / "tool/research/sync/sources.json").read_text())
    if digest((server / "jellyfin.dll").read_bytes()) != pins["jellyfin"]["binaryDllSha256"]:
        raise RuntimeError("The server assembly does not match the pinned Jellyfin archive")
    references = ["jellyfin", "MediaBrowser.Common", "MediaBrowser.Controller", "MediaBrowser.Model",
                  "Jellyfin.Api", "Microsoft.Data.Sqlite"]
    runtime = {
        "referenceServerVersion": "12.4.0", "sdk": sdk, "buildHost": "aarch64-darwin",
        "serverArchive": pins["jellyfin"]["binaryArchiveUrl"],
        "serverArchiveHash": pins["jellyfin"]["binaryArchiveHash"],
        "referenceAssemblySha256": {name + ".dll": digest((server / (name + ".dll")).read_bytes())
                                    for name in references},
    }
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="build-", dir=destination) as temporary:
        work = Path(temporary)
        dll = compile_project(PROJECT, work / "out", work / "obj", server).read_bytes()
    sources = {name: (ROOT / name).read_bytes() for name in SOURCES}
    contents = assemble(dll, sources, runtime)
    stem = "Bookfin.Storage_" + metadata()["version"]
    archive = destination / (stem + ".zip")
    source_archive = destination / (stem + ".sources.zip")
    write_archive(archive, contents)
    write_archive(source_archive, sources)
    (destination / (stem + ".sha256")).write_text("".join(
        digest(path.read_bytes()) + "  " + path.name + "\n" for path in (archive, source_archive)
    ))
    print(json.dumps({"package": archive.name, "sha256": digest(archive.read_bytes())}))
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Build the local Bookfin Storage deployment candidate")
    parser.add_argument("--output", type=Path, default=ROOT / ".cache/plugin/package")
    arguments = parser.parse_args()
    build(arguments.output.resolve())

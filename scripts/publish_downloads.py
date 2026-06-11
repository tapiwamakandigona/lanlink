#!/usr/bin/env python3
"""Publish release binaries to the tapiwa.me downloads bucket on Appwrite.

The downloads page (tapiwa.me/lanlink/downloads.html) links to *fixed*
Appwrite file IDs, so publishing a release means replacing the contents
behind each ID. Appwrite has no in-place overwrite: we delete the old file
and re-create it under the same ID (with public read), retrying on flakes.

Usage:
    APPWRITE_API_KEY=... python scripts/publish_downloads.py <artifacts_dir>

The artifacts dir is scanned recursively; any asset that matches a known
pattern is published. Missing assets are skipped with a warning so a
platform can be dropped from a release without breaking the pipeline.
"""

import fnmatch
import os
import sys
import time
from pathlib import Path

from appwrite.client import Client
from appwrite.input_file import InputFile
from appwrite.permission import Permission
from appwrite.role import Role
from appwrite.services.storage import Storage

ENDPOINT = "https://fra.cloud.appwrite.io/v1"
PROJECT_ID = "69e62515000e9e781653"
BUCKET_ID = "downloads"

# glob (case-insensitive, matched against the bare filename) -> fixed file ID
ASSET_MAP = [
    ("*universal.apk", "lanlink-android-universal"),
    ("*arm64-v8a.apk", "lanlink-android-arm64"),
    ("*armeabi-v7a.apk", "lanlink-android-armeabi"),
    ("*x86_64.apk", "lanlink-android-x64"),
    ("*setup.exe", "lanlink-windows"),
    ("*.dmg", "lanlink-macos"),
    ("*.ipa", "lanlink-ios"),
    ("*.appimage", "lanlink-linux"),
    ("*linux-x64.tar.gz", "lanlink-linux-targz"),
]

RETRIES = 3


def find_assets(root: Path) -> dict[str, Path]:
    """Map fixed file IDs to local asset paths found under *root*."""
    found: dict[str, Path] = {}
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        name = path.name.lower()
        for pattern, file_id in ASSET_MAP:
            if fnmatch.fnmatch(name, pattern) and file_id not in found:
                found[file_id] = path
    return found


def publish(storage: Storage, file_id: str, path: Path) -> None:
    size_mb = path.stat().st_size / 1e6
    print(f"-> {file_id}  ({path.name}, {size_mb:.1f} MB)")
    try:
        storage.delete_file(bucket_id=BUCKET_ID, file_id=file_id)
    except Exception as e:  # noqa: BLE001 - missing file is fine
        print(f"   (no previous file deleted: {e})")
    last = None
    for attempt in range(1, RETRIES + 1):
        try:
            storage.create_file(
                bucket_id=BUCKET_ID,
                file_id=file_id,
                file=InputFile.from_path(str(path)),
                permissions=[Permission.read(Role.any())],
            )
            print("   published")
            return
        except Exception as e:  # noqa: BLE001
            last = e
            print(f"   attempt {attempt}/{RETRIES} failed: {e}")
            time.sleep(5 * attempt)
    raise RuntimeError(f"could not publish {file_id}: {last}")


def main() -> int:
    api_key = os.environ.get("APPWRITE_API_KEY")
    if not api_key:
        print("APPWRITE_API_KEY is not set", file=sys.stderr)
        return 1
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "artifacts")
    if not root.is_dir():
        print(f"artifacts dir not found: {root}", file=sys.stderr)
        return 1

    client = Client().set_endpoint(ENDPOINT).set_project(PROJECT_ID).set_key(api_key)
    storage = Storage(client)

    assets = find_assets(root)
    missing = [fid for _, fid in ASSET_MAP if fid not in assets]
    if not assets:
        print("no matching assets found — nothing to publish", file=sys.stderr)
        return 1
    for file_id, path in assets.items():
        publish(storage, file_id, path)
    for fid in missing:
        print(f"!! skipped (no matching asset in this release): {fid}")
    print(f"done: {len(assets)} published, {len(missing)} skipped")
    return 0


if __name__ == "__main__":
    sys.exit(main())

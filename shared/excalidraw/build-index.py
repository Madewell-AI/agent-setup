#!/usr/bin/env python3
"""
Build the item-index.json from all .excalidrawlib files in the libraries/ directory.

Run this after adding or updating library files:
  python3 build-index.py

Outputs: libraries/item-index.json
"""

import json
import os
import glob

LIBRARIES_DIR = os.path.join(os.path.dirname(__file__), "libraries")
OUTPUT_PATH = os.path.join(LIBRARIES_DIR, "item-index.json")


def main():
    index = {}
    lib_files = sorted(glob.glob(os.path.join(LIBRARIES_DIR, "*.excalidrawlib")))

    for lib_path in lib_files:
        lib_name = os.path.basename(lib_path).replace(".excalidrawlib", "")

        with open(lib_path) as f:
            data = json.load(f)

        items = data.get("libraryItems", [])
        for i, item in enumerate(items):
            name = item.get("name", f"item-{i}")
            key = f"{lib_name}/{name}"
            index[key] = {
                "library": lib_name,
                "name": name,
                "elementCount": len(item.get("elements", [])),
                "index": i,
            }

    with open(OUTPUT_PATH, "w") as f:
        json.dump(index, f, indent=2)

    total = len(index)
    libs = len(lib_files)
    print(f"Built index: {total} items from {libs} libraries")
    print(f"Output: {OUTPUT_PATH}")


if __name__ == "__main__":
    main()

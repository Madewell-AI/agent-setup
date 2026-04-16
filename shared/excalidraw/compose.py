#!/usr/bin/env python3
"""
Compose Excalidraw drawings using library items with proper normalization.

Usage:
  python3 compose.py <library>/<item-name> [--x X] [--y Y] [--size S]
  python3 compose.py search <query>
  python3 compose.py list
  python3 compose.py info <library>/<item-name>

Examples:
  python3 compose.py aws-serverless/Lambda --x 100 --y 200 --size 80
  python3 compose.py it-logos/Docker --x 300 --y 100 --size 60
  python3 compose.py search "docker"
"""

import json
import sys
import os
import argparse
import copy
import uuid

LIBRARIES_DIR = os.path.join(os.path.dirname(__file__), "libraries")
INDEX_PATH = os.path.join(LIBRARIES_DIR, "item-index.json")

DEFAULT_ICON_SIZE = 80


def load_index():
    with open(INDEX_PATH) as f:
        return json.load(f)


def load_item(library: str, index: int):
    lib_path = os.path.join(LIBRARIES_DIR, f"{library}.excalidrawlib")
    with open(lib_path) as f:
        data = json.load(f)
    return data["libraryItems"][index]


def search_items(query: str):
    index = load_index()
    query_lower = query.lower()
    results = []
    for key, val in index.items():
        if query_lower in key.lower() or query_lower in val["name"].lower():
            results.append({"key": key, **val})
    return results


def get_item_elements(key: str):
    """Get elements for a library item by key (e.g., 'aws-serverless/Lambda')."""
    index = load_index()
    if key not in index:
        matches = [k for k in index if key.lower() in k.lower()]
        if matches:
            key = matches[0]
        else:
            raise KeyError(f"Item '{key}' not found. Use 'search' command.")

    entry = index[key]
    item = load_item(entry["library"], entry["index"])
    return item["elements"]


def compute_bounding_box(elements):
    """Compute true bounding box, accounting for points arrays on lines/arrows."""
    min_x = float("inf")
    min_y = float("inf")
    max_x = float("-inf")
    max_y = float("-inf")

    for e in elements:
        ex, ey = e.get("x", 0), e.get("y", 0)

        if "points" in e and e.get("type") in ("line", "arrow", "freedraw"):
            for p in e["points"]:
                px, py = ex + p[0], ey + p[1]
                min_x = min(min_x, px)
                min_y = min(min_y, py)
                max_x = max(max_x, px)
                max_y = max(max_y, py)
        else:
            w = e.get("width", 0)
            h = e.get("height", 0)
            x1, x2 = (ex, ex + w) if w >= 0 else (ex + w, ex)
            y1, y2 = (ey, ey + h) if h >= 0 else (ey + h, ey)
            min_x = min(min_x, x1)
            min_y = min(min_y, y1)
            max_x = max(max_x, x2)
            max_y = max(max_y, y2)

    return min_x, min_y, max_x - min_x, max_y - min_y


def normalize_elements(elements, target_x=0, target_y=0, target_size=DEFAULT_ICON_SIZE):
    """
    Normalize library item elements to fit within target_size px,
    preserving aspect ratio and scaling ALL relevant properties.
    """
    if not elements:
        return elements

    elements = copy.deepcopy(elements)

    bb_x, bb_y, bb_w, bb_h = compute_bounding_box(elements)

    if bb_w == 0 and bb_h == 0:
        return elements

    scale = target_size / max(bb_w, bb_h) if max(bb_w, bb_h) > 0 else 1.0

    id_map = {}
    for e in elements:
        old_id = e.get("id", "")
        new_id = str(uuid.uuid4())[:8]
        id_map[old_id] = new_id

    for e in elements:
        old_id = e.get("id", "")
        e["id"] = id_map.get(old_id, old_id)

        e["x"] = target_x + (e["x"] - bb_x) * scale
        e["y"] = target_y + (e["y"] - bb_y) * scale

        if "width" in e:
            e["width"] = e["width"] * scale
        if "height" in e:
            e["height"] = e["height"] * scale

        if "points" in e:
            e["points"] = [[p[0] * scale, p[1] * scale] for p in e["points"]]

        if "strokeWidth" in e:
            e["strokeWidth"] = max(0.5, e["strokeWidth"] * scale)

        if "fontSize" in e:
            e["fontSize"] = max(6, e["fontSize"] * scale)

        if "groupIds" in e and e["groupIds"]:
            e["groupIds"] = [
                id_map.get(gid, str(uuid.uuid5(uuid.NAMESPACE_DNS, gid))[:8])
                for gid in e["groupIds"]
            ]

        if "boundElements" in e and e["boundElements"]:
            e["boundElements"] = [
                {**be, "id": id_map.get(be.get("id", ""), be.get("id", ""))}
                for be in e["boundElements"]
            ]

        if "containerId" in e and e["containerId"]:
            e["containerId"] = id_map.get(e["containerId"], e["containerId"])

        if "startBinding" in e and e["startBinding"]:
            sb = e["startBinding"]
            if "elementId" in sb:
                sb["elementId"] = id_map.get(sb["elementId"], sb["elementId"])
        if "endBinding" in e and e["endBinding"]:
            eb = e["endBinding"]
            if "elementId" in eb:
                eb["elementId"] = id_map.get(eb["elementId"], eb["elementId"])

    return elements


def main():
    parser = argparse.ArgumentParser(description="Compose Excalidraw library items")
    parser.add_argument("command", help="Item key (lib/name) or 'search' or 'list'")
    parser.add_argument("query", nargs="?", default="", help="Search query")
    parser.add_argument("--x", type=float, default=0, help="X position")
    parser.add_argument("--y", type=float, default=0, help="Y position")
    parser.add_argument("--size", type=float, default=DEFAULT_ICON_SIZE, help="Target size in px (default 80)")
    args = parser.parse_args()

    if args.command == "search":
        results = search_items(args.query)
        for r in results[:30]:
            print(f"  {r['key']}  ({r['elementCount']} elements)")
        if len(results) > 30:
            print(f"  ... and {len(results) - 30} more")
        return

    if args.command == "list":
        index = load_index()
        libs = {}
        for k, v in index.items():
            libs.setdefault(v["library"], []).append(v["name"])
        for lib in sorted(libs.keys()):
            print(f"\n{lib} ({len(libs[lib])} items):")
            for name in libs[lib]:
                print(f"  - {name}")
        return

    if args.command == "info":
        elements = get_item_elements(args.query)
        bb_x, bb_y, bb_w, bb_h = compute_bounding_box(elements)
        print(f"  Native size: {bb_w:.0f} x {bb_h:.0f} px")
        print(f"  Elements: {len(elements)}")
        types = set(e.get("type") for e in elements)
        print(f"  Types: {', '.join(sorted(types))}")
        return

    elements = get_item_elements(args.command)
    elements = normalize_elements(elements, args.x, args.y, args.size)
    print(json.dumps(elements))


if __name__ == "__main__":
    main()

import fs from "fs/promises";
import path from "path";

const LIBRARIES_DIR = path.join(process.cwd(), "libraries");
const INDEX_PATH = path.join(LIBRARIES_DIR, "item-index.json");

export async function GET(request: Request) {
  const url = new URL(request.url);
  const key = url.searchParams.get("key") || "";

  if (!key) {
    return Response.json({ error: "key parameter required" }, { status: 400 });
  }

  const indexData = JSON.parse(await fs.readFile(INDEX_PATH, "utf-8"));
  const entry = indexData[key];

  if (!entry) {
    return Response.json({ error: "Item not found" }, { status: 404 });
  }

  const libPath = path.join(LIBRARIES_DIR, `${entry.library}.excalidrawlib`);
  const libData = JSON.parse(await fs.readFile(libPath, "utf-8"));
  const item = libData.libraryItems[entry.index];

  if (!item) {
    return Response.json({ error: "Item index out of range" }, { status: 404 });
  }

  return Response.json({
    name: entry.name,
    library: entry.library,
    elements: item.elements,
  });
}

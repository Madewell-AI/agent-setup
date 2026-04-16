import fs from "fs/promises";
import path from "path";

const INDEX_PATH = path.join(process.cwd(), "libraries", "item-index.json");

export async function GET(request: Request) {
  const url = new URL(request.url);
  const query = (url.searchParams.get("q") || "").toLowerCase();
  const lib = url.searchParams.get("lib") || "";

  const indexData = JSON.parse(await fs.readFile(INDEX_PATH, "utf-8"));

  const results = Object.entries(indexData)
    .filter(([key, val]: [string, any]) => {
      const matchesQuery = !query || key.toLowerCase().includes(query) || val.name.toLowerCase().includes(query);
      const matchesLib = !lib || val.library === lib;
      return matchesQuery && matchesLib;
    })
    .map(([key, val]: [string, any]) => ({
      key,
      ...val,
    }));

  return Response.json(results);
}

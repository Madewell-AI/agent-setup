import fs from "fs/promises";
import path from "path";

const DRAWINGS_DIR = path.join(process.cwd(), "drawings");

export async function GET(
  _request: Request,
  ctx: RouteContext<"/api/drawings/[id]">
) {
  const { id } = await ctx.params;
  const filePath = path.join(DRAWINGS_DIR, `${id}.excalidraw`);

  try {
    const content = await fs.readFile(filePath, "utf-8");
    return Response.json(JSON.parse(content));
  } catch {
    return Response.json({ error: "Drawing not found" }, { status: 404 });
  }
}

export async function PUT(
  request: Request,
  ctx: RouteContext<"/api/drawings/[id]">
) {
  const { id } = await ctx.params;
  const filePath = path.join(DRAWINGS_DIR, `${id}.excalidraw`);
  const body = await request.json();

  await fs.writeFile(filePath, JSON.stringify(body, null, 2));
  return Response.json({ ok: true });
}

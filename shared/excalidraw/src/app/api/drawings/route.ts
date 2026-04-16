import fs from "fs/promises";
import path from "path";
import crypto from "crypto";

const DRAWINGS_DIR = path.join(process.cwd(), "drawings");

export async function POST(request: Request) {
  const body = await request.json();
  const { elements, appState, files, name } = body;

  if (!elements || !Array.isArray(elements)) {
    return Response.json({ error: "elements array required" }, { status: 400 });
  }

  const id = body.id || crypto.randomBytes(8).toString("hex");

  const drawing = {
    type: "excalidraw",
    version: 2,
    name: name || id,
    elements,
    appState: appState || {
      viewBackgroundColor: "#ffffff",
      gridModeEnabled: false,
    },
    files: files || {},
  };

  await fs.mkdir(DRAWINGS_DIR, { recursive: true });
  await fs.writeFile(
    path.join(DRAWINGS_DIR, `${id}.excalidraw`),
    JSON.stringify(drawing, null, 2)
  );

  return Response.json({ id });
}

export async function GET() {
  try {
    const files = await fs.readdir(DRAWINGS_DIR);
    const drawings = files
      .filter((f) => f.endsWith(".excalidraw"))
      .map((f) => ({
        id: f.replace(".excalidraw", ""),
      }));
    return Response.json(drawings);
  } catch {
    return Response.json([]);
  }
}

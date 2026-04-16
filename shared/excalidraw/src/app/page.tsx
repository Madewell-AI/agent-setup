import fs from "fs/promises";
import path from "path";
import Link from "next/link";

const DRAWINGS_DIR = path.join(process.cwd(), "drawings");

export const dynamic = "force-dynamic";

interface DrawingMeta {
  id: string;
  title: string;
  createdAt: string;
}

export default async function HomePage() {
  let drawings: DrawingMeta[] = [];

  try {
    const files = await fs.readdir(DRAWINGS_DIR);
    const jsonFiles = files.filter((f) => f.endsWith(".excalidraw"));

    drawings = await Promise.all(
      jsonFiles.map(async (file) => {
        const content = await fs.readFile(
          path.join(DRAWINGS_DIR, file),
          "utf-8"
        );
        const data = JSON.parse(content);
        const stat = await fs.stat(path.join(DRAWINGS_DIR, file));
        return {
          id: file.replace(".excalidraw", ""),
          title: data.name || file.replace(".excalidraw", ""),
          createdAt: stat.birthtime.toISOString(),
        };
      })
    );

    drawings.sort(
      (a, b) =>
        new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
    );
  } catch {
    // drawings dir empty or doesn't exist yet
  }

  return (
    <div className="min-h-full bg-zinc-950 text-zinc-100">
      <div className="max-w-2xl mx-auto px-6 py-16">
        <h1 className="text-2xl font-semibold tracking-tight mb-1">Draw</h1>
        <p className="text-zinc-500 text-sm mb-10">
          Excalidraw drawings
        </p>

        {drawings.length === 0 ? (
          <p className="text-zinc-600 text-sm">No drawings yet.</p>
        ) : (
          <ul className="space-y-3">
            {drawings.map((d) => (
              <li key={d.id}>
                <Link
                  href={`/d/${d.id}`}
                  className="block p-4 rounded-lg border border-zinc-800 hover:border-zinc-600 transition-colors"
                >
                  <span className="font-medium">{d.title}</span>
                  <span className="block text-xs text-zinc-500 mt-1">
                    {new Date(d.createdAt).toLocaleDateString("en-US", {
                      month: "short",
                      day: "numeric",
                      year: "numeric",
                    })}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

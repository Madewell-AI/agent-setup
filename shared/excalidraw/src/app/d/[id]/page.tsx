"use client";

import { use, useEffect, useState, useCallback, useRef } from "react";
import "@excalidraw/excalidraw/index.css";

export default function DrawingPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ [key: string]: string | undefined }>;
}) {
  const { id } = use(params);
  const query = use(searchParams);
  const isExport = query.export === "true";

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const [Excalidraw, setExcalidraw] = useState<React.ComponentType<any> | null>(
    null
  );
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const [drawingData, setDrawingData] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const saveTimeout = useRef<ReturnType<typeof setTimeout> | null>(null);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const excalidrawAPI = useRef<any>(null);

  useEffect(() => {
    import("@excalidraw/excalidraw").then((mod) => {
      setExcalidraw(() => mod.Excalidraw);
    });
  }, []);

  useEffect(() => {
    fetch(`/api/drawings/${id}`)
      .then((r) => {
        if (!r.ok) throw new Error("Drawing not found");
        return r.json();
      })
      .then(setDrawingData)
      .catch((e) => setError(e.message));
  }, [id]);

  const handleChange = useCallback(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (elements: any[], appState: any, files: any) => {
      if (isExport) return;
      if (saveTimeout.current) clearTimeout(saveTimeout.current);
      saveTimeout.current = setTimeout(async () => {
        setSaving(true);
        try {
          await fetch(`/api/drawings/${id}`, {
            method: "PUT",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              type: "excalidraw",
              version: 2,
              name: drawingData?.name || id,
              elements: elements.filter(
                (e: { isDeleted?: boolean }) => !e.isDeleted
              ),
              appState: {
                viewBackgroundColor: appState.viewBackgroundColor,
                gridModeEnabled: appState.gridModeEnabled,
              },
              files,
            }),
          });
        } catch {
          // silent fail
        }
        setSaving(false);
      }, 2000);
    },
    [id, drawingData?.name, isExport]
  );

  if (error) {
    return (
      <div
        style={{
          height: "100vh",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "#f5f5f5",
          color: "#666",
        }}
      >
        <p>{error}</p>
      </div>
    );
  }

  if (!Excalidraw || !drawingData) {
    return (
      <div
        style={{
          height: "100vh",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "#f5f5f5",
          color: "#666",
        }}
      >
        <p>Loading...</p>
      </div>
    );
  }

  return (
    <div
      style={{ height: "100vh", width: "100vw", position: "relative" }}
      data-export-mode={isExport ? "true" : undefined}
    >
      {saving && !isExport && (
        <div
          style={{
            position: "absolute",
            top: 12,
            right: 12,
            zIndex: 50,
            fontSize: 12,
            color: "#999",
            background: "rgba(0,0,0,0.6)",
            padding: "4px 8px",
            borderRadius: 4,
          }}
        >
          Saving...
        </div>
      )}
      <Excalidraw
        excalidrawAPI={(api: any) => {
          // eslint-disable-line @typescript-eslint/no-explicit-any
          if (api && !excalidrawAPI.current) {
            excalidrawAPI.current = api;
            setTimeout(
              () =>
                api.scrollToContent(undefined, {
                  fitToViewport: true,
                  viewportZoomFactor: isExport ? 0.9 : 0.85,
                }),
              100
            );

            if (isExport) {
              setTimeout(() => {
                const selectors = [
                  ".App-toolbar",
                  ".App-toolbar-container",
                  ".layer-ui__wrapper__top-right",
                  ".layer-ui__wrapper__footer",
                  ".HintViewer",
                  ".App-menu",
                  ".App-menu_top",
                  ".undo-redo-buttons",
                  '[class*="sidebar"]',
                  '[class*="Sidebar"]',
                  ".help-icon",
                  ".zoom-actions",
                ];
                selectors.forEach((sel) => {
                  document.querySelectorAll(sel).forEach((el) => {
                    (el as HTMLElement).style.display = "none";
                  });
                });

                const layerUI = document.querySelector(".layer-ui__wrapper");
                if (layerUI) {
                  Array.from(layerUI.children).forEach((child) => {
                    (child as HTMLElement).style.display = "none";
                  });
                }

                document.body.setAttribute("data-export-ready", "true");
              }, 500);
            }
          }
        }}
        initialData={{
          elements: drawingData.elements,
          appState: {
            ...drawingData.appState,
            collaborators: new Map(),
          },
          files: drawingData.files,
        }}
        onChange={handleChange}
        theme="light"
        UIOptions={
          isExport
            ? {
                canvasActions: {
                  changeViewBackgroundColor: false,
                  export: false,
                  loadScene: false,
                  saveToActiveFile: false,
                  toggleTheme: false,
                  saveAsImage: false,
                },
              }
            : undefined
        }
      />
    </div>
  );
}

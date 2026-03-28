import { getCurrentWebviewWindow as getTauriWebviewWindow } from "@tauri-apps/api/webviewWindow";

type DragDropPayload = {
  type: string;
  paths: string[];
};

type DragDropEvent = {
  payload: DragDropPayload;
};

type WebviewWindowLike = {
  onDragDropEvent(
    handler: (event: DragDropEvent) => void | Promise<void>,
  ): Promise<() => void> | (() => void);
};

export function getSciPlotGodWebviewWindow(): WebviewWindowLike {
  try {
    const webviewWindow = getTauriWebviewWindow();
    if (webviewWindow && typeof webviewWindow.onDragDropEvent === "function") {
      return webviewWindow as WebviewWindowLike;
    }
  } catch (error) {
    const detail =
      error instanceof Error && error.message.trim() !== ""
        ? `: ${error.message}`
        : "";
    throw new Error(`The current desktop runtime does not support drag-and-drop import${detail}`);
  }

  throw new Error("The current desktop runtime does not support drag-and-drop import.");
}

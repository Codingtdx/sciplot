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

type TauriWebviewRuntime = {
  __CODEGOD_WEBVIEW_WINDOW__?: WebviewWindowLike;
};

const FALLBACK_WEBVIEW_WINDOW: WebviewWindowLike = {
  async onDragDropEvent() {
    return () => {};
  },
};

export function getCodeGodWebviewWindow(): WebviewWindowLike {
  const runtime = globalThis as TauriWebviewRuntime;
  if (runtime.__CODEGOD_WEBVIEW_WINDOW__) {
    return runtime.__CODEGOD_WEBVIEW_WINDOW__;
  }

  try {
    const webviewWindow = getTauriWebviewWindow();
    if (webviewWindow && typeof webviewWindow.onDragDropEvent === "function") {
      return webviewWindow as WebviewWindowLike;
    }
  } catch {
    return FALLBACK_WEBVIEW_WINDOW;
  }

  return FALLBACK_WEBVIEW_WINDOW;
}

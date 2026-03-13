import {
  open as tauriOpen,
  save as tauriSave,
  type OpenDialogOptions,
  type SaveDialogOptions,
} from "@tauri-apps/plugin-dialog";

type TauriDialogRuntime = {
  __CODEGOD_DIALOG__?: {
    open?: (options?: OpenDialogOptions) => Promise<string | string[] | null>;
    save?: (options?: SaveDialogOptions) => Promise<string | null>;
  };
};

export async function openDialog(options?: OpenDialogOptions) {
  const runtime = globalThis as TauriDialogRuntime;
  if (runtime.__CODEGOD_DIALOG__?.open) {
    return runtime.__CODEGOD_DIALOG__.open(options);
  }

  try {
    return await tauriOpen(options);
  } catch {
    return null;
  }
}

export async function saveDialog(options?: SaveDialogOptions) {
  const runtime = globalThis as TauriDialogRuntime;
  if (runtime.__CODEGOD_DIALOG__?.save) {
    return runtime.__CODEGOD_DIALOG__.save(options);
  }

  try {
    return await tauriSave(options);
  } catch {
    return null;
  }
}

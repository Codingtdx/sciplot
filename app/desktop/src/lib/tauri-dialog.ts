import {
  open as tauriOpen,
  save as tauriSave,
  type OpenDialogOptions,
  type SaveDialogOptions,
} from "@tauri-apps/plugin-dialog";

function wrapDialogError(prefix: string, error: unknown) {
  const detail =
    error instanceof Error && error.message.trim() !== ""
      ? error.message
      : "Make sure this window is running inside the Tauri desktop host.";
  return new Error(`${prefix}: ${detail}`);
}

export async function openDialog(options?: OpenDialogOptions) {
  try {
    return await tauriOpen(options);
  } catch (error) {
    throw wrapDialogError("Could not open the file picker", error);
  }
}

export async function saveDialog(options?: SaveDialogOptions) {
  try {
    return await tauriSave(options);
  } catch (error) {
    throw wrapDialogError("Could not open the save dialog", error);
  }
}

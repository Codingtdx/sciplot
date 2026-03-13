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
      : "请确认当前窗口运行在 Tauri 桌面宿主内。";
  return new Error(`${prefix}：${detail}`);
}

export async function openDialog(options?: OpenDialogOptions) {
  try {
    return await tauriOpen(options);
  } catch (error) {
    throw wrapDialogError("无法打开文件选择窗口", error);
  }
}

export async function saveDialog(options?: SaveDialogOptions) {
  try {
    return await tauriSave(options);
  } catch (error) {
    throw wrapDialogError("无法打开保存窗口", error);
  }
}

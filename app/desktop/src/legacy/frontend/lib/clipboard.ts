export async function copyTextToClipboard(value: string) {
  if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(value);
    return;
  }

  if (typeof document !== "undefined") {
    const fallback = document.createElement("textarea");
    fallback.value = value;
    fallback.setAttribute("readonly", "true");
    fallback.style.position = "absolute";
    fallback.style.left = "-9999px";
    document.body.appendChild(fallback);
    fallback.select();
    const copied = (document as Document & { execCommand?: (command: string) => boolean }).execCommand?.("copy");
    document.body.removeChild(fallback);
    if (copied) {
      return;
    }
  }

  throw new Error("Clipboard is unavailable in this environment.");
}

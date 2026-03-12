import { useEffect, useRef, useState } from "react";

import { renderPreview } from "../../lib/api";
import { requestCacheKey } from "../../lib/sidecar";
import type { PreviewItem, RenderOptionsPayload, TemplateName } from "../../lib/types";
import { getErrorMessage } from "../../lib/workbench";

type Args = {
  inputPath: string;
  sheet: string | number;
  template: TemplateName | null;
  options: RenderOptionsPayload;
  onPreviews(previews: PreviewItem[]): void;
};

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === "AbortError";
}

export function useWizardPreview({
  inputPath,
  sheet,
  template,
  options,
  onPreviews,
}: Args): {
  busy: boolean;
  error: string | null;
} {
  const cacheRef = useRef(new Map<string, PreviewItem[]>());
  const inFlightRef = useRef(new Map<string, Promise<PreviewItem[]>>());
  const latestRequestRef = useRef(0);
  const onPreviewsRef = useRef(onPreviews);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    onPreviewsRef.current = onPreviews;
  }, [onPreviews]);

  useEffect(() => {
    if (!inputPath || !template) {
      latestRequestRef.current += 1;
      setBusy(false);
      setError(null);
      onPreviewsRef.current([]);
      return;
    }

    const key = requestCacheKey("render-preview", {
      inputPath,
      options,
      sheet,
      template,
    });
    const cached = cacheRef.current.get(key);
    if (cached) {
      setBusy(false);
      setError(null);
      onPreviewsRef.current(cached);
      return;
    }

    const requestId = latestRequestRef.current + 1;
    latestRequestRef.current = requestId;
    const controller = new AbortController();
    const handle = window.setTimeout(() => {
      setBusy(true);
      setError(null);

      const existing = inFlightRef.current.get(key);
      const request =
        existing ??
        renderPreview(inputPath, sheet, template, options, {
          signal: controller.signal,
        }).then((payload) => payload.previews);

      inFlightRef.current.set(key, request);

      void request
        .then((previews) => {
          cacheRef.current.set(key, previews);
          if (latestRequestRef.current !== requestId || controller.signal.aborted) {
            return;
          }
          onPreviewsRef.current(previews);
          setError(null);
        })
        .catch((requestError) => {
          if (isAbortError(requestError) || latestRequestRef.current !== requestId) {
            return;
          }
          onPreviewsRef.current([]);
          setError(getErrorMessage(requestError));
        })
        .finally(() => {
          if (inFlightRef.current.get(key) === request) {
            inFlightRef.current.delete(key);
          }
          if (latestRequestRef.current === requestId) {
            setBusy(false);
          }
        });
    }, 220);

    return () => {
      controller.abort();
      window.clearTimeout(handle);
    };
  }, [inputPath, options, sheet, template]);

  return { busy, error };
}

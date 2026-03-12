import { useEffect, useRef } from "react";

import { composePreviewWithOptions } from "../../lib/api";
import { requestCacheKey } from "../../lib/sidecar";
import type { ComposerProject } from "../../lib/types";
import { getErrorMessage } from "../../lib/workbench";

type PreviewPayload = {
  png_base64: string;
  validation_error: string | null;
};

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === "AbortError";
}

export function useComposerPreview(
  project: ComposerProject,
  onPreview: (payload: PreviewPayload | null, error: string | null) => void,
) {
  const cacheRef = useRef(new Map<string, PreviewPayload>());
  const latestRequestRef = useRef(0);
  const onPreviewRef = useRef(onPreview);

  useEffect(() => {
    onPreviewRef.current = onPreview;
  }, [onPreview]);

  useEffect(() => {
    const key = requestCacheKey("compose-preview", project);
    const cached = cacheRef.current.get(key);
    if (cached) {
      onPreviewRef.current(cached, null);
      return;
    }

    const requestId = latestRequestRef.current + 1;
    latestRequestRef.current = requestId;
    const controller = new AbortController();
    const handle = window.setTimeout(() => {
      void composePreviewWithOptions(project, { signal: controller.signal })
        .then((response) => {
          const payload = {
            png_base64: response.png_base64,
            validation_error: response.validation_error ?? null,
          };
          cacheRef.current.set(key, payload);
          if (latestRequestRef.current !== requestId || controller.signal.aborted) {
            return;
          }
          onPreviewRef.current(payload, null);
        })
        .catch((error) => {
          if (isAbortError(error) || latestRequestRef.current !== requestId) {
            return;
          }
          onPreviewRef.current(null, getErrorMessage(error));
        });
    }, 120);

    return () => {
      controller.abort();
      window.clearTimeout(handle);
    };
  }, [project]);
}

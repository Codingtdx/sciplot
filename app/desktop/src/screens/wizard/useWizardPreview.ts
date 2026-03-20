import { useEffect, useRef, useState } from "react";

import { renderPreview } from "../../lib/api";
import { requestCacheKey } from "../../lib/sidecar";
import type {
  PreviewItem,
  RenderOptionsPayload,
  RequestActivity,
  TemplateName,
} from "../../lib/types";
import { getErrorMessage } from "../../lib/workbench";

type Args = {
  enabled?: boolean;
  inputPath: string;
  sheet: string | number;
  template: TemplateName | null;
  options: RenderOptionsPayload;
  onPreviews(previews: PreviewItem[]): void;
};

const previewCache = new Map<string, PreviewItem[]>();
const previewInFlight = new Map<string, Promise<PreviewItem[]>>();

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === "AbortError";
}

export function useWizardPreview({
  enabled = true,
  inputPath,
  sheet,
  template,
  options,
  onPreviews,
}: Args): {
  busy: boolean;
  error: string | null;
  activity: RequestActivity;
} {
  const latestRequestRef = useRef(0);
  const onPreviewsRef = useRef(onPreviews);
  const [error, setError] = useState<string | null>(null);
  const [activity, setActivity] = useState<RequestActivity>("idle");

  useEffect(() => {
    onPreviewsRef.current = onPreviews;
  }, [onPreviews]);

  useEffect(() => {
    if (!inputPath || !template) {
      latestRequestRef.current += 1;
      setActivity("idle");
      setError(null);
      onPreviewsRef.current([]);
      return;
    }

    if (!enabled) {
      setActivity("idle");
      setError(null);
      return;
    }

    const key = requestCacheKey("render-preview", {
      inputPath,
      options,
      sheet,
      template,
    });
    const cached = previewCache.get(key);
    if (cached) {
      setActivity("ready");
      setError(null);
      onPreviewsRef.current(cached);
      return;
    }

    const requestId = latestRequestRef.current + 1;
    latestRequestRef.current = requestId;
    const controller = new AbortController();
    setActivity("scheduled");
    const handle = window.setTimeout(() => {
      setActivity("running");
      setError(null);

      const existing = previewInFlight.get(key);
      const request =
        existing ??
        renderPreview(inputPath, sheet, template, options, {
          signal: controller.signal,
        }).then((payload) => payload.previews);

      previewInFlight.set(key, request);

      void request
        .then((previews) => {
          previewCache.set(key, previews);
          if (latestRequestRef.current !== requestId || controller.signal.aborted) {
            return;
          }
          onPreviewsRef.current(previews);
          setError(null);
          setActivity("ready");
        })
        .catch((requestError) => {
          if (isAbortError(requestError) || latestRequestRef.current !== requestId) {
            return;
          }
          onPreviewsRef.current([]);
          setError(getErrorMessage(requestError));
          setActivity("error");
        })
        .finally(() => {
          if (previewInFlight.get(key) === request) {
            previewInFlight.delete(key);
          }
        });
    }, 220);

    return () => {
      controller.abort();
      window.clearTimeout(handle);
    };
  }, [enabled, inputPath, options, sheet, template]);

  return {
    busy: activity === "scheduled" || activity === "running",
    error,
    activity,
  };
}

import { useRef, useState } from "react";

import { exportCodeConsoleBundle } from "../../lib/api";
import type { CodeConsoleExportResponse, RequestActivity } from "../../lib/types";
import { getErrorMessage } from "../../lib/workbench";

type ExportRequest = Parameters<typeof exportCodeConsoleBundle>[0];

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === "AbortError";
}

export function useCodeConsoleBundleExport() {
  const controllerRef = useRef<AbortController | null>(null);
  const [activity, setActivity] = useState<RequestActivity>("idle");
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<CodeConsoleExportResponse | null>(null);

  const exportBundle = async (request: ExportRequest) => {
    controllerRef.current?.abort();
    const controller = new AbortController();
    controllerRef.current = controller;
    setActivity("running");
    setError(null);

    try {
      const response = await exportCodeConsoleBundle(request, {
        signal: controller.signal,
      });
      if (controller.signal.aborted) {
        return null;
      }
      setResult(response);
      setError(null);
      setActivity("ready");
      return response;
    } catch (requestError) {
      if (isAbortError(requestError)) {
        return null;
      }
      setError(getErrorMessage(requestError));
      setActivity("error");
      return null;
    } finally {
      if (controllerRef.current === controller) {
        controllerRef.current = null;
      }
    }
  };

  return {
    activity,
    busy: activity === "running" || activity === "scheduled",
    error,
    exportBundle,
    result,
  };
}

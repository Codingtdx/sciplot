import { useCallback, useMemo, useRef, useState } from "react";

import { generateCodeConsole } from "../../lib/api";
import { requestCacheKey } from "../../lib/sidecar";
import type { CodeConsoleGenerateResponse, RequestActivity } from "../../lib/types";
import { getErrorMessage } from "../../lib/workbench";

type GenerateRequest = Parameters<typeof generateCodeConsole>[0];

const responseCache = new Map<string, CodeConsoleGenerateResponse>();

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === "AbortError";
}

export function useCodeConsoleGenerate() {
  const controllerRef = useRef<AbortController | null>(null);
  const latestRequestRef = useRef(0);
  const [activity, setActivity] = useState<RequestActivity>("idle");
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<CodeConsoleGenerateResponse | null>(null);

  const generate = useCallback(async (request: GenerateRequest) => {
    controllerRef.current?.abort();
    const requestId = latestRequestRef.current + 1;
    latestRequestRef.current = requestId;
    const key = requestCacheKey("code-console-generate", request);
    const cached = responseCache.get(key);
    if (cached) {
      setResult(cached);
      setError(null);
      setActivity("ready");
      return cached;
    }

    const controller = new AbortController();
    controllerRef.current = controller;
    setResult(null);
    setError(null);
    setActivity("running");

    try {
      const response = await generateCodeConsole(request, {
        signal: controller.signal,
      });
      if (controller.signal.aborted || latestRequestRef.current !== requestId) {
        return null;
      }
      responseCache.set(key, response);
      setResult(response);
      setError(null);
      setActivity("ready");
      return response;
    } catch (requestError) {
      if (isAbortError(requestError)) {
        if (latestRequestRef.current === requestId) {
          setActivity("idle");
          setError(null);
        }
        return null;
      }
      if (latestRequestRef.current !== requestId) {
        return null;
      }
      setResult(null);
      setError(getErrorMessage(requestError));
      setActivity("error");
      return null;
    } finally {
      if (controllerRef.current === controller) {
        controllerRef.current = null;
      }
    }
  }, []);

  const reset = useCallback(() => {
    latestRequestRef.current += 1;
    controllerRef.current?.abort();
    controllerRef.current = null;
    setResult(null);
    setError(null);
    setActivity("idle");
  }, []);

  return useMemo(() => ({
    activity,
    busy: activity === "scheduled" || activity === "running",
    error,
    generate,
    reset,
    result,
  }), [activity, error, generate, reset, result]);
}

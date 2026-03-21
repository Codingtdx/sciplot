import { useRef, useState } from "react";

import { generateCodeConsole } from "../../lib/api";
import { requestCacheKey } from "../../lib/sidecar";
import type { CodeConsoleGenerateResponse, RequestActivity } from "../../lib/types";
import { getErrorMessage } from "../../lib/workbench";

type GenerateRequest = Parameters<typeof generateCodeConsole>[0];

const responseCache = new Map<string, CodeConsoleGenerateResponse>();
const responseInFlight = new Map<string, Promise<CodeConsoleGenerateResponse>>();

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === "AbortError";
}

export function useCodeConsoleGenerate() {
  const controllerRef = useRef<AbortController | null>(null);
  const [activity, setActivity] = useState<RequestActivity>("idle");
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<CodeConsoleGenerateResponse | null>(null);

  const generate = async (request: GenerateRequest) => {
    controllerRef.current?.abort();
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
    setActivity("scheduled");
    setError(null);

    const existing = responseInFlight.get(key);
    const job =
      existing ??
      generateCodeConsole(request, {
        signal: controller.signal,
      });
    responseInFlight.set(key, job);
    setActivity("running");

    try {
      const response = await job;
      if (controller.signal.aborted) {
        return null;
      }
      responseCache.set(key, response);
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
      if (responseInFlight.get(key) === job) {
        responseInFlight.delete(key);
      }
      if (controllerRef.current === controller) {
        controllerRef.current = null;
      }
    }
  };

  return {
    activity,
    busy: activity === "scheduled" || activity === "running",
    error,
    generate,
    reset() {
      controllerRef.current?.abort();
      controllerRef.current = null;
      setResult(null);
      setError(null);
      setActivity("idle");
    },
    result,
  };
}

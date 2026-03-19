import { useEffect, useRef, useState } from "react";

import { preflightRender } from "../../lib/api";
import { requestCacheKey } from "../../lib/sidecar";
import type {
  PreflightResult,
  RequestActivity,
  RenderOptionsPayload,
  SubmissionReport,
  TemplateName,
} from "../../lib/types";
import { getErrorMessage } from "../../lib/workbench";

type Args = {
  inputPath: string;
  sheet: string | number;
  template: TemplateName | null;
  options: RenderOptionsPayload;
  onPreflight(preflight: PreflightResult | null): void;
  onSubmissionReport(report: SubmissionReport | null): void;
};

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === "AbortError";
}

export function useWizardPreflight({
  inputPath,
  sheet,
  template,
  options,
  onPreflight,
  onSubmissionReport,
}: Args): {
  busy: boolean;
  error: string | null;
  activity: RequestActivity;
} {
  const cacheRef = useRef(
    new Map<string, { preflight: PreflightResult; report: SubmissionReport | null }>(),
  );
  const inFlightRef = useRef(
    new Map<string, Promise<{ preflight: PreflightResult; report: SubmissionReport | null }>>(),
  );
  const latestRequestRef = useRef(0);
  const onPreflightRef = useRef(onPreflight);
  const onSubmissionReportRef = useRef(onSubmissionReport);
  const [error, setError] = useState<string | null>(null);
  const [activity, setActivity] = useState<RequestActivity>("idle");

  useEffect(() => {
    onPreflightRef.current = onPreflight;
  }, [onPreflight]);

  useEffect(() => {
    onSubmissionReportRef.current = onSubmissionReport;
  }, [onSubmissionReport]);

  useEffect(() => {
    if (!inputPath || !template) {
      latestRequestRef.current += 1;
      setActivity("idle");
      setError(null);
      onPreflightRef.current(null);
      onSubmissionReportRef.current(null);
      return;
    }

    const key = requestCacheKey("preflight-render", {
      inputPath,
      options,
      sheet,
      template,
    });
    const cached = cacheRef.current.get(key);
    if (cached) {
      setActivity("ready");
      setError(null);
      onPreflightRef.current(cached.preflight);
      onSubmissionReportRef.current(cached.report);
      return;
    }

    const requestId = latestRequestRef.current + 1;
    latestRequestRef.current = requestId;
    const controller = new AbortController();
    setActivity("scheduled");
    const handle = window.setTimeout(() => {
      setActivity("running");
      setError(null);

      const existing = inFlightRef.current.get(key);
      const request =
        existing ??
        preflightRender(
          inputPath,
          sheet,
          template,
          options,
          { signal: controller.signal },
        ).then((response) => ({
          preflight: response.preflight,
          report: response.preflight.submission_report ?? null,
        }));

      inFlightRef.current.set(key, request);

      void request
        .then((response) => {
          if (latestRequestRef.current !== requestId || controller.signal.aborted) {
            return;
          }
          cacheRef.current.set(key, response);
          onPreflightRef.current(response.preflight);
          onSubmissionReportRef.current(response.report);
          setError(null);
          setActivity("ready");
        })
        .catch((requestError) => {
          if (isAbortError(requestError) || latestRequestRef.current !== requestId) {
            return;
          }
          onPreflightRef.current(null);
          onSubmissionReportRef.current(null);
          setError(getErrorMessage(requestError));
          setActivity("error");
        })
        .finally(() => {
          if (inFlightRef.current.get(key) === request) {
            inFlightRef.current.delete(key);
          }
        });
    }, 220);

    return () => {
      controller.abort();
      window.clearTimeout(handle);
    };
  }, [inputPath, options, sheet, template]);

  return {
    busy: activity === "scheduled" || activity === "running",
    error,
    activity,
  };
}

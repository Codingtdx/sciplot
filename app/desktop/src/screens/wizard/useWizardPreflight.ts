import { useEffect, useRef, useState } from "react";

import { preflightRender } from "../../lib/api";
import type { PreflightResult, RenderOptionsPayload, TemplateName } from "../../lib/types";
import { getErrorMessage } from "../../lib/workbench";

type Args = {
  inputPath: string;
  sheet: string | number;
  template: TemplateName | null;
  options: RenderOptionsPayload;
  onPreflight(preflight: PreflightResult | null): void;
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
}: Args): {
  busy: boolean;
  error: string | null;
} {
  const latestRequestRef = useRef(0);
  const onPreflightRef = useRef(onPreflight);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    onPreflightRef.current = onPreflight;
  }, [onPreflight]);

  useEffect(() => {
    if (!inputPath || !template) {
      latestRequestRef.current += 1;
      setBusy(false);
      setError(null);
      onPreflightRef.current(null);
      return;
    }

    const requestId = latestRequestRef.current + 1;
    latestRequestRef.current = requestId;
    const controller = new AbortController();
    const handle = window.setTimeout(() => {
      setBusy(true);
      setError(null);

      void preflightRender(
        inputPath,
        sheet,
        template,
        options,
        { signal: controller.signal },
      )
        .then((response) => {
          if (latestRequestRef.current !== requestId || controller.signal.aborted) {
            return;
          }
          onPreflightRef.current(response.preflight);
          setError(null);
        })
        .catch((requestError) => {
          if (isAbortError(requestError) || latestRequestRef.current !== requestId) {
            return;
          }
          onPreflightRef.current(null);
          setError(getErrorMessage(requestError));
        })
        .finally(() => {
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

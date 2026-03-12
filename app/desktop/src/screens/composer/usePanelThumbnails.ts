import { useEffect, useRef, useState } from "react";

import { panelThumbnail } from "../../lib/api";
import { requestCacheKey } from "../../lib/sidecar";
import type { ComposerPanel } from "../../lib/types";

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === "AbortError";
}

export function usePanelThumbnails(panels: ComposerPanel[]) {
  const cacheRef = useRef(new Map<string, string>());
  const [thumbnailMap, setThumbnailMap] = useState<Record<string, string>>({});
  const latestRequestRef = useRef(0);

  useEffect(() => {
    if (panels.length === 0) {
      latestRequestRef.current += 1;
      setThumbnailMap({});
      return;
    }

    const requestId = latestRequestRef.current + 1;
    latestRequestRef.current = requestId;
    const controller = new AbortController();

    void Promise.all(
      panels.map(async (panel) => {
        try {
          const key = requestCacheKey("panel-thumbnail", {
            file_path: panel.file_path,
            page_index: panel.page_index,
          });
          const cached = cacheRef.current.get(key);
          if (cached) {
            return [panel.id, cached] as const;
          }

          const thumbnail = await panelThumbnail(panel.file_path, panel.page_index, {
            signal: controller.signal,
          });
          cacheRef.current.set(key, thumbnail);
          return [panel.id, thumbnail] as const;
        } catch (error) {
          if (!isAbortError(error)) {
            return null;
          }
          throw error;
        }
      }),
    )
      .then((entries) => {
        if (latestRequestRef.current !== requestId || controller.signal.aborted) {
          return;
        }
        setThumbnailMap(
          Object.fromEntries(entries.filter(Boolean) as Array<readonly [string, string]>),
        );
      })
      .catch((error) => {
        if (!isAbortError(error) && latestRequestRef.current === requestId) {
          setThumbnailMap({});
        }
      });

    return () => {
      controller.abort();
    };
  }, [panels]);

  return thumbnailMap;
}

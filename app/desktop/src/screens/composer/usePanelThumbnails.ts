import { useEffect, useRef, useState } from "react";

import { panelThumbnail } from "../../lib/api";
import { requestCacheKey } from "../../lib/sidecar";
import type { ComposerPanel } from "../../lib/types";

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === "AbortError";
}

export function usePanelThumbnails(panels: ComposerPanel[]) {
  const cacheRef = useRef(new Map<string, string>());
  const inflightRef = useRef(new Map<string, Promise<string>>());
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
    let cancelled = false;
    const panelEntries = panels.map((panel) => ({
      panel,
      key: requestCacheKey("panel-thumbnail", {
        file_path: panel.file_path,
        page_index: panel.page_index,
      }),
    }));

    setThumbnailMap((current) => {
      const nextEntries = panelEntries.flatMap(({ panel, key }) => {
        const cached = cacheRef.current.get(key);
        const existing = cached ?? current[panel.id];
        return existing ? [[panel.id, existing] as const] : [];
      });
      return Object.fromEntries(nextEntries);
    });

    panelEntries.forEach(({ panel, key }) => {
      if (cacheRef.current.has(key)) {
        return;
      }

      let request = inflightRef.current.get(key);
      if (!request) {
        request = panelThumbnail(panel.file_path, panel.page_index)
          .then((thumbnail) => {
            cacheRef.current.set(key, thumbnail);
            return thumbnail;
          })
          .finally(() => {
            inflightRef.current.delete(key);
          });
        inflightRef.current.set(key, request);
      }

      void request
        .then((thumbnail) => {
          if (cancelled || latestRequestRef.current !== requestId) {
            return;
          }
          setThumbnailMap((current) => ({
            ...current,
            ...Object.fromEntries(
              panelEntries
                .filter((entry) => entry.key === key)
                .map((entry) => [entry.panel.id, thumbnail] as const),
            ),
          }));
        })
        .catch((error) => {
          if (!isAbortError(error) && !cancelled && latestRequestRef.current === requestId) {
            setThumbnailMap((current) => current);
          }
        });
    });

    return () => {
      cancelled = true;
    };
  }, [panels]);

  return thumbnailMap;
}

import { useEffect, useMemo, useRef, useState } from "react";

import type { PreviewItem } from "../lib/types";

type Props = {
  previews: PreviewItem[];
  previewIndex: number;
  onChangeIndex(index: number): void;
  busy: boolean;
  error: string | null;
};

export function PreviewPane({ previews, previewIndex, onChangeIndex, busy, error }: Props) {
  const current = previews[previewIndex] ?? null;
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [zoomMode, setZoomMode] = useState<"fit" | "100" | "150" | "200">("fit");

  useEffect(() => {
    setZoomMode("fit");
  }, [previewIndex, current?.filename]);

  const imageStyle = useMemo(() => {
    if (zoomMode === "fit") {
      return {
        maxWidth: "100%",
        maxHeight: "100%",
        width: "auto",
        height: "auto",
      };
    }

    const scaleMap = {
      "100": 1,
      "150": 1.5,
      "200": 2,
    } as const;
    const scale = scaleMap[zoomMode];
    return {
      maxWidth: "none",
      maxHeight: "none",
      width: `${scale * 100}%`,
      height: "auto",
    };
  }, [zoomMode]);

  const cycleZoom = () => {
    setZoomMode((mode) => (mode === "fit" ? "100" : "fit"));
  };

  const handleWheel: React.WheelEventHandler<HTMLDivElement> = (event) => {
    if (!current) {
      return;
    }
    const modes: Array<"fit" | "100" | "150" | "200"> = ["fit", "100", "150", "200"];
    const index = modes.indexOf(zoomMode);
    const nextIndex =
      event.deltaY < 0
        ? Math.min(modes.length - 1, index + 1)
        : Math.max(0, index - 1);
    if (nextIndex !== index) {
      event.preventDefault();
      setZoomMode(modes[nextIndex]);
    }
  };

  return (
    <section className="preview-pane">
      <div className="preview-toolbar">
        <div>
          <div className="preview-title">{current?.filename ?? "等待图像"}</div>
          <div className="preview-subtitle">
            {current ? "当前预览" : "修改模板或参数后自动更新"}
          </div>
        </div>
        <div className="preview-nav">
          <button
            className={`ghost-button ${zoomMode === "fit" ? "active-toggle" : ""}`}
            onClick={() => setZoomMode("fit")}
            type="button"
          >
            适配宽度
          </button>
          <button
            className={`ghost-button ${zoomMode === "100" ? "active-toggle" : ""}`}
            onClick={() => setZoomMode("100")}
            type="button"
          >
            100%
          </button>
          <button
            className="ghost-button"
            disabled={previewIndex <= 0}
            onClick={() => onChangeIndex(Math.max(0, previewIndex - 1))}
            type="button"
          >
            上一张
          </button>
          <span className="preview-count">
            {previews.length > 0 ? `${previewIndex + 1} / ${previews.length}` : "0 / 0"}
          </span>
          <button
            className="ghost-button"
            disabled={previewIndex >= previews.length - 1}
            onClick={() => onChangeIndex(Math.min(previews.length - 1, previewIndex + 1))}
            type="button"
          >
            下一张
          </button>
        </div>
      </div>
      <div className="preview-surface" onWheel={handleWheel} ref={containerRef}>
        {busy && <div className="placeholder-card">正在刷新预览…</div>}
        {!busy && error && <div className="error-card">{error}</div>}
        {!busy && !error && !current && (
          <div className="placeholder-card">
            选择数据并确认图类型后，这里会显示预览。
          </div>
        )}
        {!busy && !error && current && (
          <img
            alt={current.filename}
            className="preview-image"
            onDoubleClick={cycleZoom}
            src={`data:image/png;base64,${current.png_base64}`}
            style={imageStyle}
          />
        )}
      </div>
    </section>
  );
}

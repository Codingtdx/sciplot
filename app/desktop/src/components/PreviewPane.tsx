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

  return (
    <section className="preview-pane">
      <div className="preview-toolbar">
        <div>
          <div className="preview-title">{current?.filename ?? "等待图像"}</div>
        </div>
        <div className="preview-nav">
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
      <div className="preview-surface">
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
            src={`data:image/png;base64,${current.png_base64}`}
          />
        )}
      </div>
    </section>
  );
}

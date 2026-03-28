import { MacButton } from "./MacButton";
import { MacStatusPill } from "./MacStatusPill";
import { AppIcon } from "../AppIcon";

export function MacTitlebar({
  eyebrow,
  title,
  sidecarReady,
  onRefresh,
}: {
  eyebrow: string;
  title: string;
  sidecarReady: boolean;
  onRefresh: () => void;
}) {
  return (
    <header className="app-titlebar">
      <div className="traffic-lights" aria-hidden="true">
        <span className="traffic-light traffic-close" />
        <span className="traffic-light traffic-minimize" />
        <span className="traffic-light traffic-zoom" />
      </div>
      <div className="titlebar-copy">
        <span className="titlebar-eyebrow">{eyebrow}</span>
        <h2>{title}</h2>
      </div>
      <div className="titlebar-actions">
        <MacStatusPill tone={sidecarReady ? "success" : "warning"}>
          {sidecarReady ? "Sidecar connected" : "Sidecar unavailable"}
        </MacStatusPill>
        <MacButton variant="ghost" onClick={onRefresh} icon={<AppIcon name="refresh" />}>
          Refresh
        </MacButton>
      </div>
    </header>
  );
}

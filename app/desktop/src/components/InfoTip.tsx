import { useEffect, useId, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";

type Props = {
  content: ReactNode;
  label?: string;
  className?: string;
};

type Placement = "top" | "bottom";

export function InfoTip({ content, label = "More info", className }: Props) {
  const triggerRef = useRef<HTMLButtonElement | null>(null);
  const bubbleRef = useRef<HTMLDivElement | null>(null);
  const timerRef = useRef<number | null>(null);
  const tooltipId = useId();
  const [open, setOpen] = useState(false);
  const [placement, setPlacement] = useState<Placement>("top");
  const [position, setPosition] = useState({ top: 0, left: 0 });

  const clearTimer = () => {
    if (timerRef.current != null) {
      window.clearTimeout(timerRef.current);
      timerRef.current = null;
    }
  };

  const close = () => {
    clearTimer();
    setOpen(false);
  };

  const openDelayed = () => {
    clearTimer();
    timerRef.current = window.setTimeout(() => {
      setOpen(true);
    }, 120);
  };

  const openImmediate = () => {
    clearTimer();
    setOpen(true);
  };

  useEffect(() => {
    return () => {
      clearTimer();
    };
  }, []);

  useLayoutEffect(() => {
    if (!open || !triggerRef.current || !bubbleRef.current) {
      return;
    }

    const updatePosition = () => {
      if (!triggerRef.current || !bubbleRef.current) {
        return;
      }

      const triggerRect = triggerRef.current.getBoundingClientRect();
      const bubbleRect = bubbleRef.current.getBoundingClientRect();
      const nextPlacement: Placement =
        triggerRect.top > bubbleRect.height + 28 ? "top" : "bottom";
      const gap = 10;
      const top =
        nextPlacement === "top"
          ? triggerRect.top - bubbleRect.height - gap
          : triggerRect.bottom + gap;
      const left = Math.min(
        window.innerWidth - bubbleRect.width - 16,
        Math.max(16, triggerRect.left + triggerRect.width / 2 - bubbleRect.width / 2),
      );

      setPlacement(nextPlacement);
      setPosition({ top, left });
    };

    updatePosition();
    window.addEventListener("resize", updatePosition);
    window.addEventListener("scroll", updatePosition, true);
    return () => {
      window.removeEventListener("resize", updatePosition);
      window.removeEventListener("scroll", updatePosition, true);
    };
  }, [open, content]);

  return (
    <span className={`info-tip ${className ?? ""}`.trim()}>
      <button
        aria-describedby={open ? tooltipId : undefined}
        aria-label={label}
        className="info-tip-trigger"
        onBlur={close}
        onFocus={openImmediate}
        onKeyDown={(event) => {
          if (event.key === "Escape") {
            close();
          }
        }}
        onMouseEnter={openDelayed}
        onMouseLeave={close}
        ref={triggerRef}
        type="button"
      >
        <svg
          aria-hidden="true"
          fill="none"
          stroke="currentColor"
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth="1.7"
          viewBox="0 0 20 20"
        >
          <circle cx="10" cy="10" r="7.25" />
          <path d="M10 8.25v4.1" />
          <path d="M10 5.95h.01" />
        </svg>
      </button>
      {open &&
        typeof document !== "undefined" &&
        createPortal(
          <div
            className={`info-tip-bubble info-tip-bubble-${placement}`}
            id={tooltipId}
            ref={bubbleRef}
            role="tooltip"
            style={position}
          >
            {content}
          </div>,
          document.body,
        )}
    </span>
  );
}

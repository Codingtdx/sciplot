import type { SVGProps } from "react";

export type AppIconName =
  | "start"
  | "import"
  | "template"
  | "refine"
  | "plot"
  | "tensile"
  | "composer"
  | "code"
  | "settings"
  | "spark"
  | "table"
  | "preview"
  | "export"
  | "folder"
  | "check"
  | "warning"
  | "refresh"
  | "chevron-right";

type AppIconProps = SVGProps<SVGSVGElement> & {
  name: AppIconName;
};

function pathForIcon(name: AppIconName) {
  switch (name) {
    case "start":
      return (
        <>
          <path d="M4 5.75A1.75 1.75 0 0 1 5.75 4h12.5A1.75 1.75 0 0 1 20 5.75v12.5A1.75 1.75 0 0 1 18.25 20H5.75A1.75 1.75 0 0 1 4 18.25z" />
          <path d="M9 8.5h6M9 12h6M9 15.5h3.5" />
        </>
      );
    case "import":
      return (
        <>
          <path d="M12 4.75v10.5" />
          <path d="m8.75 11.5 3.25 3.25 3.25-3.25" />
          <path d="M5 18.25A1.75 1.75 0 0 0 6.75 20h10.5A1.75 1.75 0 0 0 19 18.25V17" />
        </>
      );
    case "template":
      return (
        <>
          <rect x="4.5" y="5.5" width="15" height="13" rx="2.5" />
          <path d="M9 9.25h6M9 12h6M9 14.75h3.5" />
          <path d="M7.5 5.5v13" />
        </>
      );
    case "refine":
      return (
        <>
          <path d="M5 17.5 9.5 13l3.25 2.75L19 9.5" />
          <path d="M5 5v14h14" />
        </>
      );
    case "plot":
      return (
        <>
          <path d="M5 18.5V5.5h14" />
          <path d="m7 15 3.25-4 2.5 2.5L18 8" />
        </>
      );
    case "tensile":
      return (
        <>
          <path d="M8 5.5v4.25M16 14.25v4.25" />
          <path d="M8 9.75h8v4.5H8z" />
        </>
      );
    case "composer":
      return (
        <>
          <rect x="4.5" y="5" width="7" height="6.5" rx="1.5" />
          <rect x="12.5" y="5" width="7" height="13.5" rx="1.5" />
          <rect x="4.5" y="12.5" width="7" height="6" rx="1.5" />
        </>
      );
    case "code":
      return (
        <>
          <path d="m9 8-4 4 4 4" />
          <path d="m15 8 4 4-4 4" />
        </>
      );
    case "settings":
      return (
        <>
          <path d="M12 8.5a3.5 3.5 0 1 1 0 7 3.5 3.5 0 0 1 0-7Z" />
          <path d="M12 3.75v2.1M12 18.15v2.1M4.95 6.05l1.5 1.2M17.55 16.75l1.5 1.2M3.75 12h2.1M18.15 12h2.1M4.95 17.95l1.5-1.2M17.55 7.25l1.5-1.2" />
        </>
      );
    case "spark":
      return (
        <>
          <path d="M12 4.5 13.7 8.3 18 10l-4.3 1.7L12 15.5l-1.7-3.8L6 10l4.3-1.7z" />
        </>
      );
    case "table":
      return (
        <>
          <rect x="4.5" y="5.5" width="15" height="13" rx="2" />
          <path d="M4.5 10.5h15M9.5 5.5v13M14.5 5.5v13" />
        </>
      );
    case "preview":
      return (
        <>
          <rect x="4.5" y="5.5" width="15" height="13" rx="2.5" />
          <path d="m8 14 2.5-2.75L13 13.5l3-3.5 2 2.5" />
        </>
      );
    case "export":
      return (
        <>
          <path d="M12 18.75V8.25" />
          <path d="m15.25 11.5-3.25-3.25-3.25 3.25" />
          <path d="M5 18.25A1.75 1.75 0 0 0 6.75 20h10.5A1.75 1.75 0 0 0 19 18.25V17" />
        </>
      );
    case "folder":
      return (
        <>
          <path d="M4.5 8.25A2.25 2.25 0 0 1 6.75 6h3l1.5 1.75h6A2.75 2.75 0 0 1 20 10.5v6.75A2.75 2.75 0 0 1 17.25 20H6.75A2.25 2.25 0 0 1 4.5 17.75z" />
        </>
      );
    case "check":
      return <path d="m6.5 12.25 3.25 3.25 7.75-8" />;
    case "warning":
      return (
        <>
          <path d="M12 5.25 19 18.5H5z" />
          <path d="M12 9.5v4.5M12 16.25h.01" />
        </>
      );
    case "refresh":
      return (
        <>
          <path d="M18 8.5V5h-3.5" />
          <path d="M18 5a8 8 0 1 0 2 7" />
        </>
      );
    case "chevron-right":
      return <path d="m10 7 4.5 5L10 17" />;
    default:
      return <circle cx="12" cy="12" r="6" />;
  }
}

export function AppIcon({ name, className, ...props }: AppIconProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className={className}
      {...props}
    >
      {pathForIcon(name)}
    </svg>
  );
}

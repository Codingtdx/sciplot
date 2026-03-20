export type AppIconName =
  | "home"
  | "tensile"
  | "plot"
  | "composer"
  | "projects"
  | "settings"
  | "spark"
  | "layers"
  | "plus"
  | "inspect";

type Props = {
  name: AppIconName;
  className?: string;
};

function iconPath(name: AppIconName) {
  switch (name) {
    case "home":
      return (
        <>
          <path d="M4 11.5 12 5l8 6.5" />
          <path d="M6.5 10.5V19h11v-8.5" />
        </>
      );
    case "tensile":
      return (
        <>
          <path d="M4 18 9 11l4 3 7-10" />
          <path d="M4 6v12h16" />
        </>
      );
    case "plot":
      return (
        <>
          <path d="M4 17 8 12l4 2 4-6 4 3" />
          <path d="M4 6v12h16" />
        </>
      );
    case "composer":
      return (
        <>
          <rect x="4" y="4" width="7" height="7" rx="1.5" />
          <rect x="13" y="4" width="7" height="4.5" rx="1.5" />
          <rect x="13" y="10.5" width="7" height="9.5" rx="1.5" />
          <rect x="4" y="13" width="7" height="7" rx="1.5" />
        </>
      );
    case "projects":
      return (
        <>
          <path d="M4 7.5A2.5 2.5 0 0 1 6.5 5H10l1.2 2H17.5A2.5 2.5 0 0 1 20 9.5v8A2.5 2.5 0 0 1 17.5 20h-11A2.5 2.5 0 0 1 4 17.5z" />
          <path d="M4 9h16" />
        </>
      );
    case "settings":
      return (
        <>
          <path d="M12 8.5A3.5 3.5 0 1 1 8.5 12 3.5 3.5 0 0 1 12 8.5Z" />
          <path d="M12 3.5v2.2M12 18.3v2.2M20.5 12h-2.2M5.7 12H3.5M18 6l-1.5 1.5M7.5 16.5 6 18M18 18l-1.5-1.5M7.5 7.5 6 6" />
        </>
      );
    case "spark":
      return (
        <>
          <path d="m12 3 1.6 4.4L18 9l-4.4 1.6L12 15l-1.6-4.4L6 9l4.4-1.6z" />
          <path d="M18.5 3.5 19 5l1.5.5-1.5.5-.5 1.5-.5-1.5L16.5 5l1.5-.5zM5.5 15.5 6 17l1.5.5-1.5.5-.5 1.5-.5-1.5L3.5 17l1.5-.5z" />
        </>
      );
    case "layers":
      return (
        <>
          <path d="m12 4 8 4-8 4-8-4z" />
          <path d="m4 12 8 4 8-4" />
          <path d="m4 16 8 4 8-4" />
        </>
      );
    case "plus":
      return (
        <>
          <path d="M12 5v14M5 12h14" />
        </>
      );
    case "inspect":
      return (
        <>
          <circle cx="11" cy="11" r="6.5" />
          <path d="m16 16 4 4" />
        </>
      );
  }
}

export function AppIcon({ name, className }: Props) {
  return (
    <svg
      aria-hidden="true"
      className={className}
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="1.8"
      viewBox="0 0 24 24"
    >
      {iconPath(name)}
    </svg>
  );
}

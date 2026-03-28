import type {
  AppearanceMode,
  ResolvedAppearance,
  ThemePreset,
  ThemePresetId,
} from "./types";

export const THEME_PRESETS: ThemePreset[] = [
  {
    id: "paper-lab",
    name: "Paper Lab",
    appearance: "light",
    accent: "Coral + Teal",
    description: "Warm editorial surfaces with paper-like contrast and soft lab lighting.",
    preview: {
      background: "linear-gradient(135deg, #f4ecde 0%, #e6dfd4 100%)",
      surface: "rgba(255, 251, 245, 0.92)",
      glow: "rgba(255, 120, 90, 0.36)",
      chip: "#0f766e",
    },
  },
  {
    id: "mist-jade",
    name: "Mist Jade",
    appearance: "light",
    accent: "Jade + Fog",
    description: "A cleaner, calmer light preset with cool glass edges and misty gradients.",
    preview: {
      background: "linear-gradient(135deg, #e8f4f0 0%, #dde8ea 100%)",
      surface: "rgba(246, 252, 250, 0.92)",
      glow: "rgba(16, 185, 129, 0.28)",
      chip: "#0f766e",
    },
  },
  {
    id: "nocturne-glass",
    name: "Nocturne Glass",
    appearance: "dark",
    accent: "Teal + Ember",
    description: "Deep glass panels, studio contrast, and the premium dark desktop default.",
    preview: {
      background: "linear-gradient(135deg, #0b1217 0%, #15212a 100%)",
      surface: "rgba(17, 26, 33, 0.92)",
      glow: "rgba(20, 184, 166, 0.3)",
      chip: "#ff875e",
    },
  },
  {
    id: "verge-slate",
    name: "Verge Slate",
    appearance: "dark",
    accent: "Slate + Signal",
    description: "Sharper contrast and brighter signal accents inspired by modern desktop tooling.",
    preview: {
      background: "linear-gradient(135deg, #0d1118 0%, #202734 100%)",
      surface: "rgba(19, 24, 35, 0.94)",
      glow: "rgba(96, 165, 250, 0.32)",
      chip: "#7dd3fc",
    },
  },
];

export const DEFAULT_THEME_PRESET_BY_APPEARANCE: Record<
  ResolvedAppearance,
  ThemePresetId
> = {
  light: "paper-lab",
  dark: "nocturne-glass",
};

const PRESET_MAP = new Map(THEME_PRESETS.map((preset) => [preset.id, preset] as const));

export function isThemePresetId(value: string | null | undefined): value is ThemePresetId {
  return typeof value === "string" && PRESET_MAP.has(value);
}

export function themePresetById(value: string | null | undefined): ThemePreset | null {
  if (!isThemePresetId(value)) {
    return null;
  }
  return PRESET_MAP.get(value) ?? null;
}

export function resolveAppearance(
  appearanceMode: AppearanceMode,
  prefersDark: boolean,
): ResolvedAppearance {
  if (appearanceMode === "light" || appearanceMode === "dark") {
    return appearanceMode;
  }
  return prefersDark ? "dark" : "light";
}

export function resolveThemePreset(
  presetId: string | null | undefined,
  appearance: ResolvedAppearance,
): ThemePreset {
  return (
    themePresetById(presetId) ??
    themePresetById(DEFAULT_THEME_PRESET_BY_APPEARANCE[appearance]) ??
    THEME_PRESETS[0]
  );
}

export function describeAppearanceMode(value: AppearanceMode) {
  if (value === "light") {
    return "Light";
  }
  if (value === "dark") {
    return "Dark";
  }
  return "System";
}

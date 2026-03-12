import type {
  InputInspection,
  PalettePreset,
  RenderOptionsPayload,
  SizePreset,
  TemplateName,
  WorkbenchMeta,
  WorkbenchTemplate,
} from "./types";

const ALL_RENDER_OPTION_KEYS = [
  "size",
  "xscale",
  "yscale",
  "reverse_x",
  "baseline",
  "show_colorbar",
  "palette_preset",
  "use_sidecar",
] as const satisfies Array<keyof RenderOptionsPayload>;

function templateIds(meta: WorkbenchMeta | null): TemplateName[] {
  if (!meta) {
    return [];
  }
  return meta.template_ids.length > 0
    ? meta.template_ids
    : meta.templates.map((template) => template.id);
}

export function templateMeta(
  meta: WorkbenchMeta | null,
  template: TemplateName | null | undefined,
): WorkbenchTemplate | null {
  if (!meta || !template) {
    return null;
  }
  return meta.templates.find((item) => item.id === template) ?? null;
}

export function sanitizeTemplateId(
  meta: WorkbenchMeta | null,
  candidate: TemplateName | null | undefined,
  fallback?: TemplateName | null,
): TemplateName | null {
  if (!meta) {
    return candidate ?? fallback ?? null;
  }

  const ids = templateIds(meta);
  if (candidate && ids.includes(candidate)) {
    return candidate;
  }
  if (fallback && ids.includes(fallback)) {
    return fallback;
  }
  return ids[0] ?? null;
}

function pickAllowedSize(
  meta: WorkbenchMeta | null,
  template: WorkbenchTemplate | null,
  candidate: string | undefined,
): SizePreset | undefined {
  if (!template) {
    return candidate as SizePreset | undefined;
  }

  const allowed = template.allowed_sizes;
  if (candidate && allowed.includes(candidate)) {
    return candidate;
  }
  if (template.default_size && allowed.includes(template.default_size)) {
    return template.default_size;
  }
  return allowed[0] ?? meta?.size_ids[0];
}

function pickAllowedPalette(
  meta: WorkbenchMeta | null,
  template: WorkbenchTemplate | null,
  candidate: string | undefined,
): PalettePreset | undefined {
  const available = template?.available_palettes ?? meta?.palette_preset_ids ?? [];
  if (candidate && available.includes(candidate)) {
    return candidate;
  }
  if (meta?.default_palette && available.includes(meta.default_palette)) {
    return meta.default_palette;
  }
  return available[0];
}

export function sanitizeRenderOptions(
  meta: WorkbenchMeta | null,
  templateId: TemplateName | null | undefined,
  options: RenderOptionsPayload,
): RenderOptionsPayload {
  const template = templateMeta(meta, templateId);
  const allowed = new Set<keyof RenderOptionsPayload>(
    template?.editable_options ?? ALL_RENDER_OPTION_KEYS,
  );
  const source = {
    ...(template?.default_options ?? {}),
    ...options,
  };
  const next: RenderOptionsPayload = {};

  if (allowed.has("size")) {
    const size = pickAllowedSize(meta, template, source.size);
    if (size) {
      next.size = size;
    }
  }
  if (allowed.has("xscale") && (source.xscale === "linear" || source.xscale === "log")) {
    next.xscale = source.xscale;
  }
  if (allowed.has("yscale") && (source.yscale === "linear" || source.yscale === "log")) {
    next.yscale = source.yscale;
  }
  if (allowed.has("reverse_x") && typeof source.reverse_x === "boolean") {
    next.reverse_x = source.reverse_x;
  }
  if (
    allowed.has("baseline") &&
    (source.baseline === "none" || source.baseline === "linear_endpoints")
  ) {
    next.baseline = source.baseline;
  }
  if (allowed.has("show_colorbar") && typeof source.show_colorbar === "boolean") {
    next.show_colorbar = source.show_colorbar;
  }
  if (allowed.has("palette_preset")) {
    const palette = pickAllowedPalette(meta, template, source.palette_preset);
    if (palette) {
      next.palette_preset = palette;
    }
  }
  if (allowed.has("use_sidecar") && typeof source.use_sidecar === "boolean") {
    next.use_sidecar = source.use_sidecar;
  }

  return next;
}

export function mergeRenderOptions(
  meta: WorkbenchMeta | null,
  templateId: TemplateName | null | undefined,
  current: RenderOptionsPayload,
  patch: Partial<RenderOptionsPayload>,
): RenderOptionsPayload {
  return sanitizeRenderOptions(meta, templateId, {
    ...current,
    ...patch,
  });
}

function inspectionOptions(inspection: InputInspection): RenderOptionsPayload {
  const recommendation = inspection.recommendation;
  return {
    size: recommendation.size,
    xscale: recommendation.xscale,
    yscale: recommendation.yscale,
    reverse_x: recommendation.reverse_x,
    baseline: recommendation.baseline,
    show_colorbar: recommendation.show_colorbar,
    use_sidecar: recommendation.use_sidecar,
  };
}

export function selectionFromInspection(
  meta: WorkbenchMeta | null,
  inspection: InputInspection,
  overrides?: {
    template?: TemplateName | null;
    options?: RenderOptionsPayload;
  },
): {
  template: TemplateName | null;
  options: RenderOptionsPayload;
} {
  const template = sanitizeTemplateId(
    meta,
    overrides?.template ?? inspection.recommendation.template,
    inspection.recommendation.template,
  );
  return {
    template,
    options: sanitizeRenderOptions(meta, template, {
      ...inspectionOptions(inspection),
      ...(overrides?.options ?? {}),
    }),
  };
}

export function areRenderOptionsEqual(
  left: RenderOptionsPayload,
  right: RenderOptionsPayload,
): boolean {
  return ALL_RENDER_OPTION_KEYS.every((key) => left[key] === right[key]);
}

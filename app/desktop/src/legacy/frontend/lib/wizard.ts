import type {
  InputInspection,
  PalettePreset,
  RenderOptionsPayload,
  SizePreset,
  StylePreset,
  TemplateName,
  TemplateRecommendation,
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
  "style_preset",
  "palette_preset",
  "use_sidecar",
  "visual_theme_id",
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

export type RankedInspectionRecommendation = {
  template: WorkbenchTemplate;
  recommendation: TemplateRecommendation;
};

export type InspectionRecommendationSections = {
  primary: RankedInspectionRecommendation[];
  alternatives: RankedInspectionRecommendation[];
  advanced: RankedInspectionRecommendation[];
};

function inspectionTemplateMeta(
  meta: WorkbenchMeta | null,
  recommendation: TemplateRecommendation,
): WorkbenchTemplate | null {
  const canonicalTemplate =
    templateMeta(meta, recommendation.canonical_id ?? recommendation.implementation_id ?? recommendation.template_id) ??
    templateMeta(meta, recommendation.template_id);
  return canonicalTemplate;
}

function mapInspectionRecommendations(
  meta: WorkbenchMeta | null,
  recommendations: TemplateRecommendation[],
): RankedInspectionRecommendation[] {
  return recommendations
    .map((recommendation) => {
      const template = inspectionTemplateMeta(meta, recommendation);
      return template ? { template, recommendation } : null;
    })
    .filter((item): item is RankedInspectionRecommendation => Boolean(item));
}

export function inspectionPrimaryRecommendationChoices(
  meta: WorkbenchMeta | null,
  inspection: InputInspection | null,
  limit = 2,
): RankedInspectionRecommendation[] {
  if (!inspection) {
    return [];
  }
  const primaryRecommendations = inspection.primary_recommendation?.length
    ? inspection.primary_recommendation
    : inspection.recommendations?.length
      ? inspection.recommendations.slice(0, 1)
      : [inspectionRecommendationFallback(inspection)];
  return mapInspectionRecommendations(meta, primaryRecommendations).slice(0, limit);
}

export function inspectionAlternativeRecommendationChoices(
  meta: WorkbenchMeta | null,
  inspection: InputInspection | null,
  limit = 3,
): RankedInspectionRecommendation[] {
  if (!inspection) {
    return [];
  }
  const primaryIds = new Set(
    (inspection.primary_recommendation?.length
      ? inspection.primary_recommendation
      : inspection.recommendations?.slice(0, 1) ?? []
    ).map((item) => item.template_id),
  );
  const alternativeRecommendations = inspection.alternative_recommendations?.length
    ? inspection.alternative_recommendations
    : inspection.recommendations?.length
      ? inspection.recommendations.filter((item) => !primaryIds.has(item.template_id))
      : [];
  return mapInspectionRecommendations(meta, alternativeRecommendations).slice(0, limit);
}

export function inspectionAdvancedRecommendationChoices(
  meta: WorkbenchMeta | null,
  inspection: InputInspection | null,
  limit = 6,
): RankedInspectionRecommendation[] {
  if (!inspection) {
    return [];
  }
  const advancedRecommendations = inspection.advanced_templates?.length
    ? inspection.advanced_templates
    : [];
  return mapInspectionRecommendations(meta, advancedRecommendations).slice(0, limit);
}

export function inspectionRecommendationSections(
  meta: WorkbenchMeta | null,
  inspection: InputInspection | null,
  primaryLimit = 2,
  alternativeLimit = 3,
  advancedLimit = 6,
): InspectionRecommendationSections {
  return {
    primary: inspectionPrimaryRecommendationChoices(meta, inspection, primaryLimit),
    alternatives: inspectionAlternativeRecommendationChoices(meta, inspection, alternativeLimit),
    advanced: inspectionAdvancedRecommendationChoices(meta, inspection, advancedLimit),
  };
}

function inspectionRecommendationFallback(inspection: InputInspection): TemplateRecommendation {
  return {
    template_id: inspection.recommendation.template,
    score: 100,
    rank: 1,
    reason: inspection.recommendation.reason,
    suitability_hint: "Primary recommendation from compatibility inspection.",
    score_gap_to_top: 0,
    why_hard_match: [inspection.recommendation.reason],
    why_soft_prior: [],
    inferred_mapping: {},
    optional_enhancements: [],
    preview_config_summary: {
      size: inspection.recommendation.size,
      xscale: inspection.recommendation.xscale,
      yscale: inspection.recommendation.yscale,
      reverse_x: inspection.recommendation.reverse_x,
      baseline: inspection.recommendation.baseline,
      show_colorbar: inspection.recommendation.show_colorbar,
      style_preset: inspection.recommendation.style_preset,
      palette_preset: inspection.recommendation.palette_preset,
      use_sidecar: inspection.recommendation.use_sidecar,
    },
  };
}

export function inspectionRecommendationChoices(
  meta: WorkbenchMeta | null,
  inspection: InputInspection | null,
  limit = 5,
): RankedInspectionRecommendation[] {
  if (!inspection) {
    return [];
  }
  const primaryRecommendations = inspectionPrimaryRecommendationChoices(meta, inspection, limit);
  const alternativeLimit = Math.max(0, limit - primaryRecommendations.length);
  const alternativeRecommendations =
    alternativeLimit > 0
      ? inspectionAlternativeRecommendationChoices(meta, inspection, alternativeLimit)
      : [];
  const sourceRecommendations = primaryRecommendations.length || alternativeRecommendations.length
    ? [...primaryRecommendations, ...alternativeRecommendations]
    : mapInspectionRecommendations(
        meta,
        inspection.recommendations?.length
          ? inspection.recommendations
          : [inspectionRecommendationFallback(inspection)],
      );

  return sourceRecommendations.slice(0, limit);
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

function pickAllowedVisualTheme(
  meta: WorkbenchMeta | null,
  candidate: string | null | undefined,
): string | undefined {
  const available = meta?.visual_themes ?? [];
  if (!candidate) {
    return undefined;
  }
  if (available.length === 0) {
    return candidate;
  }
  return available.some((item) => item.id === candidate) ? candidate : undefined;
}

function pickAllowedStyle(
  meta: WorkbenchMeta | null,
  template: WorkbenchTemplate | null,
  candidate: string | undefined,
): StylePreset | undefined {
  const available = template?.available_styles ?? meta?.styles.map((item) => item.id) ?? [];
  if (candidate && available.includes(candidate as StylePreset)) {
    return candidate as StylePreset;
  }
  if (meta?.default_style && available.includes(meta.default_style)) {
    return meta.default_style;
  }
  return available[0];
}

export function sanitizeRenderOptions(
  meta: WorkbenchMeta | null,
  templateId: TemplateName | null | undefined,
  options: RenderOptionsPayload,
  inputModel?: string | null,
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
  if (allowed.has("style_preset")) {
    const style = pickAllowedStyle(meta, template, source.style_preset);
    if (style) {
      next.style_preset = style;
    }
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
  const visualThemeId = pickAllowedVisualTheme(meta, source.visual_theme_id);
  if (visualThemeId) {
    next.visual_theme_id = visualThemeId;
  }
  if (inputModel === "tensile_curve") {
    if (allowed.has("xscale")) {
      next.xscale = "linear";
    }
    if (allowed.has("yscale")) {
      next.yscale = "linear";
    }
  }

  return next;
}

export function mergeRenderOptions(
  meta: WorkbenchMeta | null,
  templateId: TemplateName | null | undefined,
  current: RenderOptionsPayload,
  patch: Partial<RenderOptionsPayload>,
  inputModel?: string | null,
): RenderOptionsPayload {
  return sanitizeRenderOptions(meta, templateId, {
    ...current,
    ...patch,
  }, inputModel);
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
    style_preset: recommendation.style_preset,
    palette_preset: recommendation.palette_preset,
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
  const primaryTemplateId =
    inspection.primary_recommendation?.[0]?.template_id ??
    inspection.recommendations?.[0]?.canonical_id ??
    inspection.recommendations?.[0]?.template_id ??
    inspection.recommendation.template;
  const template = sanitizeTemplateId(
    meta,
    overrides?.template ?? primaryTemplateId,
    primaryTemplateId,
  );
  return {
    template,
    options: sanitizeRenderOptions(meta, template, {
      ...inspectionOptions(inspection),
      ...(overrides?.options ?? {}),
    }, inspection.model),
  };
}

export function areRenderOptionsEqual(
  left: RenderOptionsPayload,
  right: RenderOptionsPayload,
): boolean {
  return ALL_RENDER_OPTION_KEYS.every((key) => left[key] === right[key]);
}

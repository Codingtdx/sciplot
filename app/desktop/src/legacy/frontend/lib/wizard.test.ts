import { describe, expect, it } from "vitest";

import type {
  InputInspection,
  TemplateRecommendation,
  WorkbenchMeta,
  WorkbenchTemplate,
} from "./types";
import {
  inspectionRecommendationSections,
  selectionFromInspection,
} from "./wizard";
import { TEST_META } from "../test/fixtures";

function makeTemplate(id: string, label: string, category = "statistics"): WorkbenchTemplate {
  return {
    id,
    label,
    description: label,
    category,
    default_size: "60x55",
    allowed_sizes: ["60x55"],
    editable_options: ["size", "style_preset", "palette_preset"],
    default_options: {
      size: "60x55",
      style_preset: "default",
      palette_preset: "colorblind_safe",
    },
    available_styles: ["default"],
    available_palettes: ["colorblind_safe"],
  };
}

function recommendation(
  template_id: string,
  score: number,
  rank: number,
  role: "canonical" | "alias" = "canonical",
  canonical_id = template_id,
): TemplateRecommendation {
  return {
    template_id,
    score,
    rank,
    reason: `${template_id} reason`,
    suitability_hint: `${template_id} hint`,
    score_gap_to_top: rank === 1 ? 0 : 1.5 * rank,
    why_hard_match: [`${template_id} hard`],
    why_soft_prior: [`${template_id} soft`],
    inferred_mapping: {},
    optional_enhancements: [],
    preview_config_summary: {},
    canonical_id,
    role,
    lifecycle_policy: role === "canonical" ? "canonical" : "deprecated_in_practice",
    implementation_id: canonical_id,
  };
}

const EXTRA_TEMPLATES = [
  makeTemplate("box", "Box"),
  makeTemplate("distribution_compare", "Distribution compare"),
  makeTemplate("box_strip", "Box strip"),
  makeTemplate("point_error", "Point error"),
  makeTemplate("violin", "Violin"),
  makeTemplate("grouped_bar_error", "Grouped bar error"),
  makeTemplate("violin_box", "Violin box"),
  makeTemplate("lollipop_error", "Lollipop error"),
];

const META: WorkbenchMeta = {
  ...TEST_META,
  templates: [...TEST_META.templates, ...EXTRA_TEMPLATES],
  template_ids: [...TEST_META.template_ids, ...EXTRA_TEMPLATES.map((template) => template.id)],
};

const INSPECTION: InputInspection = {
  model: "replicate_table",
  model_label: "Replicate wide table (replicate_table)",
  recommendation: {
    template: "grouped_bar_compare",
    reason: "Legacy compatibility path should not win over the primary lane.",
    size: "60x55",
  },
  recommendations: [
    recommendation("box", 80.0, 1),
    recommendation("distribution_compare", 79.8, 2),
    recommendation("box_strip", 77.0, 3),
    recommendation("point_error", 76.2, 4),
    recommendation("violin", 75.0, 5),
    recommendation("grouped_bar_error", 72.0, 6),
    recommendation("violin_box", 70.5, 7),
    recommendation("lollipop_error", 68.5, 8),
  ],
  primary_recommendation: [
    recommendation("box", 80.0, 1),
    recommendation("distribution_compare", 79.8, 2),
  ],
  alternative_recommendations: [
    recommendation("box_strip", 77.0, 3),
    recommendation("point_error", 76.2, 4),
    recommendation("violin", 75.0, 5),
  ],
  advanced_templates: [
    recommendation("grouped_bar_error", 72.0, 6),
    recommendation("violin_box", 70.5, 7),
    recommendation("lollipop_error", 68.5, 8),
  ],
  recommendation_confidence: 90.5,
  recommendation_summary:
    "High confidence: box and distribution_compare are co-primary templates for Replicate wide table (replicate_table) (score 80.0, gap 0.2).",
  warnings: [],
  signals: [],
};

describe("wizard recommendation mapping", () => {
  it("keeps primary, alternative, and advanced lanes separate while preferring canonical ids", () => {
    const sections = inspectionRecommendationSections(META, INSPECTION);

    expect(sections.primary.map((item) => item.template.id)).toEqual([
      "box",
      "distribution_compare",
    ]);
    expect(sections.alternatives.map((item) => item.template.id)).toEqual([
      "box_strip",
      "point_error",
      "violin",
    ]);
    expect(sections.advanced.map((item) => item.template.id)).toEqual([
      "grouped_bar_error",
      "violin_box",
      "lollipop_error",
    ]);
  });

  it("prefers the primary lane when choosing the template for a plot session", () => {
    const selection = selectionFromInspection(META, INSPECTION);

    expect(selection.template).toBe("box");
  });
});

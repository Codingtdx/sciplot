from __future__ import annotations

import unittest

from src.plot_contract import (
    lint_public_template_contract,
    load_plot_contract,
    meta_payload,
    normalize_style_alias,
    plot_contract_dict,
)

EXPECTED_STYLE_IDS = {
    "nature",
    "acs",
    "science",
    "wiley",
    "elsevier",
    "editorial",
    "presentation",
    "poster",
}

EXPECTED_PUBLICATION_STYLE_IDS = {"nature", "acs", "science", "wiley", "elsevier"}
EXPECTED_LEGACY_DISPLAY_STYLE_IDS = {"editorial", "presentation", "poster"}
EXPECTED_FIGURE_SIZE_IDS = {
    "60x55",
    "120x55",
    "180x55",
    "60x110",
    "120x110",
    "180x110",
}


class PlotContractTests(unittest.TestCase):
    def test_meta_payload_matches_contract_defaults_and_templates(self) -> None:
        contract = load_plot_contract()
        meta = meta_payload()
        removed_template_ids = {
            "grouped_bar_error",
            "scatter_with_fit",
            "replicate_curves_with_band",
            "grouped_bar_compare",
            "distribution_compare",
        }

        self.assertEqual(meta["defaults"]["style_preset"], contract.defaults.style_preset)
        self.assertEqual(meta["defaults"]["palette_preset"], contract.defaults.palette_preset)
        self.assertEqual(contract.defaults.style_preset, "nature")
        self.assertEqual({item["id"] for item in meta["styles"]}, EXPECTED_STYLE_IDS)
        self.assertEqual(set(contract.styles.keys()), EXPECTED_STYLE_IDS)
        self.assertEqual(
            {item["id"] for item in meta["styles"] if item["display_group"] == "publication"},
            EXPECTED_PUBLICATION_STYLE_IDS,
        )
        self.assertEqual(
            {item["id"] for item in meta["styles"] if item["display_group"] == "legacy_display"},
            EXPECTED_LEGACY_DISPLAY_STYLE_IDS,
        )
        self.assertEqual(contract.styles["nature"].recommended_palette_preset, "colorblind_safe")
        self.assertEqual(contract.styles["nature"].recommended_visual_theme_id, "clean_light")
        self.assertEqual(contract.styles["nature"].display_group, "publication")
        self.assertEqual(contract.styles["acs"].recommended_palette_preset, "okabe_ito")
        self.assertEqual(contract.styles["acs"].recommended_visual_theme_id, "clean_light")
        self.assertEqual(contract.styles["science"].recommended_palette_preset, "colorblind_safe")
        self.assertEqual(contract.styles["science"].recommended_visual_theme_id, "clean_light")
        self.assertEqual(contract.styles["wiley"].recommended_palette_preset, "tol_muted")
        self.assertEqual(contract.styles["wiley"].recommended_visual_theme_id, "clean_light")
        self.assertEqual(contract.styles["elsevier"].recommended_palette_preset, "muted")
        self.assertEqual(contract.styles["elsevier"].recommended_visual_theme_id, "clean_light")
        self.assertEqual(contract.styles["editorial"].recommended_palette_preset, "roma")
        self.assertEqual(contract.styles["editorial"].display_group, "legacy_display")
        self.assertEqual(contract.styles["presentation"].recommended_visual_theme_id, "presentation_like")
        self.assertTrue(
            {
                "infographic",
                "roma",
                "macarons",
                "shine",
                "vintage",
                "tableau_10",
                "seaborn_pastel",
                "seaborn_dark",
                "primer_accessible",
                "viridis_discrete",
            }.issubset(
                {item["id"] for item in meta["palettes"]}
            )
        )
        self.assertIn("area_curve", contract.templates)
        self.assertIn("step_line", contract.templates)
        self.assertIn("stacked_area", contract.templates)
        self.assertIn("density_area", contract.templates)
        self.assertIn("function_curve", contract.templates)
        self.assertIn("contour_field", contract.templates)
        self.assertIn("polar_curve", contract.templates)
        self.assertIn("table_figure", contract.templates)
        self.assertEqual(
            {item["id"] for item in meta["templates"]},
            set(contract.templates.keys()),
        )
        self.assertTrue(removed_template_ids.isdisjoint(contract.templates))
        self.assertTrue(removed_template_ids.isdisjoint({item["id"] for item in meta["templates"]}))
        self.assertEqual(
            {item["id"] for item in meta["sizes"]},
            EXPECTED_FIGURE_SIZE_IDS,
        )
        self.assertEqual(set(contract.size_presets.keys()), EXPECTED_FIGURE_SIZE_IDS)
        self.assertEqual(contract.size_presets["120x110"].label, "Large 120 x 110 mm")
        self.assertEqual(contract.size_presets["120x110"].width_mm, 120.0)
        self.assertEqual(contract.size_presets["120x110"].height_mm, 110.0)
        self.assertEqual(
            {item["id"] for item in meta["palettes"]},
            set(contract.palettes.keys()),
        )

        for template in meta["templates"]:
            self.assertIn(template["id"], contract.templates)
            self.assertIn("presentation_kind", template)
            self.assertIn(template["default_size"], template["allowed_sizes"])
            self.assertEqual(set(template["available_styles"]), EXPECTED_STYLE_IDS)
            self.assertIn("recommended_palette_preset", next(item for item in meta["styles"] if item["id"] == "nature"))
            self.assertIn("palette_preset", template["default_options"])
            self.assertIn("visual_theme_id", template["default_options"])
            self.assertEqual(template["presentation_kind"], contract.templates[template["id"]].presentation_kind)

        for template in contract.templates.values():
            if "size" in template.editable_options:
                self.assertEqual(set(template.allowed_sizes), EXPECTED_FIGURE_SIZE_IDS)
            self.assertEqual(set(template.available_styles), EXPECTED_STYLE_IDS)
            self.assertIsNotNone(template.default_options.get("style_preset"))
            self.assertIsNotNone(template.default_options.get("palette_preset"))
            self.assertIsNotNone(template.default_options.get("visual_theme_id"))
            style_spec = contract.styles[str(template.default_options["style_preset"])]
            self.assertEqual(template.default_options.get("palette_preset"), style_spec.recommended_palette_preset)
            self.assertEqual(template.default_options.get("visual_theme_id"), style_spec.recommended_visual_theme_id)

    def test_public_template_contract_lint_passes(self) -> None:
        self.assertEqual(lint_public_template_contract(), ())

    def test_plot_contract_dict_exposes_validation_rules_from_loader(self) -> None:
        contract = load_plot_contract()
        contract_dict = plot_contract_dict()

        self.assertIn("axis_policy", contract_dict)
        self.assertEqual(
            contract_dict["axis_policy"]["linear_outer_padding_fraction"],
            contract.axis_policy.linear_outer_padding_fraction,
        )
        self.assertEqual(
            set(contract_dict["validation_rules"].keys()),
            set(contract.validation_rules.keys()),
        )
        self.assertEqual(
            set(contract_dict["templates"].keys()),
            set(contract.templates.keys()),
        )
        self.assertEqual(set(contract_dict["styles"].keys()), EXPECTED_STYLE_IDS)
        self.assertEqual(
            contract_dict["aliases"]["style_presets"],
            {
                "default": "nature",
                "lab_default": "nature",
                "science_editorial": "nature",
                "jacs_analytical": "nature",
                "advanced_materials_spacious": "nature",
                "jacs": "acs",
                "aaas": "science",
                "advanced_materials": "wiley",
            },
        )
        self.assertEqual(contract_dict["styles"]["nature"]["recommended_palette_preset"], "colorblind_safe")
        self.assertEqual(contract_dict["styles"]["nature"]["recommended_visual_theme_id"], "clean_light")
        self.assertEqual(contract_dict["styles"]["acs"]["display_group"], "publication")
        self.assertEqual(contract_dict["styles"]["poster"]["display_group"], "legacy_display")
        self.assertEqual(
            contract_dict["styles"]["elsevier"]["axis_frame"],
            {"left": True, "bottom": True, "top": True, "right": True},
        )

    def test_public_styles_declare_axis_frame_in_contract(self) -> None:
        contract = load_plot_contract()
        open_axis = {"left": True, "bottom": True, "top": False, "right": False}

        for style_id, style_spec in contract.styles.items():
            self.assertIsNotNone(style_spec.axis_frame, style_id)

        self.assertEqual(contract.styles["nature"].axis_frame.__dict__, open_axis)
        self.assertEqual(contract.styles["acs"].axis_frame.__dict__, open_axis)
        self.assertEqual(contract.styles["science"].axis_frame.__dict__, open_axis)
        self.assertEqual(contract.styles["wiley"].axis_frame.__dict__, open_axis)
        self.assertEqual(
            contract.styles["elsevier"].axis_frame.__dict__,
            {"left": True, "bottom": True, "top": True, "right": True},
        )

    def test_nature_publication_style_remains_frozen(self) -> None:
        nature = load_plot_contract().styles["nature"]

        self.assertTrue(nature.hard_constraints)
        self.assertEqual(nature.display_group, "publication")
        self.assertEqual(nature.typography.font_family, ("Arial", "Helvetica", "DejaVu Sans"))
        self.assertEqual(nature.typography.font_size_pt, 6.5)
        self.assertEqual(nature.typography.legend_font_size_pt, 5.8)
        self.assertEqual(nature.typography.panel_label_size_pt, 8.0)
        self.assertEqual(nature.stroke.axis_linewidth_pt, 1.0)
        self.assertEqual(nature.stroke.tick_width_pt, 1.0)
        self.assertEqual(nature.stroke.tick_length_pt, 3.4)
        self.assertEqual(nature.stroke.line_width_pt, 1.2)
        self.assertEqual(nature.stroke.marker_size_pt, 3.4)
        self.assertEqual(nature.spacing.axes_labelpad, 2.0)
        self.assertEqual(nature.spacing.xtick_major_pad, 1.4)
        self.assertEqual(nature.spacing.ytick_major_pad, 1.4)
        self.assertEqual(nature.annotation.legend_frameon, False)
        self.assertEqual(nature.axis_frame.__dict__, {"left": True, "bottom": True, "top": False, "right": False})

    def test_new_publication_aliases_normalize_without_reusing_legacy_alias_ids(self) -> None:
        self.assertEqual(normalize_style_alias("jacs"), "acs")
        self.assertEqual(normalize_style_alias("aaas"), "science")
        self.assertEqual(normalize_style_alias("advanced_materials"), "wiley")
        self.assertEqual(normalize_style_alias("jacs_analytical"), "nature")
        self.assertEqual(normalize_style_alias("science_editorial"), "nature")
        self.assertEqual(normalize_style_alias("advanced_materials_spacious"), "nature")

    def test_tick_label_controls_are_exposed_only_on_supported_axes(self) -> None:
        contract = load_plot_contract()

        curve_options = set(contract.templates["curve"].editable_options)
        box_options = set(contract.templates["box"].editable_options)

        self.assertTrue(
            {"x_tick_density", "x_tick_edge_labels", "y_tick_density", "y_tick_edge_labels"}.issubset(curve_options)
        )
        self.assertIn("extra_x_axis", curve_options)
        self.assertIn("extra_y_axis", curve_options)
        self.assertIn("x_axis_breaks", curve_options)
        self.assertIn("y_axis_breaks", curve_options)
        self.assertIn("y_tick_density", box_options)
        self.assertIn("y_tick_edge_labels", box_options)
        self.assertNotIn("x_tick_density", box_options)
        self.assertNotIn("x_tick_edge_labels", box_options)
        self.assertNotIn("extra_x_axis", box_options)
        self.assertNotIn("extra_y_axis", box_options)
        self.assertNotIn("x_axis_breaks", box_options)
        self.assertNotIn("y_axis_breaks", box_options)

        function_options = set(contract.templates["function_curve"].editable_options)
        self.assertIn("analytical_layers", function_options)


if __name__ == "__main__":
    unittest.main()

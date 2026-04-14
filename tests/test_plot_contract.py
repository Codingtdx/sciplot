from __future__ import annotations

import unittest

from src.plot_contract import load_plot_contract, meta_payload, plot_contract_dict


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
        self.assertEqual({item["id"] for item in meta["styles"]}, {"nature"})
        self.assertEqual(set(contract.styles.keys()), {"nature"})
        self.assertEqual(
            {item["id"] for item in meta["templates"]},
            set(contract.templates.keys()),
        )
        self.assertTrue(removed_template_ids.isdisjoint(contract.templates))
        self.assertTrue(removed_template_ids.isdisjoint({item["id"] for item in meta["templates"]}))
        self.assertEqual(
            {item["id"] for item in meta["sizes"]},
            set(contract.size_presets.keys()),
        )
        self.assertEqual(
            {item["id"] for item in meta["palettes"]},
            set(contract.palettes.keys()),
        )

        for template in meta["templates"]:
            self.assertIn(template["id"], contract.templates)
            self.assertIn("presentation_kind", template)
            self.assertIn(template["default_size"], template["allowed_sizes"])
            self.assertEqual(template["available_styles"], ["nature"])
            self.assertEqual(template["presentation_kind"], contract.templates[template["id"]].presentation_kind)

        for template in contract.templates.values():
            self.assertEqual(template.available_styles, ("nature",))
            self.assertEqual(template.default_options.get("style_preset"), "nature")

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
        self.assertEqual(set(contract_dict["styles"].keys()), {"nature"})
        self.assertEqual(
            contract_dict["aliases"]["style_presets"],
            {
                "default": "nature",
                "lab_default": "nature",
                "science_editorial": "nature",
                "jacs_analytical": "nature",
                "advanced_materials_spacious": "nature",
            },
        )

    def test_tick_label_controls_are_exposed_only_on_supported_axes(self) -> None:
        contract = load_plot_contract()

        curve_options = set(contract.templates["curve"].editable_options)
        box_options = set(contract.templates["box"].editable_options)

        self.assertTrue(
            {"x_tick_density", "x_tick_edge_labels", "y_tick_density", "y_tick_edge_labels"}.issubset(curve_options)
        )
        self.assertIn("y_tick_density", box_options)
        self.assertIn("y_tick_edge_labels", box_options)
        self.assertNotIn("x_tick_density", box_options)
        self.assertNotIn("x_tick_edge_labels", box_options)


if __name__ == "__main__":
    unittest.main()

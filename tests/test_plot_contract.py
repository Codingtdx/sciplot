from __future__ import annotations

import unittest

from src.plot_contract import load_plot_contract, meta_payload, plot_contract_dict


class PlotContractTests(unittest.TestCase):
    def test_meta_payload_matches_contract_defaults_and_templates(self) -> None:
        contract = load_plot_contract()
        meta = meta_payload()

        self.assertEqual(meta["defaults"]["style_preset"], contract.defaults.style_preset)
        self.assertEqual(meta["defaults"]["palette_preset"], contract.defaults.palette_preset)
        self.assertEqual(
            {item["id"] for item in meta["templates"]},
            set(contract.templates.keys()),
        )
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
            self.assertIn(template["default_size"], template["allowed_sizes"])

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


if __name__ == "__main__":
    unittest.main()

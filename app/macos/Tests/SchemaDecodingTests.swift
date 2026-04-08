import Foundation
import XCTest
@testable import SciPlotGodMac

final class SchemaDecodingTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func testDecodeRenderInspectionPayload() throws {
        let payload = """
        {
          "input_path": "/tmp/sample.csv",
          "sheet": "Representative_Curve",
          "sheet_names": ["Representative_Curve", "Strength_Box"],
          "inspection": {
            "model": "tensile_curve",
            "model_label": "Tensile Curve",
            "recommendations": [],
            "primary_recommendation": [],
            "alternative_recommendations": [],
            "advanced_templates": [],
            "recommendation_confidence": 0.92,
            "recommendation_summary": "Curve is recommended",
            "warnings": [],
            "signals": ["tensile_curve"]
          },
          "dataset": {
            "dataset_id": "dataset-1",
            "source_path": "/tmp/sample.csv",
            "sheet": "Representative_Curve",
            "model": "tensile_curve",
            "raw_rows": 2,
            "raw_cols": 2,
            "column_profiles": [],
            "candidate_roles": {
              "x": [],
              "y": [],
              "z": [],
              "group": [],
              "sample": [],
              "value": [],
              "metric": [],
              "label": [],
              "series": []
            },
            "data_shapes": ["curve_table"],
            "semantic_signals": ["tensile_curve"],
            "quality_flags": [],
            "sample_rows": [[0.0, 1.0], [0.1, 2.0]]
          }
        }
        """

        let response = try decoder.decode(InspectFileResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.sheet, .name("Representative_Curve"))
        XCTAssertEqual(response.inspection.model, "tensile_curve")
        XCTAssertEqual(response.dataset?.sampleRows.count, 2)
    }

    func testDecodeDataStudioWorkbookAndComparisonPayloads() throws {
        let workbookPayload = """
        {
          "workbook_id": "workbook-1",
          "workbook_path": "/tmp/prepared.xlsx",
          "label": "Primary Group",
          "template_match": {
            "template_id": "builtin/tensile",
            "label": "Tensile",
            "family": "tensile",
            "confidence": 0.98,
            "reasons": ["Built with the selected Data Studio template."],
            "warnings": [],
            "matched_sheet_names": ["Representative_Curve"],
            "auto_selected": true
          },
          "source_files": ["/tmp/raw_a.csv"],
          "sheet_names": ["Representative_Curve"],
          "preferred_sheet": "Representative_Curve",
          "parsed_sample_count": 2,
          "failed_sample_count": 1,
          "representative_filename": "raw_a.csv",
          "metrics": [{"id": "strength", "label": "Strength", "unit": "MPa", "mean": 12.4, "std": 0.4}],
          "warnings": [],
          "exclusions": [],
          "samples": []
        }
        """

        let comparisonPayload = """
        {
          "comparison_set": {
            "id": "primary-vs-second",
            "label": "Primary Group vs Second Group",
            "workbook_paths": ["/tmp/prepared.xlsx", "/tmp/second.xlsx"],
            "workbook_labels": ["Primary Group", "Second Group"],
            "comparison_workbook_path": "/tmp/exports/comparison.xlsx",
            "recipes": [
              {
                "id": "representative_curve",
                "label": "Representative Curve Compare",
                "category": "curve",
                "template_id": "curve",
                "sheet_name": "Representative_Curve",
                "metric_id": null,
                "enabled_by_default": true,
                "supported": true,
                "support_reason": ""
              }
            ]
          },
          "recipe": {
            "id": "representative_curve",
            "label": "Representative Curve Compare",
            "category": "curve",
            "template_id": "curve",
            "sheet_name": "Representative_Curve",
            "metric_id": null,
            "enabled_by_default": true,
            "supported": true,
            "support_reason": ""
          },
          "preview": {
            "filename": "representative_curve.pdf",
            "pdf_base64": "\(TestPayloads.pdfBase64)"
          }
        }
        """

        let workbook = try decoder.decode(DataStudioWorkbookResponse.self, from: Data(workbookPayload.utf8))
        let comparison = try decoder.decode(DataStudioComparisonPreviewResponse.self, from: Data(comparisonPayload.utf8))

        XCTAssertEqual(workbook.templateMatch.templateID, "builtin/tensile")
        XCTAssertEqual(workbook.metrics.first?.label, "Strength")
        XCTAssertEqual(comparison.recipe.id, "representative_curve")
        XCTAssertEqual(comparison.comparisonSet.workbookLabels.count, 2)
    }

    func testDecodePlotContractSizePresetsWithoutIDField() throws {
        let payload = """
        {
          "version": 1,
          "defaults": {
            "style_preset": "journal_calm",
            "palette_preset": "aqua_graphite"
          },
          "size_presets": {
            "single_panel": {
              "label": "Single Panel",
              "width_mm": 60,
              "height_mm": 55
            }
          },
          "styles": {},
          "palettes": {},
          "templates": {
            "curve": {
              "label": "Curve",
              "description": "Continuous curve template.",
              "category": "curve",
              "default_size": "single_panel",
              "allowed_sizes": ["single_panel"],
              "editable_options": ["size", "xscale", "yscale"],
              "default_options": {},
              "available_styles": ["journal_calm"],
              "available_palettes": ["aqua_graphite"],
              "hard_rules": [],
              "soft_rules": []
            }
          }
        }
        """

        let response = try decoder.decode(PlotContractResponse.self, from: Data(payload.utf8))
        XCTAssertEqual(response.sizePresets["single_panel"]?.widthMm, 60)
        XCTAssertEqual(response.sizePresets["single_panel"]?.heightMm, 55)
    }

    func testDecodeMetaPayloadWithSnakeCaseIDCollections() throws {
        let payload = """
        {
          "version": 1,
          "defaults": {
            "style_preset": "default",
            "palette_preset": "colorblind_safe"
          },
          "sizes": [
            {
              "id": "60x55",
              "label": "60 x 55 mm",
              "width_mm": 60,
              "height_mm": 55
            }
          ],
          "styles": [
            {
              "id": "default",
              "label": "Default",
              "public": true,
              "description": "Default style",
              "hard_constraints": true,
              "preset_note": "Repo default"
            }
          ],
          "palettes": [
            {
              "id": "colorblind_safe",
              "label": "Colorblind Safe",
              "public": true,
              "description": "Default palette",
              "swatches": ["#123456", "#abcdef"]
            }
          ],
          "templates": [
            {
              "id": "curve",
              "label": "Curve",
              "description": "Continuous curve template.",
              "category": "curve",
              "default_size": "60x55",
              "allowed_sizes": ["60x55"],
              "editable_options": ["size", "style_preset", "palette_preset"],
              "default_options": {},
              "available_styles": ["default"],
              "available_palettes": ["colorblind_safe"],
              "canonical_id": "curve",
              "role": "canonical",
              "lifecycle_policy": "canonical",
              "implementation_id": "plot.curve"
            }
          ],
          "template_ids": ["curve"],
          "size_ids": ["60x55"],
          "palette_preset_ids": ["colorblind_safe"],
          "visual_themes": [
            {
              "id": "clean_light",
              "label": "Clean Light",
              "description": "A minimal theme"
            }
          ]
        }
        """

        let response = try decoder.decode(SidecarMetaResponse.self, from: Data(payload.utf8))
        XCTAssertEqual(response.templateIds, ["curve"])
        XCTAssertEqual(response.sizeIds, ["60x55"])
        XCTAssertEqual(response.palettePresetIds, ["colorblind_safe"])
        XCTAssertEqual(response.visualThemes.first?.id, "clean_light")
    }

    func testDecodeComposerPreviewPayload() throws {
        let payload = """
        {
          "valid": true,
          "validation_error": null,
          "png_base64": "\(TestPayloads.pngBase64)",
          "qa": null,
          "submission_report": {
            "context": "composer",
            "readiness": "ready",
            "summary": "Looks good.",
            "template": null,
            "style_preset": null,
            "palette_preset": null,
            "output_count": 1,
            "output_filenames": ["figure.pdf"],
            "blockers": [],
            "checks": []
          },
          "suggested_project_patch": []
        }
        """

        let response = try decoder.decode(ComposerPreviewResponse.self, from: Data(payload.utf8))

        XCTAssertTrue(response.valid)
        XCTAssertEqual(response.submissionReport?.readiness, "ready")
    }
}

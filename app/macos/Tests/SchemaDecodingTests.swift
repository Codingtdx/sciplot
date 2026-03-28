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
            "recommendation": {
              "template": "curve",
              "reason": "Compatible",
              "size": "single_panel",
              "xscale": "linear",
              "yscale": "linear",
              "reverse_x": false,
              "baseline": null,
              "show_colorbar": null,
              "style_preset": "journal_calm",
              "palette_preset": "aqua_graphite",
              "use_sidecar": true
            },
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

    func testDecodeTensilePreprocessPayload() throws {
        let payload = """
        {
          "output_path": "/tmp/prepared.xlsx",
          "group_name": "Primary Group",
          "preferred_sheet": "Representative_Curve",
          "sheet_names": ["Representative_Curve"],
          "sample_count": 3,
          "representative_filename": "sample.csv",
          "metrics": [{"label": "Strength", "unit": "MPa", "mean": 12.4, "std": 0.4}],
          "warnings": []
        }
        """

        let response = try decoder.decode(TensileReplicateResponseModel.self, from: Data(payload.utf8))

        XCTAssertEqual(response.groupName, "Primary Group")
        XCTAssertEqual(response.preferredSheet, "Representative_Curve")
        XCTAssertEqual(response.metrics.first?.label, "Strength")
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

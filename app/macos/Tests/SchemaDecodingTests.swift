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

    func testDecodeSourceTablePreviewKeepsScalarFieldRoles() throws {
        let payload = """
        {
          "input_path": "/tmp/field.csv",
          "sheet": 0,
          "offset": 0,
          "limit": 50,
          "total_rows": 7,
          "total_cols": 3,
          "column_headers": ["X", "Y", "Z"],
          "rows": [[25, 0, 0.18], [25, 5, 0.31]],
          "candidate_roles": {
            "x": ["Temperature"],
            "y": ["Time"],
            "z": ["Intensity"],
            "group": [],
            "sample": [],
            "value": [],
            "metric": [],
            "label": [],
            "series": []
          },
          "detected_x_label": "Temperature",
          "detected_y_label": "Time",
          "column_profiles": [],
          "segments": [],
          "selected_segment_id": null,
          "encoding": "utf-8",
          "delimiter": ","
        }
        """

        let response = try decoder.decode(SourceTablePreviewResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.candidateRoles.x, ["Temperature"])
        XCTAssertEqual(response.candidateRoles.y, ["Time"])
        XCTAssertEqual(response.candidateRoles.z, ["Intensity"])
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

    func testDecodeDataStudioTemplatePreviewPayloadUsesTemplateID() throws {
        let payload = """
        {
          "template_id": "user/e0",
          "output_kind": "curve_metrics",
          "parsed_sample_count": 1,
          "failed_sample_count": 0,
          "series_count": 4,
          "metric_count": 2,
          "matrix_row_count": 0,
          "missing_roles": [],
          "warnings": [],
          "errors": [],
          "segments": [
            {
              "id": "seg-1",
              "label": "Frequency sweep 1 / Interval 1",
              "curve_count": 4,
              "metric_count": 2,
              "row_count": 19
            }
          ]
        }
        """

        let preview = try decoder.decode(DataStudioTemplatePreviewResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(preview.templateID, "user/e0")
        XCTAssertEqual(preview.outputKind, "curve_metrics")
        XCTAssertEqual(preview.segments.first?.id, "seg-1")
    }

    func testDecodeRenderRequestWithExtraAxes() throws {
        let payload = """
        {
          "input_path": "/tmp/sample.csv",
          "sheet": 0,
          "template": "curve",
          "options": {
            "style_preset": "nature",
            "palette_preset": "colorblind_safe",
            "extra_x_axis": {
              "enabled": true,
              "position": "top",
              "title": "Gallons",
              "data_value": 3.78541,
              "display_value": 1.0
            },
            "extra_y_axis": {
              "enabled": true,
              "position": "right",
              "title": "Half Stress",
              "data_value": 2.0,
              "display_value": 1.0
            },
            "x_axis_breaks": [
              {
                "id": "x-gap",
                "enabled": true,
                "start": 0.8,
                "end": 1.2,
                "display_mode": "split"
              }
            ],
            "y_axis_breaks": [
              {
                "id": "y-gap",
                "enabled": true,
                "start": 1.4,
                "end": 2.2
              }
            ],
            "reference_guides": [
              {
                "id": "target-line",
                "enabled": true,
                "kind": "line",
                "axis_target": "y_primary",
                "value": 2.5,
                "label": "Target"
              }
            ],
            "text_annotations": [
              {
                "id": "note-1",
                "enabled": true,
                "text": "Peak",
                "coordinate_space": "data",
                "x": 1.5,
                "y": 2.2,
                "y_axis_target": "y_primary",
                "horizontal_alignment": "right",
                "vertical_alignment": "bottom",
                "display_style": "callout",
                "connector_enabled": true,
                "target_x": 1.0,
                "target_y": 1.8,
                "target_y_axis_target": "y_primary"
              }
            ],
            "shape_annotations": [
              {
                "id": "focus-window",
                "enabled": true,
                "kind": "rectangle",
                "bracket_orientation": "horizontal",
                "x_start": 0.5,
                "x_end": 1.5,
                "y_start": 1.8,
                "y_end": 2.6,
                "y_axis_target": "y_primary",
                "label": "Window"
              }
            ],
            "analytical_layers": [
              {
                "id": "function-1",
                "enabled": true,
                "kind": "function",
                "expression": "sin(x) + 1",
                "x_start": 0,
                "x_end": 3,
                "sample_count": 120,
                "y_axis_target": "y_primary",
                "label": "Model"
              }
            ],
            "data_variables": [
              {
                "id": "scale",
                "enabled": true,
                "kind": "scalar",
                "label": "Scale",
                "value": 2
              }
            ],
            "data_transforms": [
              {
                "id": "filter-1",
                "enabled": true,
                "kind": "row_filter",
                "label": "Window",
                "column": "Time",
                "operator": "between",
                "lower": 1,
                "upper": 2,
                "columns": ["Time"],
                "target_type": "number",
                "bins": 8,
                "window": 3,
                "group_by": ["Group"],
                "value_columns": ["Stress"],
                "statistics": ["mean", "sd"]
              }
            ]
          },
          "fit_options": {
            "enabled": false,
            "model_id": "linear"
          }
        }
        """

        let request = try decoder.decode(RenderRequest.self, from: Data(payload.utf8))

        XCTAssertEqual(request.options.extraXAxis?.position, "top")
        XCTAssertEqual(request.options.extraXAxis?.title, "Gallons")
        XCTAssertEqual(request.options.extraXAxis?.bindingMode, "conversion")
        XCTAssertEqual(request.options.extraXAxis?.seriesIDs, [])
        XCTAssertEqual(request.options.extraYAxis?.position, "right")
        XCTAssertEqual(request.options.extraYAxis?.bindingMode, "conversion")
        XCTAssertEqual(request.options.extraYAxis?.seriesIDs, [])
        XCTAssertEqual(request.options.extraYAxis?.displayValue, 1.0)
        XCTAssertEqual(request.options.xAxisBreaks?.first?.id, "x-gap")
        XCTAssertEqual(request.options.xAxisBreaks?.first?.start, 0.8)
        XCTAssertEqual(request.options.xAxisBreaks?.first?.displayMode, "split")
        XCTAssertEqual(request.options.yAxisBreaks?.first?.end, 2.2)
        XCTAssertEqual(request.options.yAxisBreaks?.first?.displayMode, "compress")
        XCTAssertEqual(request.options.referenceGuides?.first?.kind, "line")
        XCTAssertEqual(request.options.referenceGuides?.first?.axisTarget, "y_primary")
        XCTAssertEqual(request.options.textAnnotations?.first?.displayStyle, "callout")
        XCTAssertEqual(request.options.textAnnotations?.first?.connectorEnabled, true)
        XCTAssertEqual(request.options.shapeAnnotations?.first?.kind, "rectangle")
        XCTAssertEqual(request.options.shapeAnnotations?.first?.label, "Window")
        XCTAssertEqual(request.options.analyticalLayers?.first?.expression, "sin(x) + 1")
        XCTAssertEqual(request.options.analyticalLayers?.first?.sampleCount, 120)
        XCTAssertEqual(request.options.analyticalLayers?.first?.yAxisTarget, "y_primary")
        XCTAssertEqual(request.options.dataVariables?.first?.id, "scale")
        XCTAssertEqual(request.options.dataVariables?.first?.value, 2.0)
        XCTAssertEqual(request.options.dataTransforms?.first?.kind, "row_filter")
        XCTAssertEqual(request.options.dataTransforms?.first?.filterOperator, "between")
        XCTAssertEqual(request.options.dataTransforms?.first?.lower, 1.0)
        XCTAssertEqual(request.options.dataTransforms?.first?.columns, ["Time"])
        XCTAssertEqual(request.options.dataTransforms?.first?.bins, 8)
        XCTAssertEqual(request.options.dataTransforms?.first?.groupBy, ["Group"])
    }

    func testDecodePlotContractSizePresetsWithoutIDField() throws {
        let payload = """
        {
          "version": 1,
          "defaults": {
            "style_preset": "nature",
            "palette_preset": "colorblind_safe"
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
              "presentation_kind": "curve",
              "default_size": "single_panel",
              "allowed_sizes": ["single_panel"],
              "editable_options": ["size", "xscale", "yscale"],
              "default_options": {},
              "available_styles": ["nature"],
              "available_palettes": ["colorblind_safe"],
              "hard_rules": [],
              "soft_rules": []
            }
          }
        }
        """

        let response = try decoder.decode(PlotContractResponse.self, from: Data(payload.utf8))
        XCTAssertEqual(response.sizePresets["single_panel"]?.widthMm, 60)
        XCTAssertEqual(response.sizePresets["single_panel"]?.heightMm, 55)
        XCTAssertEqual(response.templates["curve"]?.presentationKind, "curve")
    }

    func testDecodeMetaPayloadWithSnakeCaseIDCollections() throws {
        let payload = """
        {
          "version": 1,
          "defaults": {
            "style_preset": "nature",
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
              "id": "nature",
              "label": "Nature",
              "public": true,
              "description": "Nature style",
              "hard_constraints": true,
              "preset_note": "Repo nature",
              "recommended_palette_preset": "colorblind_safe",
              "recommended_visual_theme_id": "clean_light"
            },
            {
              "id": "editorial",
              "label": "Editorial",
              "public": true,
              "description": "Editorial style",
              "hard_constraints": false,
              "preset_note": "Relaxed preset",
              "recommended_palette_preset": "roma",
              "recommended_visual_theme_id": "roma"
            }
          ],
          "palettes": [
            {
              "id": "colorblind_safe",
              "label": "Colorblind Safe",
              "public": true,
              "description": "Default palette",
              "swatches": ["#123456", "#abcdef"]
            },
            {
              "id": "shine",
              "label": "Shine",
              "public": true,
              "description": "Bright palette",
              "swatches": ["#c12e34", "#e6b600"]
            }
          ],
          "templates": [
            {
              "id": "curve",
              "label": "Curve",
              "description": "Continuous curve template.",
              "category": "curve",
              "presentation_kind": "curve",
              "default_size": "60x55",
              "allowed_sizes": ["60x55"],
              "editable_options": ["size", "style_preset", "palette_preset"],
              "default_options": {
                "style_preset": "presentation",
                "palette_preset": "roma",
                "visual_theme_id": "roma"
              },
              "available_styles": ["nature", "editorial", "presentation"],
              "available_palettes": ["colorblind_safe", "roma", "macarons", "shine"],
              "canonical_id": "curve",
              "role": "canonical",
              "lifecycle_policy": "canonical",
              "implementation_id": "plot.curve"
            }
          ],
          "template_ids": ["curve"],
          "size_ids": ["60x55"],
          "palette_preset_ids": ["colorblind_safe", "roma", "macarons", "shine"],
          "visual_themes": [
            {
              "id": "clean_light",
              "label": "Clean Light",
              "description": "A minimal theme"
            },
            {
              "id": "roma",
              "label": "Roma",
              "description": "A warm neutral theme"
            },
            {
              "id": "shine",
              "label": "Shine",
              "description": "A brighter theme"
            }
          ]
        }
        """

        let response = try decoder.decode(SidecarMetaResponse.self, from: Data(payload.utf8))
        XCTAssertEqual(response.templateIds, ["curve"])
        XCTAssertEqual(response.sizeIds, ["60x55"])
        XCTAssertEqual(response.palettePresetIds, ["colorblind_safe", "roma", "macarons", "shine"])
        XCTAssertEqual(response.visualThemes.first?.id, "clean_light")
        XCTAssertEqual(response.templates.first?.presentationKind, "curve")
        XCTAssertEqual(response.templates.first?.defaultOptions["style_preset"]?.stringValue, "presentation")
        XCTAssertEqual(response.templates.first?.defaultOptions["palette_preset"]?.stringValue, "roma")
        XCTAssertEqual(response.templates.first?.defaultOptions["visual_theme_id"]?.stringValue, "roma")
        XCTAssertEqual(response.styles.first?.recommendedPalettePreset, "colorblind_safe")
        XCTAssertEqual(response.styles.first?.recommendedVisualThemeID, "clean_light")
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

    func testDecodeSaveProjectResponsePreservesPlotSourceSHA256() throws {
        let payload = """
        {
          "project_path": "/tmp/sample.sciplotgod",
          "payload": {
            "version": 1,
            "selected_workbench": "plot",
            "plot": {
              "session_kind": "plot",
              "source_filename": "sample.csv",
              "source_media_type": "text/csv",
              "embedded_source_relpath": "sources/plot/primary/sample.csv",
              "source_sha256": "abc123",
              "sheet": "Representative_Curve",
              "selected_template_id": "curve",
              "render_options": {
                "size": "60x55",
                "style_preset": "nature",
                "palette_preset": "colorblind_safe",
                "visual_theme_id": "clean_light"
              },
              "fit_options": {
                "enabled": false,
                "model_id": "linear"
              },
              "project_display_name": "Sample Project",
              "source_provenance": {
                "original_input_path": "/tmp/sample.csv",
                "saved_input_mtime_ns": 123,
                "saved_at": "2026-04-26T04:30:18.424131+00:00"
              }
            },
            "data_studio": null,
            "composer": null,
            "code_console": null,
            "artifacts": {
              "manifest_relpath": "artifacts/manifest.json"
            }
          }
        }
        """

        let response = try decoder.decode(SaveProjectResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.payload.plot?.sourceSHA256, "abc123")
        XCTAssertEqual(response.payload.plot?.embeddedSourceRelpath, "sources/plot/primary/sample.csv")
    }

    func testDecodeOpenProjectResponsePreservesEmbeddedWorkbookSHA256() throws {
        let payload = """
        {
          "project_path": "/tmp/data_studio.sciplotgod",
          "restored_source_path": null,
          "restored_workbook_paths": ["/tmp/E4_9_1.xlsx"],
          "payload": {
            "version": 1,
            "selected_workbench": "data_studio",
            "plot": null,
            "data_studio": {
              "session_kind": "data_studio",
              "version": 1,
              "selected_template_id": "builtin/tensile",
              "workbook_paths": ["/tmp/E4_9_1.xlsx"],
              "selected_workbook_id": "workbook-1",
              "primary_workbook_id": "workbook-1",
              "selected_recipe_id": "representative_curve",
              "comparison_recipe_ids": ["representative_curve"],
              "selected_figure_family_id": "curve",
              "selected_figure_template_id": "curve",
              "group_states": [],
              "specimen_states": [],
              "figure_preferences": [],
              "imported_paths": ["/tmp/E4_9_1.csv"],
              "template_draft_path": null,
              "embedded_workbooks": [
                {
                  "workbook_filename": "E4_9_1.xlsx",
                  "embedded_workbook_relpath": "sources/data_studio/workbooks/E4_9_1.xlsx",
                  "workbook_sha256": "def456",
                  "original_workbook_path": "/tmp/E4_9_1.xlsx",
                  "saved_workbook_mtime_ns": 456
                }
              ],
              "project_display_name": "E4_9_1",
              "source_provenance": {
                "saved_at": "2026-04-26T04:30:18.424131+00:00"
              }
            },
            "composer": null,
            "code_console": null,
            "artifacts": {
              "manifest_relpath": "artifacts/manifest.json"
            }
          }
        }
        """

        let response = try decoder.decode(OpenProjectResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.payload.dataStudio?.embeddedWorkbooks.first?.workbookSHA256, "def456")
        XCTAssertEqual(
            response.payload.dataStudio?.embeddedWorkbooks.first?.embeddedWorkbookRelpath,
            "sources/data_studio/workbooks/E4_9_1.xlsx"
        )
    }

    func testDecodeSaveProjectResponsePreservesCoreAdvancedPlotState() throws {
        let payload = """
        {
          "project_path": "/tmp/core-advanced.sciplotgod",
          "payload": {
            "version": 1,
            "selected_workbench": "plot",
            "plot": {
              "session_kind": "plot",
              "source_filename": "sample.csv",
              "source_media_type": "text/csv",
              "embedded_source_relpath": "sources/plot/primary/sample.csv",
              "source_sha256": "abc123",
              "sheet": "Representative_Curve",
              "selected_template_id": "curve",
              "render_options": {
                "size": "60x55",
                "style_preset": "nature",
                "palette_preset": "colorblind_safe",
                "visual_theme_id": "clean_light",
                "reference_guides": [
                  {
                    "id": "target-line",
                    "enabled": true,
                    "kind": "line",
                    "axis_target": "y_primary",
                    "value": 2.5,
                    "label": "Target"
                  }
                ],
                "text_annotations": [
                  {
                    "id": "note-1",
                    "enabled": true,
                    "text": "Peak",
                    "coordinate_space": "data",
                    "x": 1.5,
                    "y": 2.2,
                    "y_axis_target": "y_primary",
                    "horizontal_alignment": "right",
                    "vertical_alignment": "bottom",
                    "display_style": "callout",
                    "connector_enabled": true,
                    "target_x": 1.0,
                    "target_y": 2.0,
                    "target_y_axis_target": "y_primary"
                  }
                ],
                "shape_annotations": [
                  {
                    "id": "focus-window",
                    "enabled": true,
                    "kind": "rectangle",
                    "bracket_orientation": "horizontal",
                    "x_start": 0.5,
                    "x_end": 1.5,
                    "y_start": 2.0,
                    "y_end": 3.0,
                    "y_axis_target": "y_primary",
                    "label": "Window"
                  }
                ],
                "data_variables": [
                  {
                    "id": "scale",
                    "enabled": true,
                    "kind": "scalar",
                    "label": "Scale",
                    "value": 2.0
                  }
                ],
                "data_transforms": [
                  {
                    "id": "double-y",
                    "enabled": true,
                    "kind": "derived_column",
                    "target_column": "Y_scaled",
                    "expression": "col('Y') * var('scale')"
                  },
                  {
                    "id": "filter-window",
                    "enabled": true,
                    "kind": "row_filter",
                    "label": "Window",
                    "column": "X",
                    "operator": "between",
                    "lower": 1.0,
                    "upper": 2.0
                  }
                ]
              },
              "fit_options": {
                "enabled": true,
                "model_id": "polynomial_2"
              },
              "project_display_name": "Core Advanced",
              "source_provenance": {
                "original_input_path": "/tmp/sample.csv",
                "saved_input_mtime_ns": 123,
                "saved_at": "2026-04-26T04:30:18.424131+00:00"
              }
            },
            "data_studio": null,
            "composer": null,
            "code_console": null,
            "artifacts": {
              "manifest_relpath": "artifacts/manifest.json"
            }
          }
        }
        """

        let response = try decoder.decode(SaveProjectResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.payload.plot?.sourceSHA256, "abc123")
        XCTAssertEqual(response.payload.plot?.selectedTemplateID, "curve")
        XCTAssertEqual(response.payload.plot?.fitOptions.modelID, "polynomial_2")
        XCTAssertEqual(response.payload.plot?.renderOptions.referenceGuides?.first?.label, "Target")
        XCTAssertEqual(response.payload.plot?.renderOptions.textAnnotations?.first?.text, "Peak")
        XCTAssertEqual(response.payload.plot?.renderOptions.shapeAnnotations?.first?.label, "Window")
        XCTAssertEqual(response.payload.plot?.renderOptions.dataVariables?.first?.id, "scale")
        XCTAssertEqual(response.payload.plot?.renderOptions.dataTransforms?.last?.filterOperator, "between")
    }

    func testDecodeOpenProjectResponsePreservesCoreAdvancedPlotState() throws {
        let payload = """
        {
          "project_path": "/tmp/core-advanced.sciplotgod",
          "restored_source_path": "/tmp/restored/sample.csv",
          "restored_workbook_paths": [],
          "payload": {
            "version": 1,
            "selected_workbench": "plot",
            "plot": {
              "session_kind": "plot",
              "source_filename": "sample.csv",
              "source_media_type": "text/csv",
              "embedded_source_relpath": "sources/plot/primary/sample.csv",
              "source_sha256": "abc123",
              "sheet": "Representative_Curve",
              "selected_template_id": "curve",
              "render_options": {
                "size": "60x55",
                "style_preset": "nature",
                "palette_preset": "colorblind_safe",
                "visual_theme_id": "clean_light",
                "reference_guides": [
                  {
                    "id": "target-line",
                    "enabled": true,
                    "kind": "line",
                    "axis_target": "y_primary",
                    "value": 2.5,
                    "label": "Target"
                  }
                ],
                "text_annotations": [
                  {
                    "id": "note-1",
                    "enabled": true,
                    "text": "Peak",
                    "coordinate_space": "data",
                    "x": 1.5,
                    "y": 2.2,
                    "y_axis_target": "y_primary",
                    "horizontal_alignment": "right",
                    "vertical_alignment": "bottom",
                    "display_style": "callout",
                    "connector_enabled": true,
                    "target_x": 1.0,
                    "target_y": 2.0,
                    "target_y_axis_target": "y_primary"
                  }
                ],
                "shape_annotations": [
                  {
                    "id": "focus-window",
                    "enabled": true,
                    "kind": "rectangle",
                    "bracket_orientation": "horizontal",
                    "x_start": 0.5,
                    "x_end": 1.5,
                    "y_start": 2.0,
                    "y_end": 3.0,
                    "y_axis_target": "y_primary",
                    "label": "Window"
                  }
                ],
                "data_variables": [
                  {
                    "id": "scale",
                    "enabled": true,
                    "kind": "scalar",
                    "label": "Scale",
                    "value": 2.0
                  }
                ],
                "data_transforms": [
                  {
                    "id": "double-y",
                    "enabled": true,
                    "kind": "derived_column",
                    "target_column": "Y_scaled",
                    "expression": "col('Y') * var('scale')"
                  },
                  {
                    "id": "filter-window",
                    "enabled": true,
                    "kind": "row_filter",
                    "label": "Window",
                    "column": "X",
                    "operator": "between",
                    "lower": 1.0,
                    "upper": 2.0
                  }
                ]
              },
              "fit_options": {
                "enabled": true,
                "model_id": "polynomial_2"
              },
              "project_display_name": "Core Advanced",
              "source_provenance": {
                "original_input_path": "/tmp/sample.csv",
                "saved_input_mtime_ns": 123,
                "saved_at": "2026-04-26T04:30:18.424131+00:00"
              }
            },
            "data_studio": null,
            "composer": null,
            "code_console": null,
            "artifacts": {
              "manifest_relpath": "artifacts/manifest.json"
            }
          }
        }
        """

        let response = try decoder.decode(OpenProjectResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.restoredSourcePath, "/tmp/restored/sample.csv")
        XCTAssertEqual(response.payload.plot?.sourceSHA256, "abc123")
        XCTAssertEqual(response.payload.plot?.selectedTemplateID, "curve")
        XCTAssertEqual(response.payload.plot?.fitOptions.modelID, "polynomial_2")
        XCTAssertEqual(response.payload.plot?.renderOptions.referenceGuides?.first?.label, "Target")
        XCTAssertEqual(response.payload.plot?.renderOptions.textAnnotations?.first?.text, "Peak")
        XCTAssertEqual(response.payload.plot?.renderOptions.shapeAnnotations?.first?.label, "Window")
        XCTAssertEqual(response.payload.plot?.renderOptions.dataVariables?.first?.id, "scale")
        XCTAssertEqual(response.payload.plot?.renderOptions.dataTransforms?.last?.filterOperator, "between")
    }

    func testDecodeSaveProjectResponsePreservesFunctionCurveAxesAndAnalyticalLayers() throws {
        let payload = """
        {
          "project_path": "/tmp/function-advanced.sciplotgod",
          "payload": {
            "version": 1,
            "selected_workbench": "plot",
            "plot": {
              "session_kind": "plot",
              "source_filename": "function.csv",
              "source_media_type": "text/csv",
              "embedded_source_relpath": "sources/plot/primary/function.csv",
              "source_sha256": "func123",
              "sheet": 0,
              "selected_template_id": "function_curve",
              "render_options": {
                "style_preset": "nature",
                "palette_preset": "colorblind_safe",
                "visual_theme_id": "clean_light",
                "extra_x_axis": {
                  "enabled": true,
                  "position": "top",
                  "title": "Gallons",
                  "data_value": 3.78541,
                  "display_value": 1.0
                },
                "extra_y_axis": {
                  "enabled": true,
                  "position": "right",
                  "binding_mode": "series_assignment",
                  "series_ids": ["Model"],
                  "title": "Half Stress",
                  "data_value": 2.0,
                  "display_value": 1.0
                },
                "analytical_layers": [
                  {
                    "id": "function-1",
                    "enabled": true,
                    "kind": "function",
                    "expression": "sin(x) + 1",
                    "x_start": 0.0,
                    "x_end": 3.0,
                    "sample_count": 120,
                    "y_axis_target": "y_primary",
                    "label": "Model"
                  }
                ]
              },
              "fit_options": {
                "enabled": false,
                "model_id": "linear"
              },
              "project_display_name": "Function Advanced",
              "source_provenance": {
                "original_input_path": "/tmp/function.csv",
                "saved_input_mtime_ns": 123,
                "saved_at": "2026-04-26T04:30:18.424131+00:00"
              }
            },
            "data_studio": null,
            "composer": null,
            "code_console": null,
            "artifacts": {
              "manifest_relpath": "artifacts/manifest.json"
            }
          }
        }
        """

        let response = try decoder.decode(SaveProjectResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.payload.plot?.selectedTemplateID, "function_curve")
        XCTAssertEqual(response.payload.plot?.renderOptions.extraXAxis?.title, "Gallons")
        XCTAssertEqual(response.payload.plot?.renderOptions.extraYAxis?.bindingMode, "series_assignment")
        XCTAssertEqual(response.payload.plot?.renderOptions.extraYAxis?.seriesIDs, ["Model"])
        XCTAssertEqual(response.payload.plot?.renderOptions.analyticalLayers?.first?.expression, "sin(x) + 1")
        XCTAssertEqual(response.payload.plot?.renderOptions.analyticalLayers?.first?.sampleCount, 120)
    }

    func testDecodeOpenProjectResponsePreservesAxisBreaks() throws {
        let payload = """
        {
          "project_path": "/tmp/axis-breaks.sciplotgod",
          "restored_source_path": "/tmp/restored/axis-breaks.csv",
          "restored_workbook_paths": [],
          "payload": {
            "version": 1,
            "selected_workbench": "plot",
            "plot": {
              "session_kind": "plot",
              "source_filename": "axis-breaks.csv",
              "source_media_type": "text/csv",
              "embedded_source_relpath": "sources/plot/primary/axis-breaks.csv",
              "source_sha256": "axis123",
              "sheet": 0,
              "selected_template_id": "step_line",
              "render_options": {
                "style_preset": "editorial",
                "palette_preset": "roma",
                "visual_theme_id": "roma",
                "x_axis_breaks": [
                  {
                    "id": "x-gap",
                    "enabled": true,
                    "start": 0.8,
                    "end": 1.2,
                    "display_mode": "split"
                  }
                ],
                "y_axis_breaks": [
                  {
                    "id": "y-gap",
                    "enabled": false,
                    "start": 1.4,
                    "end": 2.2,
                    "display_mode": "compress"
                  }
                ]
              },
              "fit_options": {
                "enabled": false,
                "model_id": "linear"
              },
              "project_display_name": "Axis Breaks",
              "source_provenance": {
                "original_input_path": "/tmp/axis-breaks.csv",
                "saved_input_mtime_ns": 123,
                "saved_at": "2026-04-26T04:30:18.424131+00:00"
              }
            },
            "data_studio": null,
            "composer": null,
            "code_console": null,
            "artifacts": {
              "manifest_relpath": "artifacts/manifest.json"
            }
          }
        }
        """

        let response = try decoder.decode(OpenProjectResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.payload.plot?.selectedTemplateID, "step_line")
        XCTAssertEqual(response.payload.plot?.renderOptions.xAxisBreaks?.first?.id, "x-gap")
        XCTAssertEqual(response.payload.plot?.renderOptions.xAxisBreaks?.first?.displayMode, "split")
        XCTAssertEqual(response.payload.plot?.renderOptions.yAxisBreaks?.first?.displayMode, "compress")
    }
}

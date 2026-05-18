import Foundation
import CoreGraphics
import XCTest
@testable import SciPlotMac

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

    func testDecodeSourceTablePreviewDataContainers() throws {
        let payload = """
        {
          "input_path": "/tmp/curve.csv",
          "sheet": "Sheet1",
          "offset": 1,
          "limit": 2,
          "total_rows": 4,
          "total_cols": 2,
          "column_headers": ["time", "signal"],
          "rows": [["s", "mV"], [0.0, 1.2]],
          "candidate_roles": {
            "x": ["time"],
            "y": ["signal"],
            "z": [],
            "group": [],
            "sample": [],
            "value": [],
            "metric": [],
            "label": [],
            "series": []
          },
          "detected_x_label": "time",
          "detected_y_label": "signal",
          "column_profiles": [],
          "segments": [],
          "selected_segment_id": null,
          "encoding": "utf-8",
          "delimiter": ",",
          "data_containers": [
            {
              "id": "source-table:Sheet1",
              "kind": "table",
              "label": "Sheet1 table",
              "status": "enabled",
              "readonly": true,
              "row_count": 4,
              "column_count": 2,
              "columns": [
                {
                  "id": "col-0",
                  "name": "time",
                  "index": 0,
                  "role_hints": ["x"],
                  "unit": "s",
                  "comment": null,
                  "profile": {
                    "name": "time",
                    "header_preview": ["time", "s"],
                    "inferred_type": "numeric",
                    "non_empty_count": 2,
                    "missing_count": 0,
                    "min_value": 0,
                    "max_value": 1
                  }
                }
              ],
              "source": {
                "input_path": "/tmp/curve.csv",
                "sheet": "Sheet1",
                "selected_segment_id": null,
                "encoding": "utf-8",
                "delimiter": ",",
                "offset": 1,
                "limit": 2
              },
              "help": "Readonly table container generated by source preview."
            }
          ]
        }
        """

        let response = try decoder.decode(SourceTablePreviewResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.dataContainers.count, 1)
        XCTAssertEqual(response.dataContainers[0].id, "source-table:Sheet1")
        XCTAssertEqual(response.dataContainers[0].kind, "table")
        XCTAssertTrue(response.dataContainers[0].readonly)
        XCTAssertEqual(response.dataContainers[0].columns[0].roleHints, ["x"])
        XCTAssertEqual(response.dataContainers[0].columns[0].unit, "s")
    }

    func testDecodeLabPlotScalePayloadLandingModels() throws {
        let containerPayload = """
        {
          "id": "matrix-1",
          "kind": "matrix",
          "label": "Scalar Field",
          "status": "enabled",
          "readonly": true,
          "row_count": 4,
          "column_count": 3,
          "columns": [],
          "source": {
            "input_path": "/tmp/field.csv",
            "sheet": "Sheet1",
            "selected_segment_id": null,
            "encoding": "utf-8",
            "delimiter": ",",
            "offset": 0,
            "limit": 50,
            "transform_count": 0
          },
          "dimensions": {"rows": 2, "columns": 2},
          "coordinate_vectors": {"x": [25, 40], "y": [0, 5]},
          "missing_value_policy": "preserve",
          "statistics": {"Intensity": {"mean": 0.395}},
          "diagnostics": [{"status_code": "matrix_detected", "message": "XYZ grid detected."}],
          "help": "Matrix container landing."
        }
        """
        let container = try decoder.decode(DataContainerPayload.self, from: Data(containerPayload.utf8))
        XCTAssertEqual(container.kind, "matrix")
        XCTAssertEqual(container.dimensions?["rows"]?.numberValue, 2)

        let objectPayload = """
        {
          "id": "plot:guide:target-line",
          "kind": "plot.guide",
          "module": "plot",
          "label": "Target",
          "status": "active",
          "visible": true,
          "locked": false,
          "graph_node_id": "plot:guide:target-line",
          "payload": {"axis_target": "y_primary"},
          "help": "Graph-addressable plot object."
        }
        """
        let object = try decoder.decode(PlotObjectPayload.self, from: Data(objectPayload.utf8))
        XCTAssertEqual(object.kind, "plot.guide")
        XCTAssertTrue(object.visible)

        let commandPayload = """
        {
          "command_id": "cmd-1",
          "kind": "edit",
          "target_object_id": "plot:guide:target-line",
          "before": {"visible": true},
          "after": {"visible": false},
          "graph_patch": {"selected_nodes": {"plot": "plot:guide:target-line"}},
          "reversible": true,
          "help": "Undoable typed edit command."
        }
        """
        let command = try decoder.decode(PlotEditCommandPayload.self, from: Data(commandPayload.utf8))
        XCTAssertEqual(command.kind, "edit")
        XCTAssertTrue(command.reversible)

        let analysisPayload = """
        {
          "operation_id": "analysis.fit",
          "available": true,
          "valid": true,
          "status_code": "ok",
          "message": "Fit complete.",
          "diagnostics": [],
          "metrics": {"r_squared": 0.99},
          "tables": [{"id": "fit-table", "rows": []}],
          "overlays": [{"kind": "fit_overlay"}],
          "data_containers": []
        }
        """
        let analysis = try decoder.decode(AnalysisOperationResultPayload.self, from: Data(analysisPayload.utf8))
        XCTAssertEqual(analysis.operationID, "analysis.fit")
        XCTAssertEqual(analysis.metrics["r_squared"]?.numberValue, 0.99)

        let filterPayload = """
        {
          "id": "import.hdf5",
          "label": "HDF5",
          "status": "disabled",
          "owner": "sidecar",
          "surface": "plot,data_studio",
          "options_schema": {"type": "object"},
          "output_container_kinds": ["matrix"],
          "help": "Explicit import filter landing.",
          "test_requirements": ["schema_decode"]
        }
        """
        let importFilter = try decoder.decode(ImportFilterPayload.self, from: Data(filterPayload.utf8))
        XCTAssertEqual(importFilter.id, "import.hdf5")
        XCTAssertEqual(importFilter.outputContainerKinds, ["matrix"])

        let exportPayload = """
        {
          "id": "export.artifact_manifest",
          "label": "Artifact Manifest",
          "status": "enabled",
          "owner": "sidecar",
          "surface": "all",
          "allowed_modules": ["plot", "data_studio", "composer", "code_console"],
          "artifact_kind": "manifest",
          "filename_policy": "base_name_with_suffixes",
          "help": "Explicit export target landing.",
          "test_requirements": ["manifest_roundtrip"]
        }
        """
        let exportTarget = try decoder.decode(ExportTargetPayload.self, from: Data(exportPayload.utf8))
        XCTAssertEqual(exportTarget.artifactKind, "manifest")

        let notebookPayload = """
        {
          "id": "notebook-output-1",
          "kind": "figure",
          "label": "Generated Figure",
          "status": "enabled",
          "source_run_id": "run-1",
          "artifact_paths": ["/tmp/figure.pdf"],
          "container_ids": ["data.notebook_output:run-1"],
          "help": "Code Console generated output landing."
        }
        """
        let notebook = try decoder.decode(NotebookOutputPayload.self, from: Data(notebookPayload.utf8))
        XCTAssertEqual(notebook.kind, "figure")
        XCTAssertEqual(notebook.containerIDs, ["data.notebook_output:run-1"])

        let analysisRequest = AnalysisOperationRequest(
            operationID: "analysis.smoothing",
            inputPath: "/tmp/curve.csv",
            xColumn: "x",
            yColumn: "signal",
            parameters: ["window": .number(3)]
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let analysisRequestJSON = try JSONSerialization.jsonObject(
            with: try encoder.encode(analysisRequest)
        ) as? [String: Any]
        XCTAssertEqual(analysisRequestJSON?["operation_id"] as? String, "analysis.smoothing")

        let importPreviewPayload = """
        {
          "input_path": "/tmp/records.json",
          "filter_id": "import.json",
          "status": "enabled",
          "label": "JSON",
          "data_containers": [],
          "diagnostics": [{"status_code": "json_records_loaded"}],
          "options_schema": {"type": "object"},
          "help": "JSON records preview is enabled."
        }
        """
        let importPreview = try decoder.decode(ImportPreviewResponse.self, from: Data(importPreviewPayload.utf8))
        XCTAssertEqual(importPreview.filterID, "import.json")
        XCTAssertEqual(importPreview.status, "enabled")

        let commandResponsePayload = """
        {
          "command": {
            "command_id": "cmd-visible",
            "kind": "visibility",
            "target_object_id": "plot:guide:target-line",
            "graph_patch": {"target_object_id": "plot:guide:target-line"},
            "reversible": true,
            "help": "Normalized command."
          },
          "diagnostics": []
        }
        """
        let commandResponse = try decoder.decode(
            PlotEditCommandNormalizeResponse.self,
            from: Data(commandResponsePayload.utf8)
        )
        XCTAssertEqual(commandResponse.command.targetObjectID, "plot:guide:target-line")
    }

    func testDecodeLabPlotNextGenerationRuntimePayloads() throws {
        let previewScenePayload = """
        {
          "scene_id": "preview-scene:curve.csv:0:curve",
          "template": "curve",
          "sheet": 0,
          "native_supported": true,
          "fallback_reason": null,
          "graph_revision": 3,
          "figure": {"pixel_width": 800, "pixel_height": 600, "scale": 2.0},
          "plot_area": {"x": 96, "y": 60, "width": 608, "height": 468},
          "axes": [{"id": "axis:primary", "role": "primary", "bbox_pixels": {"x": 96, "y": 60, "width": 608, "height": 468}, "x_scale": "linear", "y_scale": "linear", "x_range": [0, 3], "y_range": [0, 9], "x_reversed": false, "y_reversed": false}],
          "series": [{"id": "plot:series:0", "label": "signal", "kind": "curve", "column_refs": {"x": "col-0", "y": "col-1"}, "samples": [{"x": 0, "y": 0}, {"x": 1, "y": 1}]}],
          "objects": [
            {"id": "plot:series:0", "kind": "series_line", "axis_id": "axis:primary", "bbox_pixels": {"x": 96, "y": 60, "width": 608, "height": 468}, "points": [[96, 528], [299, 476]], "payload_ref": {"type": "series", "id": "plot:series:0"}, "operations": ["select", "quick_edit", "drag_offset", "copy_settings"], "visible": true, "locked": false},
            {"id": "plot:axis:x", "kind": "x_axis", "label": "Time", "axis_id": "axis:primary", "bbox_pixels": {"x": 96, "y": 524, "width": 608, "height": 8}, "points": [[96, 528], [704, 528]], "payload_ref": {"type": "axis", "id": "x"}, "operations": ["select", "quick_edit", "rename"], "visible": true, "locked": false},
            {"id": "plot:legend:main", "kind": "legend", "label": "Legend", "bbox_pixels": {"x": 568, "y": 76, "width": 120, "height": 36}, "points": [], "payload_ref": {"type": "legend", "id": "main"}, "operations": ["select", "quick_edit", "reorder", "lock"], "visible": true, "locked": false},
            {"id": "plot:guide:target", "kind": "reference_guide_line", "label": "Target", "axis_id": "axis:primary", "bbox_pixels": {"x": 96, "y": 260, "width": 608, "height": 0}, "points": [[96, 260], [704, 260]], "payload_ref": {"type": "reference_guide", "id": "target"}, "operations": ["select", "quick_edit", "drag", "visibility"], "visible": false, "locked": true},
            {"id": "plot:function:fn", "kind": "function_layer", "label": "Model", "axis_id": "axis:primary", "bbox_pixels": {"x": 96, "y": 260, "width": 608, "height": 0}, "points": [[96, 260], [704, 260]], "payload_ref": {"type": "analytical_layer", "id": "fn"}, "operations": ["select", "quick_edit", "drag", "delete"], "visible": true, "locked": false},
            {"id": "plot:fit_overlay:linear", "kind": "fit_overlay", "label": "Linear Fit", "axis_id": "axis:primary", "bbox_pixels": {"x": 96, "y": 60, "width": 608, "height": 468}, "points": [[96, 528], [299, 476]], "payload_ref": {"type": "fit_overlay", "id": "linear"}, "operations": ["select", "quick_edit", "visibility"], "visible": true, "locked": false}
          ],
          "overlays": [
            {"id": "plot:guide:target", "kind": "reference_guide_line", "payload_ref": {"type": "reference_guide", "id": "target"}, "payload": {"id": "target", "kind": "line"}}
          ],
          "budgets": {"native_scene_samples": 2000},
          "diagnostics": []
        }
        """
        let scene = try decoder.decode(PreviewSceneResponse.self, from: Data(previewScenePayload.utf8))
        XCTAssertTrue(scene.nativeSupported)
        XCTAssertEqual(scene.graphRevision, 3)
        XCTAssertEqual(scene.figure["pixel_width"]?.numberValue, 800)
        XCTAssertEqual(scene.series[0].columnRefs["x"], "col-0")
        XCTAssertEqual(scene.interactionMetadata?.objects.first?.kind, "series_line")
        XCTAssertEqual(scene.interactionMetadata?.objects.first?.operations, ["select", "quick_edit", "drag_offset", "copy_settings"])
        let guideObject = try XCTUnwrap(scene.interactionMetadata?.objects.first(where: { $0.id == "plot:guide:target" }))
        XCTAssertEqual(guideObject.payloadRef?.type, "reference_guide")
        XCTAssertFalse(guideObject.visible)
        XCTAssertTrue(guideObject.locked)
        XCTAssertTrue(guideObject.operations.contains("drag"))
        let functionObject = try XCTUnwrap(scene.interactionMetadata?.objects.first(where: { $0.id == "plot:function:fn" }))
        XCTAssertEqual(functionObject.kind, "function_layer")
        XCTAssertEqual(functionObject.payloadRef?.type, "analytical_layer")
        XCTAssertEqual(scene.overlays.first?["payload"]?.objectValue?["kind"]?.stringValue, "line")

        let commandPayload = """
        {
          "command": {
            "command_id": "cmd-copy-style",
            "kind": "copy_settings",
            "module": "plot",
            "target_object_id": "plot:legend:main",
            "source_object_id": "plot:series:a",
            "before": {"visible": true},
            "after": {"visible": true, "copied_style_ref": "plot:series:a"},
            "graph_patch": {"target_object_id": "plot:legend:main", "revision_delta": 1},
            "graph_revision": 5,
            "reversible": true,
            "help": "Undoable typed command."
          },
          "diagnostics": []
        }
        """
        let command = try decoder.decode(CommandNormalizeResponse.self, from: Data(commandPayload.utf8))
        XCTAssertEqual(command.command.module, "plot")
        XCTAssertEqual(command.command.sourceObjectID, "plot:series:a")
        XCTAssertEqual(command.command.graphRevision, 5)

        let applyPayload = """
        {
          "command": {
            "command_id": "cmd-copy-style",
            "kind": "copy_settings",
            "module": "plot",
            "target_object_id": "plot:legend:main",
            "source_object_id": "plot:series:a",
            "graph_patch": {"target_object_id": "plot:legend:main", "revision_delta": 1},
            "graph_revision": 6,
            "reversible": true,
            "help": "Undoable typed command."
          },
          "graph_revision": 6,
          "graph_patch": {"target_object_id": "plot:legend:main"},
          "render_invalidation": {"reason": "command_applied"},
          "diagnostics": []
        }
        """
        let applied = try decoder.decode(CommandApplyPreviewResponse.self, from: Data(applyPayload.utf8))
        XCTAssertEqual(applied.graphRevision, 6)
        XCTAssertEqual(applied.renderInvalidation["reason"]?.stringValue, "command_applied")

        let livePayload = """
        {
          "live_source": {
            "id": "live:file-tail:live",
            "kind": "periodic_csv",
            "status": "enabled",
            "poll_interval_ms": 1000,
            "sample_window": 200,
            "append_policy": "replace",
            "paused": false,
            "last_update_diagnostic": {"status_code": "live_source_updated"},
            "help": "Periodic CSV refresh for local files."
          },
          "input_path": "/tmp/live.csv",
          "sheet": 0,
          "data_revision": 12,
          "data_containers": [],
          "diagnostics": [{"status_code": "live_source_updated"}],
          "render_invalidation": {"reason": "live_source_updated"},
          "help": "Periodic CSV refresh for local files."
        }
        """
        let liveUpdate = try decoder.decode(LiveSourceUpdateResponse.self, from: Data(livePayload.utf8))
        XCTAssertEqual(liveUpdate.liveSource.kind, "periodic_csv")
        XCTAssertEqual(liveUpdate.dataRevision, 12)
        XCTAssertEqual(liveUpdate.renderInvalidation["reason"]?.stringValue, "live_source_updated")
    }

    func testDecodeCodeConsoleContextResponseUsesSnakeCaseContextID() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let payload = try encoder.encode(TestPayloads.codeConsoleContext())

        let response = try decoder.decode(CodeConsoleContextResponse.self, from: payload)

        XCTAssertEqual(response.contextID, "ctx_test_payload")
    }

    func testDecodeCodeConsoleRunResponseWithNotebookOutputs() throws {
        let payload = """
        {
          "status": "succeeded",
          "exit_code": 0,
          "duration_seconds": 0.42,
          "stdout": "ok",
          "stderr": "",
          "run_dir": "/tmp/run",
          "output_dir": "/tmp/run/outputs",
          "script_path": "/tmp/run/user_code.py",
          "prompt_path": "/tmp/run/prompt.txt",
          "context_path": "/tmp/run/context.json",
          "stdout_path": "/tmp/run/stdout.txt",
          "stderr_path": "/tmp/run/stderr.txt",
          "generated_files": [
            {"path": "/tmp/run/outputs/plot.pdf", "name": "plot.pdf", "file_type": "pdf", "size_bytes": 120}
          ],
          "notebook_outputs": [
            {
              "id": "notebook-output:1",
              "kind": "figure",
              "label": "plot.pdf",
              "status": "enabled",
              "source_run_id": "run",
              "artifact_paths": ["/tmp/run/outputs/plot.pdf"],
              "container_ids": [],
              "help": "Code Console generated figure output."
            }
          ],
          "data_containers": []
        }
        """

        let response = try decoder.decode(CodeConsoleRunResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.notebookOutputs.first?.kind, "figure")
        XCTAssertEqual(response.generatedFiles.first?.name, "plot.pdf")
    }

    func testEncodeCodeConsoleRunRequestUsesSnakeCaseContextID() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let request = CodeConsoleRunRequest(contextID: "ctx_fast_path", code: "print('ok')", timeoutSeconds: 30)

        let payload = try JSONSerialization.jsonObject(with: try encoder.encode(request)) as? [String: Any]

        XCTAssertEqual(payload?["context_id"] as? String, "ctx_fast_path")
        XCTAssertNil(payload?["contextID"])
    }

    func testDecodePreviewInteractionMetadataWithArtistMap() throws {
        let payload = """
        {
          "filename": "sample_curve.pdf",
          "pdf_base64": "\(TestPayloads.pdfBase64)",
          "png_base64": null,
          "qa": null,
          "interaction_metadata": {
            "schema_version": 2,
            "figure": {
              "pixel_width": 1000,
              "pixel_height": 800
            },
            "axes": [
              {
                "id": "axis-0",
                "role": "primary",
                "bbox_pixels": {"x": 100, "y": 120, "width": 760, "height": 520},
                "x_range": [0, 10],
                "y_range": [0, 20],
                "x_scale": "linear",
                "y_scale": "linear",
                "x_reversed": false,
                "y_reversed": false
              }
            ],
            "artists": [
              {
                "id": "series:axis-0:Sample A",
                "kind": "series_line",
                "axis_id": "axis-0",
                "series_id": "Sample A",
                "label": "Sample A",
                "bbox_pixels": {"x": 120, "y": 220, "width": 700, "height": 260},
                "points": [[120, 480], [500, 320], [820, 220]]
              }
            ],
            "objects": [
              {
                "id": "series:axis-0:Sample A",
                "kind": "series_line",
                "label": "Sample A",
                "axis_id": "axis-0",
                "bbox_pixels": {"x": 120, "y": 220, "width": 700, "height": 260},
                "points": [[120, 480], [500, 320], [820, 220]],
                "payload_ref": {"type": "series", "id": "Sample A"},
                "operations": ["select", "quick_edit", "drag_offset"]
              }
            ]
          }
        }
        """

        let response = try decoder.decode(PreviewItemResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.interactionMetadata?.schemaVersion, 2)
        XCTAssertEqual(response.interactionMetadata?.figure.pixelWidth, 1000)
        XCTAssertEqual(response.interactionMetadata?.axes.first?.bboxPixels.width, 760)
        XCTAssertEqual(response.interactionMetadata?.artists.first?.axisID, "axis-0")
        XCTAssertEqual(response.interactionMetadata?.artists.first?.seriesID, "Sample A")
        XCTAssertEqual(response.interactionMetadata?.objects.first?.payloadRef?.type, "series")
        XCTAssertEqual(response.interactionMetadata?.objects.first?.payloadRef?.id, "Sample A")
        XCTAssertEqual(response.interactionMetadata?.objects.first?.operations, ["select", "quick_edit", "drag_offset"])
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

    func testDecodePreviewItemPayloadKeepsPNGAndPDFPreviews() throws {
        let payload = """
        {
          "filename": "sample_curve.pdf",
          "pdf_base64": "\(TestPayloads.pdfBase64)",
          "png_base64": "\(TestPayloads.pngBase64)",
          "qa": null,
          "interaction_metadata": {
            "figure": {
              "pixel_width": 1600,
              "pixel_height": 1200
            },
            "axes": [
              {
                "id": "primary",
                "role": "primary",
                "bbox_pixels": {
                  "x": 220,
                  "y": 180,
                  "width": 980,
                  "height": 760
                },
                "x_range": [0, 10],
                "y_range": [1, 5],
                "x_scale": "linear",
                "y_scale": "linear",
                "x_reversed": false,
                "y_reversed": false
              }
            ]
          }
        }
        """

        let response = try decoder.decode(PreviewItemResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.filename, "sample_curve.pdf")
        XCTAssertEqual(response.pdfBase64, TestPayloads.pdfBase64)
        XCTAssertEqual(response.pngBase64, TestPayloads.pngBase64)
        XCTAssertEqual(response.interactionMetadata?.figure.pixelWidth, 1600)
        XCTAssertEqual(response.interactionMetadata?.axes.first?.role, "primary")
        XCTAssertEqual(response.interactionMetadata?.axes.first?.bboxPixels.width, 980)
    }

    func testDecodeRenderOptionsKeepsCustomPlotTheme() throws {
        let payload = """
        {
          "style_preset": "nature",
          "palette_preset": "colorblind_safe",
          "visual_theme_id": "clean_light",
          "custom_theme_id": "user/nature_plus",
          "custom_theme_draft": {
            "id": "user/nature_plus",
            "label": "Nature Plus",
            "base_style_id": "nature",
            "palette_preset": "colorblind_safe",
            "visual_theme_id": "clean_light",
            "palette": {"categorical": ["#0ea5e9", "#f97316"]},
            "hard_overrides": {"typography": {"font_size_pt": 7.2}},
            "soft_overrides": {"axes.grid": true},
            "expert_rcparams": {"grid.linestyle": ":"}
          }
        }
        """

        let response = try decoder.decode(RenderOptionsPayload.self, from: Data(payload.utf8))

        XCTAssertEqual(response.customThemeID, "user/nature_plus")
        XCTAssertEqual(response.customThemeDraft?.id, "user/nature_plus")
        XCTAssertEqual(response.customThemeDraft?.palette.categorical, ["#0ea5e9", "#f97316"])
        XCTAssertEqual(response.customThemeDraft?.hardOverrides["typography"]?["font_size_pt"], .number(7.2))
        XCTAssertEqual(response.customThemeDraft?.softOverrides["axes.grid"], .bool(true))
        XCTAssertEqual(response.customThemeDraft?.expertRcParams["grid.linestyle"], .string(":"))
    }

    func testDecodeRenderOptionsKeepsLegendPosition() throws {
        let payload = """
        {
          "size": "120x110",
          "style_preset": "nature",
          "palette_preset": "colorblind_safe",
          "legend_position": "upper_left"
        }
        """

        let response = try decoder.decode(RenderOptionsPayload.self, from: Data(payload.utf8))

        XCTAssertEqual(response.size, "120x110")
        XCTAssertEqual(response.legendPosition, "upper_left")
    }

    func testDecodeRenderOptionsKeepsSeriesOffsets() throws {
        let payload = """
        {
          "style_preset": "nature",
          "palette_preset": "colorblind_safe",
          "series_offsets": [
            {
              "series_id": "Sample A",
              "enabled": true,
              "x_offset": 0.5,
              "y_offset": -0.25,
              "y_axis_target": "y_primary"
            }
          ]
        }
        """

        let response = try decoder.decode(RenderOptionsPayload.self, from: Data(payload.utf8))

        XCTAssertEqual(response.seriesOffsets?.first?.seriesID, "Sample A")
        XCTAssertEqual(response.seriesOffsets?.first?.xOffset, 0.5)
        XCTAssertEqual(response.seriesOffsets?.first?.yOffset, -0.25)
        XCTAssertEqual(response.seriesOffsets?.first?.yAxisTarget, "y_primary")
    }

    func testDecodePlotThemeEndpointResponses() throws {
        let payload = """
        {
          "theme": {
            "id": "user/nature_plus",
            "label": "Nature Plus",
            "base_style_id": "nature",
            "palette_preset": "colorblind_safe",
            "visual_theme_id": "clean_light",
            "palette": {"categorical": ["#0ea5e9"]},
            "hard_overrides": {},
            "soft_overrides": {},
            "expert_rcparams": {}
          },
          "blocked_keys": ["font.size"],
          "warnings": ["Blocked unsupported or protected custom theme keys: font.size."]
        }
        """

        let response = try decoder.decode(PlotThemePreviewResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.theme.id, "user/nature_plus")
        XCTAssertEqual(response.blockedKeys, ["font.size"])
        XCTAssertEqual(response.warnings.count, 1)
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

    func testEncodeRenderRequestWithPreviewConfig() throws {
        let request = RenderRequest(
            inputPath: "/tmp/sample.csv",
            sheet: .index(0),
            template: "curve",
            options: RenderOptionsPayload(stylePreset: "nature"),
            previewConfig: PreviewRenderConfigPayload(pixelWidth: 2048, pixelHeight: 1536, scale: 2.0)
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let payload = try JSONSerialization.jsonObject(with: try encoder.encode(request)) as? [String: Any]
        let previewConfig = payload?["preview_config"] as? [String: Any]

        XCTAssertEqual(previewConfig?["pixel_width"] as? Int, 2048)
        XCTAssertEqual(previewConfig?["pixel_height"] as? Int, 1536)
        XCTAssertEqual(previewConfig?["scale"] as? Double, 2.0)
    }

    func testPreviewPixelBucketRoundsAndClampsStageSize() {
        let bucket = PlotPreviewPixelBucket(stageSize: CGSize(width: 1800, height: 1300), displayScale: 2.0)

        XCTAssertEqual(bucket.config.pixelWidth, 3584)
        XCTAssertEqual(bucket.config.pixelHeight, 2560)
        XCTAssertEqual(bucket.config.scale, 2.0)

        let nearSameBucket = PlotPreviewPixelBucket(stageSize: CGSize(width: 1808, height: 1304), displayScale: 2.0)
        XCTAssertEqual(bucket, nearSameBucket)
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
            "60x55": {
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
              "default_size": "60x55",
              "allowed_sizes": ["60x55"],
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
        XCTAssertEqual(response.sizePresets["60x55"]?.widthMm, 60)
        XCTAssertEqual(response.sizePresets["60x55"]?.heightMm, 55)
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
              "id": "acs",
              "label": "ACS",
              "public": true,
              "description": "ACS publication style",
              "hard_constraints": false,
              "preset_note": "ACS",
              "recommended_palette_preset": "okabe_ito",
              "recommended_visual_theme_id": "clean_light"
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
                "style_preset": "acs",
                "palette_preset": "okabe_ito",
                "visual_theme_id": "clean_light"
              },
              "available_styles": ["nature", "acs"],
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
        XCTAssertEqual(response.templates.first?.defaultOptions["style_preset"]?.stringValue, "acs")
        XCTAssertEqual(response.templates.first?.defaultOptions["palette_preset"]?.stringValue, "okabe_ito")
        XCTAssertEqual(response.templates.first?.defaultOptions["visual_theme_id"]?.stringValue, "clean_light")
        XCTAssertEqual(response.styles.first?.recommendedPalettePreset, "colorblind_safe")
        XCTAssertEqual(response.styles.first?.recommendedVisualThemeID, "clean_light")
    }

    func testDecodeMetaPayloadWithCapabilityCatalogs() throws {
        let payload = """
        {
          "version": 1,
          "defaults": {
            "style_preset": "nature",
            "palette_preset": "colorblind_safe"
          },
          "global_frame": {
            "panel_width_mm": 60,
            "panel_height_mm": 55,
            "left_margin_mm": 10,
            "right_margin_mm": 4,
            "bottom_margin_mm": 8,
            "top_margin_mm": 3
          },
          "sizes": [],
          "styles": [],
          "palettes": [],
          "templates": [],
          "template_ids": [],
          "size_ids": [],
          "palette_preset_ids": [],
          "visual_themes": [],
          "capability_catalogs": [
            {
              "id": "plot_objects",
              "label": "Plot Objects",
              "description": "Graph-addressable plot object capabilities.",
              "capabilities": [
                {
                  "id": "plot.axis",
                  "label": "Axis",
                  "status": "enabled",
                  "owner": "shared",
                  "surface": "plot",
                  "typed_payload_schema": {
                    "type": "object"
                  },
                  "help": "Axes are editable plot objects.",
                  "introduced_in": "phase_2",
                  "test_requirements": ["decode"]
                }
              ]
            }
          ]
        }
        """

        let response = try decoder.decode(SidecarMetaResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.capabilityCatalogs.first?.id, "plot_objects")
        XCTAssertEqual(response.capabilityCatalogs.first?.capabilities.first?.id, "plot.axis")
        XCTAssertEqual(response.capabilityCatalogs.first?.capabilities.first?.status, "enabled")
        XCTAssertEqual(
            response.capabilityCatalogs.first?.capabilities.first?.typedPayloadSchema["type"]?.stringValue,
            "object"
        )
    }

    func testDecodeProjectBundlePayloadWithDocumentGraph() throws {
        let payload = """
        {
          "version": 2,
          "selected_workbench": "plot",
          "plot": null,
          "data_studio": null,
          "composer": null,
          "code_console": null,
          "artifacts": {},
          "document_graph": {
            "schema_version": 1,
            "nodes": [
              {
                "id": "plot:scene",
                "kind": "plot.scene",
                "module": "plot",
                "label": "Plot Scene",
                "status": "active",
                "payload": {
                  "selected_template_id": "curve"
                }
              }
            ],
            "edges": [],
            "selected_nodes": {
              "plot": "plot:scene"
            },
            "module_roots": {
              "plot": "plot:scene"
            },
            "capabilities": ["project_bundle.document_graph"],
            "migration_notes": ["Generated document_graph from project payload v2."]
          }
        }
        """

        let response = try decoder.decode(ProjectBundlePayload.self, from: Data(payload.utf8))

        XCTAssertEqual(response.documentGraph?.schemaVersion, 1)
        XCTAssertEqual(response.documentGraph?.nodes.first?.kind, "plot.scene")
        XCTAssertEqual(response.documentGraph?.nodes.first?.payload["selected_template_id"]?.stringValue, "curve")
        XCTAssertEqual(response.documentGraph?.moduleRoots["plot"], "plot:scene")
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
          "project_path": "/tmp/sample.sciplot",
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
          "project_path": "/tmp/data_studio.sciplot",
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
          "project_path": "/tmp/core-advanced.sciplot",
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
          "project_path": "/tmp/core-advanced.sciplot",
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
          "project_path": "/tmp/function-advanced.sciplot",
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
          "project_path": "/tmp/axis-breaks.sciplot",
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
                "style_preset": "wiley",
                "palette_preset": "tol_muted",
                "visual_theme_id": "clean_light",
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

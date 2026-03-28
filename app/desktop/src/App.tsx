import { startTransition, useDeferredValue, useEffect, useMemo, useState } from "react";

import {
  currentPathname,
  documentTitleForRoute,
  NAV_ITEMS,
  normalizeActiveRoute,
  type ActiveRoute,
} from "./app-shell";
import { MacSidebar } from "./components/mac/MacSidebar";
import { MacTitlebar } from "./components/mac/MacTitlebar";
import { MacWindowShell } from "./components/mac/MacWindowShell";
import {
  exportRender,
  getWorkbenchMeta,
  inspectFile,
  materializeDataTemplateFolder,
  openPath,
  preflightRender,
  renderPreview,
} from "./lib/api";
import { useWizardStore, useWorkbenchStore } from "./lib/store";
import { openDialog } from "./lib/tauri-dialog";
import type { RenderOptionsPayload, TemplateName, WorkbenchMeta } from "./lib/types";
import {
  compatibleTemplateChoices,
  confirmReplaceWizardSession,
  formatLeaf,
  getErrorMessage,
  incompatibleTemplateChoices,
  templateCompatibilityReason,
  templateLabel,
} from "./lib/workbench";
import {
  inspectionRecommendationSections,
  mergeRenderOptions,
  sanitizeRenderOptions,
  selectionFromInspection,
} from "./lib/wizard";
import { PlotImportScreen } from "./screens/PlotImportScreen";
import { PlotRefineScreen } from "./screens/PlotRefineScreen";
import { PlotTemplateScreen } from "./screens/PlotTemplateScreen";
import { StartScreen } from "./screens/StartScreen";

export function App() {
  const wizard = useWizardStore();
  const workbench = useWorkbenchStore();

  const [route, setRoute] = useState<ActiveRoute>(() => {
    const current = currentPathname();
    if (current !== "/") {
      return current;
    }
    return normalizeActiveRoute(workbench.lastRoute);
  });
  const [meta, setMeta] = useState<WorkbenchMeta | null>(null);
  const [metaError, setMetaError] = useState<string | null>(null);
  const [metaBusy, setMetaBusy] = useState(true);
  const [importBusy, setImportBusy] = useState(false);
  const [previewBusy, setPreviewBusy] = useState(false);
  const [previewError, setPreviewError] = useState<string | null>(null);
  const [readinessBusy, setReadinessBusy] = useState(false);
  const [exportBusy, setExportBusy] = useState(false);
  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const [pathDraft, setPathDraft] = useState(wizard.inputPath);

  const deferredOptions = useDeferredValue(wizard.options);
  const recentDatasets = useMemo(
    () => workbench.recentProjects.filter((item) => item.mode === "wizard" && item.kind === "data"),
    [workbench.recentProjects],
  );

  useEffect(() => {
    document.title = documentTitleForRoute(route);
  }, [route]);

  useEffect(() => {
    if (typeof window === "undefined") {
      return undefined;
    }
    const onPopState = () => {
      setRoute(currentPathname());
    };
    window.addEventListener("popstate", onPopState);
    return () => window.removeEventListener("popstate", onPopState);
  }, []);

  useEffect(() => {
    setPathDraft(wizard.inputPath);
  }, [wizard.inputPath]);

  useEffect(() => {
    let cancelled = false;

    async function loadMeta() {
      setMetaBusy(true);
      setMetaError(null);
      try {
        const nextMeta = await getWorkbenchMeta();
        if (cancelled) {
          return;
        }
        setMeta(nextMeta);
        wizard.setSidecarReady(true);
        if (!wizard.options.style_preset || !wizard.options.palette_preset) {
          wizard.setOptions(
            sanitizeRenderOptions(
              nextMeta,
              wizard.template,
              {
                ...wizard.options,
                style_preset: wizard.options.style_preset ?? nextMeta.default_style,
                palette_preset: wizard.options.palette_preset ?? nextMeta.default_palette,
              },
              wizard.inspection?.model,
            ),
          );
        }
      } catch (error) {
        if (cancelled) {
          return;
        }
        wizard.setSidecarReady(false);
        setMetaError(getErrorMessage(error));
      } finally {
        if (!cancelled) {
          setMetaBusy(false);
        }
      }
    }

    void loadMeta();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (route !== "/plot/refine" || !wizard.inputPath || !wizard.template) {
      return;
    }
    const controller = new AbortController();
    let cancelled = false;
    const templateId = wizard.template;

    async function loadPreview() {
      setPreviewBusy(true);
      setPreviewError(null);
      try {
        const response = await renderPreview(
          wizard.inputPath,
          wizard.sheet,
          templateId,
          deferredOptions,
          { signal: controller.signal },
        );
        if (cancelled) {
          return;
        }
        wizard.setPreviews(response.previews);
        wizard.setSubmissionReport(response.submission_report ?? null);
      } catch (error) {
        if (cancelled || controller.signal.aborted) {
          return;
        }
        wizard.setPreviews([]);
        setPreviewError(getErrorMessage(error));
      } finally {
        if (!cancelled) {
          setPreviewBusy(false);
        }
      }
    }

    void loadPreview();
    return () => {
      cancelled = true;
      controller.abort();
    };
  }, [route, wizard.inputPath, wizard.sheet, wizard.template, deferredOptions]);

  const navigate = (next: ActiveRoute) => {
    startTransition(() => {
      setRoute(next);
      workbench.setLastRoute(next);
      if (typeof window !== "undefined" && window.location.pathname !== next) {
        window.history.pushState({}, "", next);
      }
    });
  };

  const retryMeta = () => {
    setMetaBusy(true);
    setMetaError(null);
    void getWorkbenchMeta()
      .then((nextMeta) => {
        setMeta(nextMeta);
        wizard.setSidecarReady(true);
      })
      .catch((error) => {
        wizard.setSidecarReady(false);
        setMetaError(getErrorMessage(error));
      })
      .finally(() => {
        setMetaBusy(false);
      });
  };

  const rememberDataset = (path: string, detail: string) => {
    workbench.rememberProject({
      mode: "wizard",
      kind: "data",
      path,
      title: formatLeaf(path),
      detail,
    });
  };

  const resetPlotSession = (nextPath: string) => {
    wizard.setInputPath(nextPath);
    wizard.setProjectPath("");
    wizard.setSheet(0);
    wizard.setSheetNames([]);
    wizard.setInspection(null);
    wizard.setDataset(null);
    wizard.setTemplate(null);
    wizard.setPreflight(null);
    wizard.setPreviews([]);
    wizard.setPreviewIndex(0);
    wizard.setOutputs([]);
    wizard.setExportResult(null);
    wizard.setSubmissionReport(null);
    wizard.setStage("import");
    wizard.setStep("file");
    wizard.setError(null);
    if (meta) {
      wizard.setOptions(
        sanitizeRenderOptions(meta, null, {
          style_preset: meta.default_style,
          palette_preset: meta.default_palette,
        }),
      );
    } else {
      wizard.setOptions({});
    }
  };

  const inspectDataset = async (nextPath: string, nextSheet: string | number = wizard.sheet || 0) => {
    if (!nextPath.trim()) {
      wizard.setError("Choose a dataset path first.");
      return;
    }
    if (
      !confirmReplaceWizardSession(
        {
          inputPath: wizard.inputPath,
          inspection: wizard.inspection,
          template: wizard.template,
          outputs: wizard.outputs,
          exportResult: wizard.exportResult,
        },
        formatLeaf(nextPath),
        nextPath,
      )
    ) {
      return;
    }

    setImportBusy(true);
    wizard.setError(null);
    setActionMessage(null);
    resetPlotSession(nextPath);
    try {
      const response = await inspectFile(nextPath, nextSheet);
      const selection = selectionFromInspection(meta, response.inspection);
      wizard.setInputPath(response.input_path);
      wizard.setSheet(response.sheet);
      wizard.setSheetNames(response.sheet_names);
      wizard.setInspection(response.inspection);
      wizard.setDataset(response.dataset ?? null);
      wizard.setTemplate(selection.template);
      wizard.setOptions(selection.options);
      wizard.setStage("type");
      wizard.setStep("inspect");
      rememberDataset(response.input_path, response.inspection.model_label);
      navigate("/plot/import");
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      setImportBusy(false);
    }
  };

  const openDatasetDialog = async () => {
    try {
      const selected = await openDialog({
        multiple: false,
        directory: false,
        filters: [
          {
            name: "Datasets",
            extensions: ["csv", "txt", "tsv", "xlsx", "xls"],
          },
        ],
      });
      if (typeof selected === "string" && selected.trim()) {
        setPathDraft(selected);
        await inspectDataset(selected, 0);
      }
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    }
  };

  const revealTemplateFolder = async (variant: "example" | "blank") => {
    try {
      setActionMessage(null);
      const response = await materializeDataTemplateFolder({ variant });
      await openPath(response.folder_path);
      setActionMessage(
        `${variant === "example" ? "Example" : "Blank"} template folder ready at ${response.folder_path}`,
      );
    } catch (error) {
      setActionMessage(getErrorMessage(error));
    }
  };

  const selectTemplate = (templateId: TemplateName) => {
    if (!meta || !wizard.inspection) {
      return;
    }
    const selection = selectionFromInspection(meta, wizard.inspection, {
      template: templateId,
      options: wizard.options,
    });
    wizard.setTemplate(selection.template);
    wizard.setOptions(selection.options);
    wizard.setStage("tune");
    wizard.setStep("options");
    navigate("/plot/refine");
  };

  const updateRenderOptions = (patch: Partial<RenderOptionsPayload>) => {
    wizard.setOptions(
      mergeRenderOptions(meta, wizard.template, wizard.options, patch, wizard.inspection?.model),
    );
  };

  const checkReadiness = async () => {
    if (!wizard.inputPath || !wizard.template) {
      return;
    }
    setReadinessBusy(true);
    wizard.setError(null);
    try {
      const response = await preflightRender(
        wizard.inputPath,
        wizard.sheet,
        wizard.template,
        wizard.options,
      );
      wizard.setPreflight(response.preflight);
      wizard.setSubmissionReport(response.preflight.submission_report ?? null);
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      setReadinessBusy(false);
    }
  };

  const runExport = async () => {
    if (!wizard.inputPath || !wizard.template) {
      return;
    }
    setExportBusy(true);
    wizard.setError(null);
    try {
      const response = await exportRender({
        input_path: wizard.inputPath,
        sheet: wizard.sheet,
        template: wizard.template,
        options: wizard.options,
        output_dir: null,
      });
      wizard.setOutputs(response.outputs);
      wizard.setExportResult(response);
      wizard.setSubmissionReport(response.submission_report ?? wizard.submissionReport);
      wizard.setStage("export");
      wizard.setStep("export");
      rememberDataset(
        wizard.inputPath,
        `${templateLabel(meta, wizard.template)} exported to ${formatLeaf(response.output_dir)}`,
      );
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      setExportBusy(false);
    }
  };

  const openOutputDirectory = async () => {
    const target = wizard.exportResult?.output_dir;
    if (!target) {
      return;
    }
    try {
      await openPath(target);
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    }
  };

  const templateSections = inspectionRecommendationSections(meta, wizard.inspection);
  const compatibleTemplates = compatibleTemplateChoices(meta, wizard.inspection?.model);
  const incompatibleTemplates = incompatibleTemplateChoices(meta, wizard.inspection?.model);

  const currentNavItem = NAV_ITEMS.find((item) => item.route === route) ?? NAV_ITEMS[0];

  const screen = metaBusy ? (
    <div className="empty-screen">
      <p>Loading SciPlot desktop workspace…</p>
      <small>Fetching current sidecar metadata and plot contract choices.</small>
    </div>
  ) : metaError ? (
    <div className="empty-screen">
      <p>{metaError}</p>
      <small>Reconnect the sidecar to continue using the active Plot path.</small>
    </div>
  ) : route === "/" ? (
    <StartScreen
      recentItems={recentDatasets}
      onOpenDataset={() => {
        navigate("/plot/import");
        void openDatasetDialog();
      }}
      onOpenRecentDataset={(path) => {
        navigate("/plot/import");
        void inspectDataset(path, 0);
      }}
      onRevealTemplateFolder={(variant) => {
        void revealTemplateFolder(variant);
      }}
      actionMessage={actionMessage}
    />
  ) : route === "/plot/import" ? (
    <PlotImportScreen
      inputPath={pathDraft}
      sheet={wizard.sheet}
      sheetNames={wizard.sheetNames}
      inspectionModelLabel={wizard.inspection?.model_label ?? null}
      dataset={wizard.dataset}
      inspectionSummary={
        wizard.inspection
          ? {
              warnings: wizard.inspection.warnings,
              signals: wizard.inspection.signals,
              recommendationSummary: wizard.inspection.recommendation_summary,
            }
          : null
      }
      importError={wizard.error}
      importBusy={importBusy}
      onInputPathChange={(value) => {
        setPathDraft(value);
        wizard.setError(null);
      }}
      onBrowse={() => {
        void openDatasetDialog();
      }}
      onInspect={() => {
        void inspectDataset(pathDraft, wizard.sheet || 0);
      }}
      onSelectSheet={(value) => {
        void inspectDataset(wizard.inputPath || pathDraft, value);
      }}
      onContinue={() => navigate("/plot/template")}
    />
  ) : route === "/plot/template" ? (
    <PlotTemplateScreen
      templateSections={templateSections}
      incompatibleTemplates={incompatibleTemplates.length > 0 ? incompatibleTemplates : compatibleTemplates.slice(3)}
      inspectionSummary={
        wizard.inspection
          ? {
              compatibility: templateCompatibilityReason(wizard.inspection.model),
            }
          : null
      }
      onSelectTemplate={selectTemplate}
    />
  ) : (
    <PlotRefineScreen
      meta={meta}
      template={wizard.template}
      options={wizard.options}
      previews={wizard.previews}
      previewIndex={wizard.previewIndex}
      previewBusy={previewBusy}
      previewError={previewError ?? wizard.error}
      readinessBusy={readinessBusy}
      exportBusy={exportBusy}
      submissionChecks={
        wizard.submissionReport?.checks.map((check) => ({
          id: check.id,
          status: check.status,
          message: check.message,
        })) ?? []
      }
      exportOutputs={wizard.outputs}
      lastOutputDir={wizard.exportResult?.output_dir ?? null}
      onSelectPreview={(index) => wizard.setPreviewIndex(index)}
      onOptionChange={updateRenderOptions}
      onCheckReadiness={() => {
        void checkReadiness();
      }}
      onExport={() => {
        void runExport();
      }}
      onOpenOutputDir={() => {
        void openOutputDirectory();
      }}
    />
  );

  return (
    <MacWindowShell
      sidebar={
        <MacSidebar
          items={NAV_ITEMS}
          activeRoute={route}
          footer="SciPlot now ships a single plot-first desktop path."
          onNavigate={navigate}
        />
      }
      titlebar={
        <MacTitlebar
          eyebrow="Plot Workspace"
          title={currentNavItem.label}
          sidecarReady={wizard.sidecarReady}
          onRefresh={retryMeta}
        />
      }
    >
      {screen}
    </MacWindowShell>
  );
}

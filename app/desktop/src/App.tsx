import { Suspense, lazy, useEffect, useMemo, useRef, useState } from "react";
import { useShallow } from "zustand/react/shallow";

import {
  CommandBar,
  ContentPane,
  IconRail,
  StatusBar,
  WorkbenchShell,
} from "./components/workbench/V2Primitives";
import { getPlotContract, getWorkbenchMeta, healthcheck } from "./lib/api";
import {
  useComposerStore,
  useTensileStore,
  useWizardStore,
  useWorkbenchStore,
} from "./lib/store";
import type {
  PlotContract,
  WorkbenchMeta,
  WorkbenchRoute,
} from "./lib/types";
import {
  describeAppearanceMode,
  resolveAppearance,
  resolveThemePreset,
} from "./lib/themes";
import {
  WORKSPACE_ITEMS,
  WORKSPACE_META,
  formatLeaf,
  getPlotStageLabel,
  hasComposerSessionContent,
  hasWizardSessionContent,
  normalizeWorkbenchRoute,
  plotRoute,
  plotStageFromRoute,
  workspaceForRoute,
} from "./lib/workbench";

const LaunchpadScreen = lazy(async () => ({
  default: (await import("./screens/LaunchpadScreen")).LaunchpadScreen,
}));
const TensileScreen = lazy(async () => ({
  default: (await import("./screens/TensileScreen")).TensileScreen,
}));
const WizardScreen = lazy(async () => ({
  default: (await import("./screens/WizardScreen")).WizardScreen,
}));
const ComposerScreen = lazy(async () => ({
  default: (await import("./screens/ComposerScreen")).ComposerScreen,
}));
const CodeConsoleScreen = lazy(async () => ({
  default: (await import("./screens/CodeConsoleScreen")).CodeConsoleScreen,
}));
const SettingsScreen = lazy(async () => ({
  default: (await import("./screens/SettingsScreen")).SettingsScreen,
}));

function initialRoute(persistedRoute: WorkbenchRoute, rememberLastScreen: boolean) {
  if (typeof window !== "undefined") {
    const fromLocation = normalizeWorkbenchRoute(window.location.pathname);
    if (fromLocation) {
      return fromLocation;
    }
  }
  return rememberLastScreen ? persistedRoute : "/";
}

export default function App() {
  const persistedRoute = useWorkbenchStore((state) => state.lastRoute);
  const setPersistedRoute = useWorkbenchStore((state) => state.setLastRoute);
  const rememberLastScreen = useWorkbenchStore(
    (state) => state.settings.remember_last_screen,
  );
  const autoStatusPoll = useWorkbenchStore((state) => state.settings.auto_status_poll);
  const appearanceMode = useWorkbenchStore((state) => state.settings.appearance_mode);
  const themePresetId = useWorkbenchStore((state) => state.settings.theme_preset_id);
  const [route, setRoute] = useState<WorkbenchRoute>(() =>
    initialRoute(persistedRoute, rememberLastScreen),
  );
  const [prefersDark, setPrefersDark] = useState(false);
  const [workbenchMeta, setWorkbenchMeta] = useState<WorkbenchMeta | null>(null);
  const [plotContract, setPlotContract] = useState<PlotContract | null>(null);
  const [metaError, setMetaError] = useState<string | null>(null);
  const sidecarReady = useWizardStore((state) => state.sidecarReady);
  const setSidecarReady = useWizardStore((state) => state.setSidecarReady);
  const wizard = useWizardStore(
    useShallow((state) => ({
      exportResult: state.exportResult,
      inputPath: state.inputPath,
      inspection: state.inspection,
      outputsCount: state.outputs.length,
      stage: state.stage,
      template: state.template,
    })),
  );
  const tensileCompareCount = useTensileStore((state) => state.comparisonSources.length);
  const tensileOutputsCount = useTensileStore((state) => state.comparisonResult?.outputs.length ?? 0);
  const tensileLatestWorkbook = useTensileStore(
    (state) => state.preprocessResult?.output_path ?? "",
  );
  const composerProject = useComposerStore((state) => state.project);
  const composerPanelCount = composerProject.panels.length;
  const composerTextCount = composerProject.texts.length;
  const workbenchLoadRef = useRef<Promise<void> | null>(null);
  const workbenchStateRef = useRef<{
    meta: WorkbenchMeta | null;
    contract: PlotContract | null;
    metaError: string | null;
  }>({
    meta: null,
    contract: null,
    metaError: null,
  });

  const navigate = (nextRoute: WorkbenchRoute, options?: { replace?: boolean }) => {
    setRoute(nextRoute);
    if (typeof window === "undefined" || window.location.pathname === nextRoute) {
      return;
    }
    if (options?.replace) {
      window.history.replaceState(window.history.state, "", nextRoute);
      return;
    }
    window.history.pushState(window.history.state, "", nextRoute);
  };

  useEffect(() => {
    const handlePopState = () => {
      setRoute(normalizeWorkbenchRoute(window.location.pathname) ?? "/");
    };
    window.addEventListener("popstate", handlePopState);
    return () => {
      window.removeEventListener("popstate", handlePopState);
    };
  }, []);

  useEffect(() => {
    if (rememberLastScreen) {
      setPersistedRoute(route);
      return;
    }
    if (persistedRoute !== "/") {
      setPersistedRoute("/");
    }
  }, [persistedRoute, rememberLastScreen, route, setPersistedRoute]);

  const loadWorkbenchData = () => {
    if (workbenchLoadRef.current) {
      return workbenchLoadRef.current;
    }

    let request: Promise<void>;
    request = Promise.all([getWorkbenchMeta(), getPlotContract()])
      .then(([meta, contract]) => {
        setWorkbenchMeta(meta);
        setPlotContract(contract);
        setMetaError(null);
      })
      .catch((error) => {
        setMetaError(error instanceof Error ? error.message : String(error));
      })
      .finally(() => {
        if (workbenchLoadRef.current === request) {
          workbenchLoadRef.current = null;
        }
      });

    workbenchLoadRef.current = request;
    return request;
  };

  useEffect(() => {
    void loadWorkbenchData();
  }, []);

  useEffect(() => {
    workbenchStateRef.current = {
      meta: workbenchMeta,
      contract: plotContract,
      metaError,
    };
  }, [metaError, plotContract, workbenchMeta]);

  useEffect(() => {
    let cancelled = false;
    let intervalId: number | undefined;

    async function check() {
      const ok = await healthcheck();
      if (!cancelled) {
        setSidecarReady(ok);
        if (ok) {
          const { meta, contract, metaError: currentMetaError } = workbenchStateRef.current;
          if (!meta || !contract || currentMetaError) {
            void loadWorkbenchData();
          }
        }
      }
    }

    void check();
    if (autoStatusPoll) {
      intervalId = window.setInterval(() => {
        void check();
      }, 6000);
    }

    return () => {
      cancelled = true;
      if (intervalId) {
        window.clearInterval(intervalId);
      }
    };
  }, [autoStatusPoll, setSidecarReady]);

  useEffect(() => {
    if (sidecarReady && (!workbenchMeta || !plotContract || metaError)) {
      void loadWorkbenchData();
    }
  }, [metaError, plotContract, sidecarReady, workbenchMeta]);

  const resolvedAppearanceValue = resolveAppearance(appearanceMode, prefersDark);
  const activeThemePreset = resolveThemePreset(themePresetId, resolvedAppearanceValue);

  useEffect(() => {
    if (typeof window === "undefined" || typeof document === "undefined") {
      return;
    }

    const root = document.documentElement;
    const mediaQuery =
      typeof window.matchMedia === "function"
        ? window.matchMedia("(prefers-color-scheme: dark)")
        : null;

    const syncPreference = () => {
      const nextPrefersDark = Boolean(mediaQuery?.matches);
      setPrefersDark(nextPrefersDark);
      const theme = resolveAppearance(appearanceMode, nextPrefersDark);
      const preset = resolveThemePreset(themePresetId, theme);
      root.dataset.theme = theme;
      root.dataset.themePreset = preset.id;
      root.style.colorScheme = theme;
    };

    syncPreference();

    if (!mediaQuery) {
      return;
    }

    const handleChange = () => {
      syncPreference();
    };

    if (typeof mediaQuery.addEventListener === "function") {
      mediaQuery.addEventListener("change", handleChange);
      return () => {
        mediaQuery.removeEventListener("change", handleChange);
      };
    }

    mediaQuery.addListener(handleChange);
    return () => {
      mediaQuery.removeListener(handleChange);
    };
  }, [appearanceMode, themePresetId]);

  const workspace = workspaceForRoute(route);
  const studioWorkspace =
    workspace === "launchpad" || workspace === "plot" || workspace === "composer";
  const meta = WORKSPACE_META[workspace];
  const currentPlotStage = plotStageFromRoute(route);
  const importFocus = workspace === "plot" && currentPlotStage === "import";
  const plotSessionActive = hasWizardSessionContent({
    inputPath: wizard.inputPath,
    inspection: wizard.inspection,
    template: wizard.template,
    outputs: wizard.outputsCount > 0 ? new Array(wizard.outputsCount).fill("") : [],
    exportResult: wizard.exportResult,
  });
  const composerSessionActive = hasComposerSessionContent(composerProject);

  const workspaceLinks = useMemo(
    () =>
      WORKSPACE_ITEMS.map((item) => ({
        ...item,
        route:
          item.workspace === "plot"
            ? plotSessionActive
              ? plotRoute(wizard.stage)
              : "/plot/import"
            : item.workspace === "tensile"
              ? "/tensile"
              : item.workspace === "composer"
                ? "/composer"
                : item.workspace === "code"
                  ? "/code-console"
                : "/settings",
      })),
    [plotSessionActive, wizard.stage],
  );
  const railItems = [
    {
      id: "start",
      label: "Start",
      icon: "home" as const,
      active: workspace === "launchpad",
      onSelect: () => navigate("/"),
    },
    ...workspaceLinks.map((item) => ({
      id: item.workspace,
      label: item.label,
      icon: item.icon,
      active: workspace === item.workspace,
      onSelect: () => navigate(item.route),
    })),
  ];

  let secondaryStatusLabel = "Focus mode";
  if (workspace === "plot") {
    secondaryStatusLabel =
      wizard.outputsCount > 0
        ? `${getPlotStageLabel(wizard.stage)} / ${wizard.outputsCount} outputs`
        : `${getPlotStageLabel(plotStageFromRoute(route))} stage`;
  } else if (workspace === "tensile") {
    secondaryStatusLabel =
      tensileOutputsCount > 0
        ? `${tensileCompareCount} sources / ${tensileOutputsCount} outputs`
        : `${tensileCompareCount} sources queued`;
  } else if (workspace === "composer") {
    secondaryStatusLabel = `${composerPanelCount + composerTextCount} objects`;
  } else if (workspace === "code") {
    secondaryStatusLabel = wizard.inputPath ? "Current plot context" : "Waiting for Plot session";
  } else if (workspace === "settings") {
    secondaryStatusLabel = `${describeAppearanceMode(appearanceMode)} · ${activeThemePreset.name}`;
  } else if (plotSessionActive) {
    secondaryStatusLabel = `Plot session · ${getPlotStageLabel(wizard.stage)}`;
  } else if (composerSessionActive) {
    secondaryStatusLabel = "Composer session ready";
  }

  let activeItemLabel = "Next action";
  let activeItemValue = "Choose a workspace and start working.";
  if (workspace === "plot") {
    activeItemLabel = importFocus ? "Source" : "Active file";
    activeItemValue = wizard.inputPath ? formatLeaf(wizard.inputPath) : "No file loaded";
  } else if (workspace === "tensile") {
    activeItemLabel = "Latest workbook";
    activeItemValue = tensileLatestWorkbook ? formatLeaf(tensileLatestWorkbook) : "No workbook prepared";
  } else if (workspace === "composer") {
    activeItemLabel = "Canvas";
    activeItemValue =
      composerPanelCount + composerTextCount > 0
        ? `${composerPanelCount + composerTextCount} visible objects in session`
        : "No composition open";
  } else if (workspace === "code") {
    activeItemLabel = "Bound data";
    activeItemValue = wizard.inputPath ? formatLeaf(wizard.inputPath) : "No data bound";
  } else if (workspace === "settings") {
    activeItemLabel = "Appearance";
    activeItemValue = `${describeAppearanceMode(appearanceMode)} / ${activeThemePreset.name}`;
  } else if (plotSessionActive) {
    activeItemLabel = "Resume";
    activeItemValue = `Plot · ${getPlotStageLabel(wizard.stage)}`;
  } else if (composerSessionActive) {
    activeItemLabel = "Resume";
    activeItemValue = "Composer session ready";
  }

  const commandActions = (() => {
    if (workspace === "launchpad") {
      return [
        { id: "plot-new", label: "New Plot", kind: "primary" as const, onSelect: () => navigate("/plot/import") },
        { id: "open-composer", label: "Composer", onSelect: () => navigate("/composer") },
        { id: "open-settings", label: "Settings", onSelect: () => navigate("/settings") },
      ];
    }
    if (workspace === "plot") {
      if (importFocus) {
        return [
          {
            id: "plot-continue",
            label: "Continue",
            kind: "primary" as const,
            disabled: !wizard.inputPath,
            onSelect: () => navigate("/plot/type"),
          },
          {
            id: "plot-review",
            label: "Review",
            disabled: !wizard.inputPath,
            onSelect: () => navigate("/plot/review"),
          },
        ];
      }
      return [
        { id: "plot-import", label: "Import", kind: "primary" as const, onSelect: () => navigate("/plot/import") },
        { id: "plot-review", label: "Review", onSelect: () => navigate("/plot/review") },
        { id: "plot-composer", label: "Composer", onSelect: () => navigate("/composer") },
      ];
    }
    if (workspace === "tensile") {
      return [
        { id: "tensile-plot", label: "Plot", kind: "primary" as const, onSelect: () => navigate("/plot/import") },
        { id: "tensile-code", label: "Code Console", onSelect: () => navigate("/code-console") },
        { id: "tensile-settings", label: "Settings", onSelect: () => navigate("/settings") },
      ];
    }
    if (workspace === "composer") {
      return [
        { id: "composer-open", label: "Start", onSelect: () => navigate("/") },
        { id: "composer-plot", label: "Plot", kind: "primary" as const, onSelect: () => navigate("/plot/import") },
        { id: "composer-settings", label: "Settings", onSelect: () => navigate("/settings") },
      ];
    }
    if (workspace === "code") {
      return [
        { id: "code-plot", label: "Plot", kind: "primary" as const, onSelect: () => navigate("/plot/import") },
        { id: "code-composer", label: "Composer", onSelect: () => navigate("/composer") },
        { id: "code-settings", label: "Settings", onSelect: () => navigate("/settings") },
      ];
    }
    return [
      { id: "settings-start", label: "Start", onSelect: () => navigate("/") },
      { id: "settings-plot", label: "Plot", kind: "primary" as const, onSelect: () => navigate("/plot/import") },
      { id: "settings-composer", label: "Composer", onSelect: () => navigate("/composer") },
    ];
  })();

  const shellClassName = [
    studioWorkspace ? "wb-studio-shell" : "",
    importFocus ? "wb-import-focus" : "",
  ]
    .filter(Boolean)
    .join(" ");

  let content = (
    <LaunchpadScreen
      meta={workbenchMeta}
      onNavigate={navigate}
    />
  );

  if (workspace === "plot") {
    content = (
      <WizardScreen
        meta={workbenchMeta}
        onNavigate={navigate}
        routeStage={plotStageFromRoute(route)}
      />
    );
  } else if (workspace === "tensile") {
    content = <TensileScreen meta={workbenchMeta} onNavigate={navigate} />;
  } else if (workspace === "composer") {
    content = <ComposerScreen />;
  } else if (workspace === "code") {
    content = <CodeConsoleScreen contract={plotContract} meta={workbenchMeta} onNavigate={navigate} />;
  } else if (workspace === "settings") {
    content = <SettingsScreen contract={plotContract} meta={workbenchMeta} />;
  }

  return (
    <WorkbenchShell
      className={shellClassName}
      commandBar={
        <CommandBar
          actions={commandActions}
          moduleLabel={workspace === "plot" ? `${meta.eyebrow} · ${getPlotStageLabel(currentPlotStage)}` : meta.eyebrow}
          moduleTitle={meta.title}
          objectLabel={activeItemLabel}
          objectValue={activeItemValue}
          runtimeStatusLabel={sidecarReady ? "Sidecar Online" : "Sidecar Offline"}
          runtimeTone={sidecarReady ? "good" : "warn"}
          sessionLabel={importFocus ? undefined : secondaryStatusLabel}
        />
      }
      content={
        <>
          {metaError && <div className="warning-card topbar-warning">{metaError}</div>}
          <ContentPane className="app-main wb-legacy-content">
            <Suspense fallback={<div className="placeholder-card">Loading workspace…</div>}>
              {content}
            </Suspense>
          </ContentPane>
        </>
      }
      rail={
        <IconRail
          brandLabel="SciPlot God"
          footer={importFocus ? null : (
            <span>
              {plotSessionActive || composerSessionActive
                ? `${Number(plotSessionActive) + Number(composerSessionActive)} active`
                : "Idle"}
            </span>
          )}
          items={railItems}
          onBrandSelect={() => navigate("/")}
          variant={importFocus ? "icon" : studioWorkspace ? "text" : "icon"}
        />
      }
      statusBar={
        <StatusBar
          left={`${meta.title} · ${secondaryStatusLabel}`}
          right={`Appearance: ${describeAppearanceMode(appearanceMode)} · ${activeThemePreset.name}`}
        />
      }
    />
  );
}

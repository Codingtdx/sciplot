import type {
  ComposerPreviewResponse,
  ComposerProject,
  ExportResponse,
  InspectResponse,
  PlotContract,
  PreflightResponse,
  RenderOptionsPayload,
  RenderPreviewResponse,
  TemplateName,
  TensileComparisonExportResponse,
  TensileWorkbookSummary,
  TensileReplicateResponse,
  WorkbenchMeta,
} from "./types";
import { coercePlotContract, coerceWorkbenchMeta } from "./runtime";
import { resolveSidecarUrl } from "./sidecar";

const SIDECAR_URL = resolveSidecarUrl();

type RequestOptions = {
  signal?: AbortSignal;
};

async function postJson<T>(
  path: string,
  body: unknown,
  options: RequestOptions = {},
): Promise<T> {
  const response = await fetch(`${SIDECAR_URL}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: options.signal,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const detail =
      typeof payload?.detail === "string"
        ? payload.detail
        : `Request failed: ${response.status}`;
    throw new Error(detail);
  }
  return payload as T;
}

async function getJson<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const response = await fetch(`${SIDECAR_URL}${path}`, {
    signal: options.signal,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const detail =
      typeof payload?.detail === "string"
        ? payload.detail
        : `Request failed: ${response.status}`;
    throw new Error(detail);
  }
  return payload as T;
}

export async function healthcheck(options: RequestOptions = {}): Promise<boolean> {
  try {
    const response = await fetch(`${SIDECAR_URL}/health`, {
      signal: options.signal,
    });
    return response.ok;
  } catch {
    return false;
  }
}

export async function getWorkbenchMeta(options: RequestOptions = {}): Promise<WorkbenchMeta> {
  return coerceWorkbenchMeta(await getJson<unknown>("/meta", options));
}

export async function getPlotContract(options: RequestOptions = {}): Promise<PlotContract> {
  return coercePlotContract(await getJson<unknown>("/plot-contract", options));
}

export async function inspectFile(
  inputPath: string,
  sheet: string | number,
  options: RequestOptions = {},
): Promise<InspectResponse> {
  return postJson<InspectResponse>("/inspect-file", {
    input_path: inputPath,
    sheet,
  }, options);
}

export async function preflightRender(
  inputPath: string,
  sheet: string | number,
  template: TemplateName,
  options: RenderOptionsPayload,
  requestOptions: RequestOptions = {},
): Promise<PreflightResponse> {
  return postJson<PreflightResponse>("/preflight-render", {
    input_path: inputPath,
    sheet,
    template,
    options,
  }, requestOptions);
}

export async function renderPreview(
  inputPath: string,
  sheet: string | number,
  template: TemplateName,
  options: RenderOptionsPayload,
  requestOptions: RequestOptions = {},
): Promise<RenderPreviewResponse> {
  return postJson<RenderPreviewResponse>("/render-preview", {
    input_path: inputPath,
    sheet,
    template,
    options,
  }, requestOptions);
}

export async function exportRender(
  inputPath: string,
  sheet: string | number,
  template: TemplateName,
  options: RenderOptionsPayload,
  outputDir?: string,
  requestOptions: RequestOptions = {},
): Promise<ExportResponse> {
  return postJson<ExportResponse>("/export-render", {
    input_path: inputPath,
    sheet,
    template,
    options,
    output_dir: outputDir ?? null,
  }, requestOptions);
}

export async function preprocessTensileReplicates(
  filePaths: string[],
  outputPath: string,
  groupName?: string,
  options: RequestOptions = {},
): Promise<TensileReplicateResponse> {
  return postJson<TensileReplicateResponse>("/preprocess-tensile-replicates", {
    file_paths: filePaths,
    output_path: outputPath,
    group_name: groupName ?? null,
  }, options);
}

export async function inspectTensileWorkbook(
  workbookPath: string,
  options: RequestOptions = {},
): Promise<TensileWorkbookSummary> {
  return postJson<TensileWorkbookSummary>("/inspect-tensile-workbook", {
    workbook_path: workbookPath,
  }, options);
}

export async function exportTensileComparison(
  workbookPaths: string[],
  outputDir: string,
  options: RequestOptions = {},
): Promise<TensileComparisonExportResponse> {
  return postJson<TensileComparisonExportResponse>("/export-tensile-comparison", {
    workbook_paths: workbookPaths,
    output_dir: outputDir,
  }, options);
}

export async function panelThumbnail(
  filePath: string,
  pageIndex = 0,
  options: RequestOptions = {},
): Promise<string> {
  const response = await postJson<{ png_base64: string }>("/panel-thumbnail", {
    file_path: filePath,
    page_index: pageIndex,
  }, options);
  return response.png_base64;
}

export async function composePreview(project: ComposerProject): Promise<{
  valid: boolean;
  validation_error: string | null;
  png_base64: string;
}> {
  return composePreviewWithOptions(project);
}

export async function composePreviewWithOptions(
  project: ComposerProject,
  options: RequestOptions = {},
): Promise<ComposerPreviewResponse> {
  return postJson<ComposerPreviewResponse>("/compose-preview", project, options);
}

export async function composeExport(project: ComposerProject): Promise<{
  output_path: string;
}> {
  return postJson("/compose-export", project);
}

export async function threeUp(filePaths: string[]): Promise<ComposerProject> {
  return postJson("/composer/three-up", filePaths);
}

export async function twoUpEditorial(filePaths: string[]): Promise<ComposerProject> {
  return postJson("/composer/two-up-editorial", filePaths);
}

export async function importComposerPanels(
  project: ComposerProject,
  filePaths: string[],
  kind: "graph" | "asset",
): Promise<ComposerProject> {
  return postJson("/composer/import-panels", {
    project,
    file_paths: filePaths,
    kind,
  });
}

export async function saveProject(projectPath: string, data: unknown): Promise<void> {
  await postJson("/save-project", {
    project_path: projectPath,
    data,
  });
}

export async function openProject(projectPath: string): Promise<unknown> {
  const response = await postJson<{ data: unknown }>("/open-project", {
    project_path: projectPath,
  });
  return response.data;
}

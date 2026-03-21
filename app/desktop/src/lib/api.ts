import type {
  CodeConsoleExportResponse,
  CodeConsoleGenerateResponse,
  CodeConsoleRunResponse,
  ComposerPreviewResponse,
  DataTemplateCatalogResponse,
  DataTemplateFolderResponse,
  DataTemplateMaterializeResponse,
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
import {
  coerceCodeConsoleRunResponse,
  coerceCodeConsoleExportResponse,
  coerceCodeConsoleGenerateResponse,
  coerceDataTemplateCatalog,
  coerceDataTemplateFolderResponse,
  coerceDataTemplateMaterializeResponse,
  coercePlotContract,
  coerceWorkbenchMeta,
} from "./runtime";
import { resolveSidecarUrl } from "./sidecar";

const SIDECAR_URL = resolveSidecarUrl();

type RequestOptions = {
  signal?: AbortSignal;
};

type JsonRequestResult<T> = {
  payload: T;
  method: "GET" | "POST";
  url: string;
  status: number;
  bodyText: string;
};

function shouldDebugSidecarRequest(path: string) {
  return path === "/data-templates/folder" || path === "/open-path";
}

function formatResponseDebugBody(bodyText: string, payload: unknown) {
  const trimmedText = bodyText.trim();
  if (trimmedText !== "") {
    return trimmedText;
  }
  if (payload && typeof payload === "object" && Object.keys(payload).length > 0) {
    return JSON.stringify(payload);
  }
  return "(empty response body)";
}

async function requestJson<T>(
  method: "GET" | "POST",
  path: string,
  body: unknown,
  options: RequestOptions = {},
): Promise<JsonRequestResult<T>> {
  const url = `${SIDECAR_URL}${path}`;
  if (shouldDebugSidecarRequest(path)) {
    console.info("[sidecar]", {
      sidecarBaseUrl: SIDECAR_URL,
      method,
      url,
      requestBody: body,
    });
  }
  const response = await fetch(url, {
    method,
    headers: method === "POST" ? { "Content-Type": "application/json" } : undefined,
    body: method === "POST" ? JSON.stringify(body) : undefined,
    signal: options.signal,
  });
  const bodyText = await response.text();
  const payload = bodyText === "" ? {} : await Promise.resolve().then(() => JSON.parse(bodyText)).catch(() => ({}));
  if (shouldDebugSidecarRequest(path)) {
    console.info("[sidecar]", {
      sidecarBaseUrl: SIDECAR_URL,
      method,
      url,
      responseStatus: response.status,
      responseBody: formatResponseDebugBody(bodyText, payload),
    });
  }
  if (!response.ok) {
    throw new Error(
      `${method} ${url} -> ${response.status} ${formatResponseDebugBody(
        bodyText,
        payload,
      )} (sidecar base url: ${SIDECAR_URL})`,
    );
  }
  return {
    payload: payload as T,
    method,
    url,
    status: response.status,
    bodyText,
  };
}

async function postJson<T>(
  path: string,
  body: unknown,
  options: RequestOptions = {},
): Promise<T> {
  return (await requestJson<T>("POST", path, body, options)).payload;
}

async function getJson<T>(path: string, options: RequestOptions = {}): Promise<T> {
  return (await requestJson<T>("GET", path, null, options)).payload;
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

export async function getDataTemplateCatalog(
  options: RequestOptions = {},
): Promise<DataTemplateCatalogResponse> {
  return coerceDataTemplateCatalog(await getJson<unknown>("/data-templates", options));
}

export async function materializeDataTemplate(
  payload: {
    template_id: string;
    variant: "example" | "blank";
  },
  options: RequestOptions = {},
): Promise<DataTemplateMaterializeResponse> {
  return coerceDataTemplateMaterializeResponse(
    await postJson<unknown>("/data-templates/materialize", payload, options),
  );
}

export async function materializeDataTemplateFolder(
  payload: {
    variant: "example" | "blank";
  },
  options: RequestOptions = {},
): Promise<DataTemplateFolderResponse> {
  return coerceDataTemplateFolderResponse(
    await postJson<unknown>("/data-templates/folder", payload, options),
  );
}

export async function generateCodeConsole(
  payload: {
    intent: "custom_plot" | "patch_renderer" | "annotation_tweak";
    brief: string;
    base_template: string;
    options?: RenderOptionsPayload | null;
    size?: string | null;
    style_preset?: string | null;
    palette_preset?: string | null;
    target_path?: string | null;
    input_path?: string | null;
    sheet?: string | number | null;
    project_path?: string | null;
    include_data_context: boolean;
    include_inspection_summary: boolean;
    include_project_context: boolean;
  },
  options: RequestOptions = {},
): Promise<CodeConsoleGenerateResponse> {
  return coerceCodeConsoleGenerateResponse(
    await postJson<unknown>("/code-console/generate", payload, options),
  );
}

export async function runCodeConsole(
  payload: {
    code: string;
    base_template: string;
    options?: RenderOptionsPayload | null;
    input_path: string;
    sheet?: string | number | null;
    project_path?: string | null;
    include_project_context: boolean;
  },
  options: RequestOptions = {},
): Promise<CodeConsoleRunResponse> {
  return coerceCodeConsoleRunResponse(
    await postJson<unknown>("/code-console/run", payload, options),
  );
}

export async function exportCodeConsoleBundle(
  payload: {
    intent: "custom_plot" | "patch_renderer" | "annotation_tweak";
    brief: string;
    base_template: string;
    options?: RenderOptionsPayload | null;
    size?: string | null;
    style_preset?: string | null;
    palette_preset?: string | null;
    target_path?: string | null;
    input_path?: string | null;
    sheet?: string | number | null;
    project_path?: string | null;
    include_data_context: boolean;
    include_inspection_summary: boolean;
    include_project_context: boolean;
    output_dir: string;
    include_full_data: boolean;
  },
  options: RequestOptions = {},
): Promise<CodeConsoleExportResponse> {
  return coerceCodeConsoleExportResponse(
    await postJson<unknown>("/code-console/export-bundle", payload, options),
  );
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

export async function openPath(
  outputPath: string,
  requestOptions: RequestOptions = {},
): Promise<{ output_path: string }> {
  return postJson<{ output_path: string }>("/open-path", {
    output_path: outputPath,
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

import type {
  ComposerPanel,
  ComposerProject,
  ExportResponse,
  InspectResponse,
  PreflightResponse,
  RenderOptionsPayload,
  RenderPreviewResponse,
  TemplateName,
} from "./types";

const SIDECAR_URL = "http://127.0.0.1:8765";

async function postJson<T>(path: string, body: unknown): Promise<T> {
  const response = await fetch(`${SIDECAR_URL}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
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

export async function healthcheck(): Promise<boolean> {
  try {
    const response = await fetch(`${SIDECAR_URL}/health`);
    return response.ok;
  } catch {
    return false;
  }
}

export async function inspectFile(
  inputPath: string,
  sheet: string | number,
): Promise<InspectResponse> {
  return postJson<InspectResponse>("/inspect-file", {
    input_path: inputPath,
    sheet,
  });
}

export async function preflightRender(
  inputPath: string,
  sheet: string | number,
  template: TemplateName,
  options: RenderOptionsPayload,
): Promise<PreflightResponse> {
  return postJson<PreflightResponse>("/preflight-render", {
    input_path: inputPath,
    sheet,
    template,
    options,
  });
}

export async function renderPreview(
  inputPath: string,
  sheet: string | number,
  template: TemplateName,
  options: RenderOptionsPayload,
): Promise<RenderPreviewResponse> {
  return postJson<RenderPreviewResponse>("/render-preview", {
    input_path: inputPath,
    sheet,
    template,
    options,
  });
}

export async function exportRender(
  inputPath: string,
  sheet: string | number,
  template: TemplateName,
  options: RenderOptionsPayload,
  outputDir?: string,
): Promise<ExportResponse> {
  return postJson<ExportResponse>("/export-render", {
    input_path: inputPath,
    sheet,
    template,
    options,
    output_dir: outputDir ?? null,
  });
}

export async function panelThumbnail(
  filePath: string,
  pageIndex = 0,
): Promise<string> {
  const response = await postJson<{ png_base64: string }>("/panel-thumbnail", {
    file_path: filePath,
    page_index: pageIndex,
  });
  return response.png_base64;
}

export async function composePreview(project: ComposerProject): Promise<{
  valid: boolean;
  validation_error: string | null;
  png_base64: string;
}> {
  return postJson("/compose-preview", project);
}

export async function composeExport(project: ComposerProject): Promise<{
  output_path: string;
}> {
  return postJson("/compose-export", project);
}

export async function threeUp(filePaths: string[]): Promise<{ panels: ComposerPanel[] }> {
  return postJson("/composer/three-up", filePaths);
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

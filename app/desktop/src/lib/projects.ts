import type { RenderOptionsPayload, WizardProject } from "./types";

function asObject(payload: unknown): Record<string, unknown> {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error("这不是可识别的绘图精灵项目文件。");
  }
  return payload as Record<string, unknown>;
}

function asRenderOptions(payload: unknown): RenderOptionsPayload {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return {};
  }
  const candidate = payload as Record<string, unknown>;
  const next: RenderOptionsPayload = {};
  if (typeof candidate.size === "string") {
    next.size = candidate.size;
  }
  if (candidate.xscale === "linear" || candidate.xscale === "log") {
    next.xscale = candidate.xscale;
  }
  if (candidate.yscale === "linear" || candidate.yscale === "log") {
    next.yscale = candidate.yscale;
  }
  if (typeof candidate.reverse_x === "boolean") {
    next.reverse_x = candidate.reverse_x;
  }
  if (candidate.baseline === "none" || candidate.baseline === "linear_endpoints") {
    next.baseline = candidate.baseline;
  }
  if (typeof candidate.show_colorbar === "boolean") {
    next.show_colorbar = candidate.show_colorbar;
  }
  if (typeof candidate.palette_preset === "string") {
    next.palette_preset = candidate.palette_preset;
  }
  if (typeof candidate.use_sidecar === "boolean") {
    next.use_sidecar = candidate.use_sidecar;
  }
  return next;
}

export function extractWizardProject(payload: unknown): WizardProject {
  const candidate = asObject(payload);
  if (candidate.mode !== "wizard") {
    throw new Error("这不是可识别的绘图精灵项目文件。");
  }

  const wizard = asObject(candidate.wizard);
  if (typeof wizard.input_path !== "string" || wizard.input_path.trim().length === 0) {
    throw new Error("绘图项目文件缺少有效的数据路径。");
  }

  return {
    version: typeof candidate.version === "number" ? candidate.version : 1,
    mode: "wizard",
    wizard: {
      input_path: wizard.input_path,
      sheet:
        typeof wizard.sheet === "number" || typeof wizard.sheet === "string"
          ? wizard.sheet
          : 0,
      template: typeof wizard.template === "string" ? wizard.template : null,
      options: asRenderOptions(wizard.options),
      outputs: Array.isArray(wizard.outputs)
        ? wizard.outputs.filter((item): item is string => typeof item === "string")
        : [],
    },
  };
}

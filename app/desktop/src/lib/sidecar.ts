export const DEFAULT_SIDECAR_URL = "http://127.0.0.1:8765";

type SidecarRuntimeConfig = {
  __CODEGOD_SIDECAR_URL__?: unknown;
};

function normalizeBaseUrl(value: string): string {
  return value.replace(/\/+$/, "");
}

export function resolveSidecarUrl(): string {
  const runtimeOverride = (globalThis as SidecarRuntimeConfig).__CODEGOD_SIDECAR_URL__;
  const envOverride =
    import.meta.env.VITE_SIDECAR_URL ?? import.meta.env.TAURI_SIDECAR_URL;

  if (typeof runtimeOverride === "string" && runtimeOverride.trim() !== "") {
    return normalizeBaseUrl(runtimeOverride.trim());
  }
  if (typeof envOverride === "string" && envOverride.trim() !== "") {
    return normalizeBaseUrl(envOverride.trim());
  }
  return DEFAULT_SIDECAR_URL;
}

function stableValue(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(stableValue);
  }
  if (value && typeof value === "object") {
    return Object.keys(value as Record<string, unknown>)
      .sort()
      .reduce<Record<string, unknown>>((result, key) => {
        result[key] = stableValue((value as Record<string, unknown>)[key]);
        return result;
      }, {});
  }
  return value;
}

export function stableStringify(value: unknown): string {
  return JSON.stringify(stableValue(value));
}

export function requestCacheKey(namespace: string, value: unknown): string {
  return `${namespace}:${stableStringify(value)}`;
}

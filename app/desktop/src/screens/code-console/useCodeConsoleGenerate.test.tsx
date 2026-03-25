import { act, renderHook } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { generateCodeConsole } from "../../lib/api";
import type { CodeConsoleGenerateResponse } from "../../lib/types";
import { useCodeConsoleGenerate } from "./useCodeConsoleGenerate";

vi.mock("../../lib/api", async () => {
  const actual = await vi.importActual<typeof import("../../lib/api")>("../../lib/api");
  return {
    ...actual,
    generateCodeConsole: vi.fn(),
  };
});

function makeRequest(brief: string) {
  return {
    intent: "custom_plot" as const,
    brief,
    base_template: "curve",
    include_data_context: true,
    include_inspection_summary: true,
    include_project_context: false,
  };
}

function fakeResponse(id: string): CodeConsoleGenerateResponse {
  return {
    bundle_version: 1,
    generated_at: id,
  } as unknown as CodeConsoleGenerateResponse;
}

describe("useCodeConsoleGenerate", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("aborts the previous request when a new generate call starts", async () => {
    let firstSignal: AbortSignal | undefined;
    const latestResponse = fakeResponse("latest");

    vi.mocked(generateCodeConsole)
      .mockImplementationOnce((_request, options = {}) => {
        firstSignal = options.signal;
        return new Promise((_resolve, reject) => {
          options.signal?.addEventListener("abort", () => {
            reject(new DOMException("The operation was aborted.", "AbortError"));
          });
        });
      })
      .mockResolvedValueOnce(latestResponse);

    const { result } = renderHook(() => useCodeConsoleGenerate());

    await act(async () => {
      void result.current.generate(makeRequest("abort-me"));
    });
    await act(async () => {
      await result.current.generate(makeRequest("keep-me"));
    });

    expect(firstSignal?.aborted).toBe(true);
    expect(generateCodeConsole).toHaveBeenCalledTimes(2);
    expect(result.current.activity).toBe("ready");
    expect(result.current.error).toBeNull();
    expect(result.current.result).toBe(latestResponse);
  });

  it("uses the response cache for repeated identical requests", async () => {
    const cachedResponse = fakeResponse("cached");
    vi.mocked(generateCodeConsole).mockResolvedValue(cachedResponse);

    const { result } = renderHook(() => useCodeConsoleGenerate());
    const request = makeRequest("cache-hit");

    await act(async () => {
      await result.current.generate(request);
    });
    await act(async () => {
      await result.current.generate(request);
    });

    expect(generateCodeConsole).toHaveBeenCalledTimes(1);
    expect(result.current.activity).toBe("ready");
    expect(result.current.result).toBe(cachedResponse);
  });

  it("reset aborts in-flight work and returns to idle", async () => {
    let signal: AbortSignal | undefined;
    vi.mocked(generateCodeConsole).mockImplementation((_request, options = {}) => {
      signal = options.signal;
      return new Promise((_resolve, reject) => {
        options.signal?.addEventListener("abort", () => {
          reject(new DOMException("The operation was aborted.", "AbortError"));
        });
      });
    });

    const { result } = renderHook(() => useCodeConsoleGenerate());

    await act(async () => {
      void result.current.generate(makeRequest("reset-me"));
    });

    act(() => {
      result.current.reset();
    });

    expect(signal?.aborted).toBe(true);
    expect(result.current.activity).toBe("idle");
    expect(result.current.error).toBeNull();
    expect(result.current.result).toBeNull();
  });
});

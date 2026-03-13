import "@testing-library/jest-dom/vitest";
import { beforeEach, vi } from "vitest";

const createMemoryStorage = () => {
  const store = new Map<string, string>();
  return {
    getItem: (key: string) => store.get(key) ?? null,
    setItem: (key: string, value: string) => {
      store.set(key, value);
    },
    removeItem: (key: string) => {
      store.delete(key);
    },
    clear: () => {
      store.clear();
    },
  };
};

const memoryStorage = createMemoryStorage();
Object.defineProperty(window, "localStorage", {
  value: memoryStorage,
  configurable: true,
});
Object.defineProperty(globalThis, "localStorage", {
  value: memoryStorage,
  configurable: true,
});
Object.defineProperty(window, "matchMedia", {
  writable: true,
  configurable: true,
  value: vi.fn().mockImplementation((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    addListener: vi.fn(),
    removeListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
});

beforeEach(() => {
  window.localStorage?.clear?.();
});

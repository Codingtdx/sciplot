import "@testing-library/jest-dom/vitest";
import { beforeEach } from "vitest";

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

beforeEach(() => {
  window.localStorage?.clear?.();
});

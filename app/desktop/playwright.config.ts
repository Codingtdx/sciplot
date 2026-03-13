import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  testMatch: "**/*.e2e.ts",
  fullyParallel: true,
  reporter: "list",
  timeout: 30_000,
  expect: {
    timeout: 5_000,
  },
  use: {
    baseURL: "http://127.0.0.1:1420",
    trace: "retain-on-failure",
    viewport: {
      width: 1600,
      height: 1400,
    },
  },
  webServer: {
    command: "npm run dev -- --host 127.0.0.1",
    port: 1420,
    reuseExistingServer: !process.env.CI,
    timeout: 30_000,
  },
  projects: [
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        viewport: {
          width: 1600,
          height: 1400,
        },
      },
    },
  ],
});

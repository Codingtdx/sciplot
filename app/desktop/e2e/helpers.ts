import { expect, type Page } from "@playwright/test";

import {
  BLANK_PNG_BASE64,
  COMPOSER_E2E_PROJECT,
  TEST_CONTRACT,
  TEST_META,
} from "./fixtures";

const WORKBENCH_STORAGE_KEY = "codegod-workbench-store";
const COMPOSER_STORAGE_KEY = "codegod-composer-store";
const WIZARD_STORAGE_KEY = "codegod-wizard-store";

export async function mockSidecar(page: Page) {
  await page.route("http://127.0.0.1:8765/**", async (route) => {
    const url = new URL(route.request().url());

    if (route.request().method() === "GET" && url.pathname === "/health") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ ok: true }),
      });
      return;
    }

    if (route.request().method() === "GET" && url.pathname === "/meta") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify(TEST_META),
      });
      return;
    }

    if (route.request().method() === "GET" && url.pathname === "/plot-contract") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify(TEST_CONTRACT),
      });
      return;
    }

    if (route.request().method() === "POST" && url.pathname === "/compose-preview") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          valid: true,
          validation_error: null,
          png_base64: BLANK_PNG_BASE64,
        }),
      });
      return;
    }

    if (route.request().method() === "POST" && url.pathname === "/panel-thumbnail") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          png_base64: BLANK_PNG_BASE64,
        }),
      });
      return;
    }

    await route.fulfill({
      status: 404,
      contentType: "application/json",
      body: JSON.stringify({ detail: `Unhandled E2E route: ${url.pathname}` }),
    });
  });
}

export async function seedComposerSession(page: Page) {
  await page.addInitScript((payload) => {
    const workbenchState = {
      state: {
        lastScreen: "composer",
        pdfImportMode: "graph",
        recentProjects: [],
        settings: {
          auto_status_poll: false,
          remember_last_screen: true,
        },
      },
      version: 0,
    };
    const composerState = {
      state: {
        project: payload.project,
        palettePreset: "colorblind_safe",
      },
      version: 2,
    };

    window.localStorage.clear();
    window.localStorage.setItem("codegod-workbench-store", JSON.stringify(workbenchState));
    window.localStorage.setItem("codegod-composer-store", JSON.stringify(composerState));
    window.localStorage.setItem(
      "codegod-wizard-store",
      JSON.stringify({
        state: {},
        version: 0,
      }),
    );
  }, { project: COMPOSER_E2E_PROJECT });
}

export async function openComposerWorkbench(page: Page) {
  await mockSidecar(page);
  await seedComposerSession(page);
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "拼图器工作台" })).toBeVisible();
  const stage = page.locator(".composer-stage .konvajs-content");
  await stage.scrollIntoViewIfNeeded();
  await expect(stage).toBeVisible();
}

export async function canvasPoint(page: Page, xMm: number, yMm: number) {
  const box = await page.locator(".composer-stage .konvajs-content").boundingBox();
  if (!box) {
    throw new Error("Composer canvas is not visible.");
  }
  return {
    x: box.x + xMm * 4,
    y: box.y + yMm * 4,
  };
}

export async function dragOnCanvas(
  page: Page,
  from: { xMm: number; yMm: number },
  to: { xMm: number; yMm: number },
  options: {
    alt?: boolean;
    steps?: number;
  } = {},
) {
  if (options.alt) {
    await page.keyboard.down("Alt");
  }
  const start = await canvasPoint(page, from.xMm, from.yMm);
  const end = await canvasPoint(page, to.xMm, to.yMm);
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  await page.mouse.move(end.x, end.y, { steps: options.steps ?? 16 });
  await page.mouse.up();
  if (options.alt) {
    await page.keyboard.up("Alt");
  }
}

export async function readComposerProject(page: Page) {
  return page.evaluate(() => {
    const raw = window.localStorage.getItem("codegod-composer-store");
    if (!raw) {
      throw new Error("Composer store is empty.");
    }
    const payload = JSON.parse(raw) as {
      state?: {
        project?: unknown;
      };
    };
    return payload.state?.project;
  });
}

export { COMPOSER_STORAGE_KEY, COMPOSER_E2E_PROJECT, WIZARD_STORAGE_KEY, WORKBENCH_STORAGE_KEY };

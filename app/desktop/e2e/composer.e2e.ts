import { expect, test } from "@playwright/test";

import {
  COMPOSER_E2E_PROJECT,
  dragOnCanvas,
  openComposerWorkbench,
  readComposerProject,
} from "./helpers";

test.describe("Composer pointer E2E", () => {
  test.beforeEach(async ({ page }) => {
    await openComposerWorkbench(page);
  });

  test("marquee-selects multiple drawables on the canvas", async ({ page }) => {
    await dragOnCanvas(
      page,
      { xMm: 62.5, yMm: 5 },
      { xMm: 5, yMm: 120 },
    );

    const selectionTile = page.locator(".stat-tile", {
      has: page.getByText("多选对象"),
    });
    await expect(selectionTile.getByText("2")).toBeVisible();
  });

  test("drags a free asset with real pointer movement", async ({ page }) => {
    await page.getByRole("button", { name: /asset-2\.png/i }).click();

    await dragOnCanvas(
      page,
      { xMm: 64, yMm: 106 },
      { xMm: 74, yMm: 112 },
    );

    await expect
      .poll(async () => {
        const project = (await readComposerProject(page)) as typeof COMPOSER_E2E_PROJECT;
        const asset = project.panels.find((panel) => panel.id === "asset-2");
        return asset ? [asset.x_mm, asset.y_mm] : null;
      })
      .toEqual([65, 106]);
  });

  test("alt-drags to duplicate a drawable and move the duplicate", async ({ page }) => {
    await page.getByRole("button", { name: /asset-2\.png/i }).click();

    await dragOnCanvas(
      page,
      { xMm: 64, yMm: 106 },
      { xMm: 79, yMm: 106 },
      { alt: true },
    );

    await expect
      .poll(async () => {
        const project = (await readComposerProject(page)) as typeof COMPOSER_E2E_PROJECT;
        return {
          count: project.panels.length,
          original: project.panels.find((panel) => panel.id === "asset-2"),
          duplicate: project.panels.find((panel) => panel.id === "asset-3"),
        };
      })
      .toEqual({
        count: 3,
        original: expect.objectContaining({
          x_mm: 55,
          y_mm: 100,
          file_path: "/tmp/e2e-asset-2.png",
        }),
        duplicate: expect.objectContaining({
          x_mm: 70,
          y_mm: 100,
          file_path: "/tmp/e2e-asset-2.png",
        }),
      });
  });

  test("moves a free region and its bound asset together", async ({ page }) => {
    await dragOnCanvas(
      page,
      { xMm: 50, yMm: 50 },
      { xMm: 50, yMm: 105 },
    );

    await expect
      .poll(async () => {
        const project = (await readComposerProject(page)) as typeof COMPOSER_E2E_PROJECT;
        return {
          region: project.regions.find((region) => region.id === "region-1"),
          asset: project.panels.find((panel) => panel.id === "asset-1"),
        };
      })
      .toEqual({
        region: expect.objectContaining({
          col: 0,
          row: 1,
        }),
        asset: expect.objectContaining({
          x_mm: 10,
          y_mm: 75,
        }),
      });
  });
});

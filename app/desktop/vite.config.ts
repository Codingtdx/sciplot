import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  clearScreen: false,
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (
            id.includes("node_modules/konva") ||
            id.includes("node_modules/react-konva") ||
            id.includes("node_modules/use-image")
          ) {
            return "composer-vendor";
          }
          if (
            id.includes("/src/screens/Composer") ||
            id.includes("/src/components/Composer")
          ) {
            return "composer-workbench";
          }
          if (
            id.includes("/src/screens/CodeConsole") ||
            id.includes("/src/components/CodeConsole")
          ) {
            return "code-console-workbench";
          }
          if (
            id.includes("/src/screens/Tensile") ||
            id.includes("/src/screens/DataCleanup")
          ) {
            return "data-cleanup-workbench";
          }
          if (
            id.includes("/src/screens/Wizard") ||
            id.includes("/src/screens/Plot") ||
            id.includes("/src/components/Plot")
          ) {
            return "plot-workbench";
          }
          if (id.includes("node_modules")) {
            return "vendor";
          }
          return undefined;
        },
      },
    },
  },
  server: {
    port: 1420,
    strictPort: true,
  },
  envPrefix: ["VITE_", "TAURI_"],
});

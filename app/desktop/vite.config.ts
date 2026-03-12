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
            return "composer-screen";
          }
          if (id.includes("/src/screens/Wizard")) {
            return "wizard-screen";
          }
          if (
            id.includes("/src/screens/Projects") ||
            id.includes("/src/screens/Settings")
          ) {
            return "workbench-screen";
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

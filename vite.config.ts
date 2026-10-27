import path from "node:path";
import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

// Files in /public live outside Vite's module graph, so editing them doesn't
// trigger HMR on its own. This plugin watches the Lottie file and its optional
// controls sidecar explicitly and full-reloads the page on change — so an LLM
// (or you) can overwrite either and immediately see the result in the running
// dev server.
function watchLottie(): Plugin {
  const files = [
    path.resolve(__dirname, "public/lottie.json"),
    path.resolve(__dirname, "public/controls.json"),
  ];
  return {
    name: "watch-lottie",
    configureServer(server) {
      files.forEach((file) => server.watcher.add(file));
      server.watcher.on("change", (changed) => {
        if (files.includes(path.resolve(changed))) {
          server.ws.send({ type: "full-reload" });
        }
      });
    },
  };
}

export default defineConfig({
  plugins: [react(), tailwindcss(), watchLottie()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
});

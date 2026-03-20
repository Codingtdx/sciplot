import { execFile, spawn } from "node:child_process";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const desktopRoot = path.resolve(__dirname, "..");
const repoRoot = path.resolve(desktopRoot, "..", "..");
const isWindows = process.platform === "win32";
const npmCommand = isWindows ? "npm.cmd" : "npm";
const pythonCommand = isWindows
  ? path.join(repoRoot, ".venv", "Scripts", "python.exe")
  : path.join(repoRoot, ".venv", "bin", "python");
const sidecarUrl = "http://127.0.0.1:8765/health";
const frontendUrl = "http://127.0.0.1:1420/";
const tauriConfig = JSON.stringify({
  build: {
    beforeDevCommand: "true",
    devUrl: "http://127.0.0.1:1420",
  },
});

const managedProcesses = [];

function log(message) {
  console.log(`[tauri-smoke] ${message}`);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function httpOk(url) {
  try {
    const response = await fetch(url);
    return response.ok;
  } catch {
    return false;
  }
}

function summarizeLogs(handle) {
  return handle.logs.slice(-20).join("\n");
}

function spawnManaged(name, command, args, cwd) {
  const child = spawn(command, args, {
    cwd,
    env: { ...process.env, NO_COLOR: "1" },
    stdio: ["ignore", "pipe", "pipe"],
    detached: !isWindows,
  });
  const logs = [];
  let spawnError = null;
  const pushLog = (chunk, stream) => {
    const lines = chunk
      .toString()
      .split(/\r?\n/)
      .map((line) => line.trimEnd())
      .filter(Boolean);
    for (const line of lines) {
      logs.push(`[${stream}] ${line}`);
      if (logs.length > 120) {
        logs.shift();
      }
    }
  };
  child.stdout?.on("data", (chunk) => pushLog(chunk, "stdout"));
  child.stderr?.on("data", (chunk) => pushLog(chunk, "stderr"));
  child.on("error", (error) => {
    spawnError = error;
    logs.push(`[spawn-error] ${error.message}`);
  });
  const handle = { name, child, logs, get spawnError() { return spawnError; } };
  managedProcesses.push(handle);
  return handle;
}

async function stopManaged(handle) {
  if (!handle || handle.child.exitCode !== null) {
    return;
  }
  try {
    if (!isWindows && handle.child.pid) {
      process.kill(-handle.child.pid, "SIGTERM");
    } else {
      handle.child.kill("SIGTERM");
    }
  } catch {
    return;
  }
  await sleep(500);
  if (handle.child.exitCode !== null) {
    return;
  }
  try {
    if (!isWindows && handle.child.pid) {
      process.kill(-handle.child.pid, "SIGKILL");
    } else {
      handle.child.kill("SIGKILL");
    }
  } catch {
    return;
  }
}

async function cleanup() {
  while (managedProcesses.length > 0) {
    const handle = managedProcesses.pop();
    await stopManaged(handle);
  }
}

async function waitFor(description, predicate, options = {}) {
  const timeoutMs = options.timeoutMs ?? 60_000;
  const intervalMs = options.intervalMs ?? 500;
  const start = Date.now();
  let lastError = null;
  while (Date.now() - start < timeoutMs) {
    try {
      const value = await predicate();
      if (value) {
        return value;
      }
    } catch (error) {
      lastError = error;
    }
    await sleep(intervalMs);
  }
  if (lastError instanceof Error) {
    throw new Error(`${description} 超时: ${lastError.message}`);
  }
  throw new Error(`${description} 超时。`);
}

async function ensureService(name, url, factory) {
  log(`检查 ${name}...`);
  if (await httpOk(url)) {
    log(`${name} 已存在，复用当前服务。`);
    return null;
  }
  const handle = factory();
  await waitFor(`${name} 就绪`, async () => {
    if (handle.spawnError) {
      throw new Error(`${name} 启动失败: ${handle.spawnError.message}`);
    }
    if (handle.child.exitCode !== null) {
      throw new Error(`${name} 提前退出。\n${summarizeLogs(handle)}`);
    }
    return httpOk(url);
  });
  log(`${name} 已启动。`);
  return handle;
}

async function findNativeAppProcesses() {
  if (isWindows) {
    return [];
  }
  try {
    const { stdout } = await execFileAsync("pgrep", ["-fal", "sciplot-god-desktop"]);
    return stdout
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean)
      .filter(
        (line) =>
          /(?:^|\s|\/)target\/debug\/sciplot-god-desktop(?:\s|$)/.test(line) &&
          !/build_script_build|rustc|clang|cargo/.test(line),
      );
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === 1) {
      return [];
    }
    throw error;
  }
}

async function main() {
  const signals = ["SIGINT", "SIGTERM"];
  for (const signal of signals) {
    process.on(signal, async () => {
      await cleanup();
      process.exit(130);
    });
  }

  const sidecarHandle = await ensureService("Sidecar", sidecarUrl, () =>
    spawnManaged("sidecar", pythonCommand, ["-m", "app.sidecar.server"], repoRoot),
  );
  if (sidecarHandle) {
    log("Sidecar 使用仓库内 FastAPI 实例。");
  }

  const frontendHandle = await ensureService("Vite", frontendUrl, () =>
    spawnManaged("vite", npmCommand, ["run", "dev", "--", "--host", "127.0.0.1"], desktopRoot),
  );
  if (frontendHandle) {
    log("前端 dev server 使用本地 Vite 进程。");
  }

  const tauriHandle = spawnManaged(
    "tauri",
    npmCommand,
    ["run", "tauri", "--", "dev", "--no-watch", "--config", tauriConfig],
    desktopRoot,
  );
  log("等待 Tauri 原生进程启动...");

  const nativeProcesses = await waitFor("Tauri 原生窗口进程", async () => {
    if (tauriHandle.spawnError) {
      throw new Error(`Tauri 启动失败: ${tauriHandle.spawnError.message}`);
    }
    if (tauriHandle.child.exitCode !== null) {
      throw new Error(`Tauri dev 提前退出。\n${summarizeLogs(tauriHandle)}`);
    }
    const processes = await findNativeAppProcesses();
    return processes.length > 0 ? processes : null;
  }, { timeoutMs: 90_000, intervalMs: 750 });

  log("已捕获到 Tauri 原生进程，开始执行启动后检查。");
  log("Tauri 原生进程已启动。");
  for (const line of nativeProcesses) {
    log(`native: ${line}`);
  }

  if (!(await httpOk(sidecarUrl)) || !(await httpOk(frontendUrl))) {
    throw new Error("Tauri 启动后，前端或 sidecar 健康检查失败。");
  }

  log("启动后健康检查通过。");
  log("Smoke passed.");
}

try {
  await main();
} finally {
  await cleanup();
}

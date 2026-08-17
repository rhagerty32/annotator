import {
  closeMainWindow,
  getPreferenceValues,
  PopToRootType,
  showToast,
  Toast,
} from "@raycast/api";
import { spawn } from "child_process";
import { accessSync, constants } from "fs";
import { homedir } from "os";
import { join } from "path";

interface Preferences {
  annotatorPath?: string;
}

export function resolveBinary(preference?: string): string | null {
  const candidates = [
    preference?.trim(),
    join(__dirname, "../.build/release/Annotator"),
    join(__dirname, "../../.build/release/Annotator"),
    join(__dirname, "../../../.build/release/Annotator"),
    join(homedir(), "GROUND/side-projects/annotator/.build/release/Annotator"),
    "/Users/ryan/GROUND/side-projects/annotator/.build/release/Annotator",
  ].filter((p): p is string => Boolean(p));

  for (const path of candidates) {
    try {
      accessSync(path, constants.X_OK);
      return path;
    } catch {
      // try next
    }
  }
  return null;
}

export async function launchAnnotator(
  args: string[],
  options: { wait?: boolean } = {},
): Promise<number | null> {
  const result = await runAnnotator(args, options);
  return result?.code ?? null;
}

export async function runAnnotator(
  args: string[],
  options: { wait?: boolean } = {},
): Promise<{ code: number; stdout: string } | null> {
  const { annotatorPath } = getPreferenceValues<Preferences>();
  const binary = resolveBinary(annotatorPath);

  if (!binary) {
    await showToast({
      style: Toast.Style.Failure,
      title: "Annotator binary not found",
      message: "Build with `npm run build:annotator` and set the preference path.",
    });
    return null;
  }

  await closeMainWindow({
    clearRootSearch: true,
    popToRootType: PopToRootType.Immediate,
  });

  if (!options.wait) {
    const child = spawn(binary, args, {
      detached: true,
      stdio: "ignore",
    });
    child.unref();
    return null;
  }

  return new Promise((resolve, reject) => {
    const child = spawn(binary, args, { stdio: ["ignore", "pipe", "ignore"] });
    let stdout = "";
    child.stdout.on("data", (chunk: Buffer) => {
      stdout += chunk.toString("utf8");
    });
    child.on("error", reject);
    child.on("close", (code) => resolve({ code: code ?? 1, stdout }));
  });
}

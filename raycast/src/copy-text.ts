import { showToast, Toast } from "@raycast/api";
import { spawn } from "child_process";
import { writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { runAnnotator } from "./launch";

export default async function Command() {
  const result = await runAnnotator(["--ocr"], { wait: true });
  if (result === null) return;

  if (result.code === 0) {
    if (result.stdout.length > 0) {
      copyAfterCommand(result.stdout);
    }
    return;
  }
  if (result.code === 2) {
    await showToast({ style: Toast.Style.Failure, title: "No text found" });
    return;
  }
  await showToast({ style: Toast.Style.Failure, title: "Cancelled" });
}

function copyAfterCommand(text: string) {
  const file = join(tmpdir(), `annotator-ocr-${process.pid}-${Date.now()}.txt`);
  writeFileSync(file, text, "utf8");
  const child = spawn(
    "/bin/bash",
    ["-c", 'sleep 0.45 && /usr/bin/pbcopy < "$1" && rm -f "$1"', "annotator-ocr", file],
    { detached: true, stdio: "ignore" },
  );
  child.unref();
}

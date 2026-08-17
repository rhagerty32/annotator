import { launchAnnotator } from "./launch";

export default async function Command() {
  await launchAnnotator(["--capture", "--window"]);
}

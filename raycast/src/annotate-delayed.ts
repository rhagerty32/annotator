import { launchFastCapture } from "./launch";

export default async function Command() {
  await launchFastCapture({ delay: 3 });
}

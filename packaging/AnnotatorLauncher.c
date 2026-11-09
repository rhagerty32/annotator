/*
 * Finder launcher for Annotator.app.
 *
 * A double-click (and the Finder -psn_ argument) execs AnnotatorBin with no
 * extra flags so the menu bar agent stays resident. Any other argument is
 * forwarded unchanged, which keeps Raycast commands and the CLI working.
 */
#include <libgen.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
  char exe[4096];
  uint32_t size = (uint32_t)sizeof(exe);

  if (_NSGetExecutablePath(exe, &size) != 0) {
    fputs("Annotator: could not locate itself\n", stderr);
    return 1;
  }

  char *dir = dirname(exe);
  char bin[4096];
  int wrote = snprintf(bin, sizeof(bin), "%s/AnnotatorBin", dir);
  if (wrote < 0 || wrote >= (int)sizeof(bin)) {
    return 1;
  }

  char **args = calloc((size_t)argc + 1, sizeof(char *));
  if (args == NULL) {
    return 1;
  }
  args[0] = bin;
  int out = 1;
  for (int i = 1; i < argc; i++) {
    if (strncmp(argv[i], "-psn_", 5) == 0) {
      continue;
    }
    args[out++] = argv[i];
  }
  args[out] = NULL;

  execv(bin, args);
  perror("Annotator");
  return 1;
}

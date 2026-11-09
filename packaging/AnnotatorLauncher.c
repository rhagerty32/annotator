/*
 * Finder launcher for Annotator.app.
 *
 * Double-click and the Finder -psn_ argument both exec AnnotatorBin with
 * --capture. Any other argument is forwarded and --capture is left off, so
 * the Raycast commands and the CLI keep working.
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

  int add_capture = 1;
  if (argc >= 2) {
    int other = 0;
    for (int i = 1; i < argc; i++) {
      if (strncmp(argv[i], "-psn_", 5) != 0) {
        other++;
      }
    }
    add_capture = (other == 0);
  }

  char **args = calloc((size_t)argc + 3, sizeof(char *));
  if (args == NULL) {
    return 1;
  }
  args[0] = bin;
  int out = 1;
  if (add_capture) {
    args[1] = "--capture";
    out = 2;
  } else {
    for (int i = 1; i < argc; i++) {
      if (strncmp(argv[i], "-psn_", 5) != 0) {
        args[out++] = argv[i];
      }
    }
  }
  args[out] = NULL;

  execv(bin, args);
  perror("Annotator");
  return 1;
}

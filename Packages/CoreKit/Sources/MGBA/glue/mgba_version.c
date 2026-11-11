// Replaces mGBA's CMake-generated src/core/version.c (from version.c.in, MPL-2.0), which we
// don't generate because we never run mGBA's build system. Values describe the vendored snapshot.
#include <mgba/core/version.h>

MGBA_EXPORT const char* const gitCommit = "662dada";
MGBA_EXPORT const char* const gitCommitShort = "662dada";
MGBA_EXPORT const char* const gitBranch = "master";
MGBA_EXPORT const int gitRevision = -1;
MGBA_EXPORT const char* const binaryName = "mgba";
MGBA_EXPORT const char* const projectName = "mGBA";
MGBA_EXPORT const char* const projectVersion = "0.11-dev (662dada, vendored)";

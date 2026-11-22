#include "fpzip.h"

// DrawThingsClient: per thread (see fpzip.h).
thread_local fpzipError fpzip_errno;

const char* const fpzip_errstr[] = {
  "success",
  "cannot read stream",
  "cannot write stream",
  "not an fpzip stream",
  "fpzip format version not supported",
  "precision not supported",
  "memory buffer overflow",
  "internal error",
};

#pragma once
/*
    Windows (MinGW-w64) build only. Force-included into every translation unit
    of the kit and of anything linking it (target_compile_options -include in
    CMakeLists.txt), so shared POSIX-flavoured code compiles unchanged and the
    Linux sources need no #ifdef.

    Rules for this file: C-safe, no <windows.h> (its macros would leak into
    every TU), and only what MinGW really lacks. Each stub fails the way the
    real call fails on an unsupported system (-1 + errno), so callers take
    their existing error path. Add a line here when shared code starts using a
    new POSIX call and the Windows CI job reports it as undeclared.
*/

#ifdef _WIN32

#include <errno.h>
#include <fcntl.h>
#include <io.h>
#include <signal.h>
#include <unistd.h>

/* No fork/exec on Windows, so nothing can inherit a descriptor across exec.
   _O_NOINHERIT is the nearest meaning; _O_BINARY because a POSIX open() never
   translates newlines and the MSVCRT default (text mode) does. */
#ifndef O_CLOEXEC
#define O_CLOEXEC (_O_NOINHERIT | _O_BINARY)
#endif

#ifndef F_DUPFD_CLOEXEC
#define F_DUPFD_CLOEXEC 1030
#endif

#ifndef SIGSTOP
#define SIGSTOP 19
#endif

/* _commit flushes the CRT descriptor's OS buffers to disk, which is what
   fsync promises. */
static inline int fsync(int fd)
{
    return _commit(fd);
}

static inline int fcntl(int fd, int cmd, ...)
{
    (void)fd;
    (void)cmd;
    errno = ENOSYS;
    return -1;
}

static inline int mkfifo(const char *path, int mode)
{
    (void)path;
    (void)mode;
    errno = ENOSYS;
    return -1;
}

static inline int kill(int pid, int sig)
{
    (void)pid;
    (void)sig;
    errno = ENOSYS;
    return -1;
}

#endif /* _WIN32 */

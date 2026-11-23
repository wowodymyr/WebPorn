// crashprobe.dylib: DYLD_INSERT_LIBRARIES helper for devices without a debugger.
// On SIGSEGV/SIGBUS/SIGTRAP/SIGILL/SIGABRT prints the fault address, registers
// and a frame-pointer backtrace (symbolized with dladdr) to stderr, then exits.
//   clang -target armv7-apple-ios8.0 -isysroot <sdk> -dynamiclib crashprobe.c -o crashprobe.dylib

#include <dlfcn.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ucontext.h>
#include <unistd.h>

static void describe(const char* what, uintptr_t address)
{
    Dl_info info;
    if (address && dladdr((void*)address, &info) && info.dli_fname) {
        const char* image = info.dli_fname;
        for (const char* p = image; *p; ++p)
            if (*p == '/')
                image = p + 1;
        fprintf(stderr, "  %-4s %#010lx %s+%#lx", what, (unsigned long)address, image,
            (unsigned long)(address - (uintptr_t)info.dli_fbase));
        if (info.dli_sname)
            fprintf(stderr, " (%s+%#lx)", info.dli_sname, (unsigned long)(address - (uintptr_t)info.dli_saddr));
        fputc('\n', stderr);
    } else
        fprintf(stderr, "  %-4s %#010lx\n", what, (unsigned long)address);
}

static void handler(int sig, siginfo_t* si, void* context)
{
    ucontext_t* uc = context;
    fprintf(stderr, "\n=== crashprobe: signal %d code %d fault address %p\n", sig, si->si_code, si->si_addr);
#if defined(__arm__)
    _STRUCT_ARM_THREAD_STATE* s = &uc->uc_mcontext->__ss;
    for (int i = 0; i < 13; ++i)
        fprintf(stderr, "  r%-2d %#010x%s", i, s->__r[i], i % 4 == 3 ? "\n" : "");
    fprintf(stderr, "\n  sp  %#010x  cpsr %#010x\n", s->__sp, s->__cpsr);
    describe("pc", s->__pc);
    describe("lr", s->__lr);
    uintptr_t fp = s->__r[7];
#elif defined(__arm64__)
    _STRUCT_ARM_THREAD_STATE64* s = &uc->uc_mcontext->__ss;
    for (int i = 0; i < 29; ++i)
        fprintf(stderr, "  x%-2d %#018llx%s", i, s->__x[i], i % 3 == 2 ? "\n" : "");
    fprintf(stderr, "\n  sp  %#018llx\n", s->__sp);
    describe("pc", s->__pc);
    describe("lr", s->__lr);
    uintptr_t fp = s->__fp;
#endif
    for (int depth = 0; fp && !(fp & (sizeof(void*) - 1)) && depth < 64; ++depth) {
        uintptr_t* frame = (uintptr_t*)fp;
        describe("ret", frame[1]);
        if (frame[0] <= fp)
            break;
        fp = frame[0];
    }
    _exit(128 + sig);
}

__attribute__((constructor)) static void install(void)
{
    static char stack[64 * 1024];
    stack_t ss = { .ss_sp = stack, .ss_size = sizeof(stack), .ss_flags = 0 };
    sigaltstack(&ss, NULL);
    struct sigaction sa = { 0 };
    sa.sa_sigaction = handler;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    int signals[] = { SIGSEGV, SIGBUS, SIGTRAP, SIGILL, SIGABRT };
    for (unsigned i = 0; i < sizeof(signals) / sizeof(*signals); ++i)
        sigaction(signals[i], &sa, NULL);
}

// dlopen each image given on the command line with RTLD_NOW, so every symbol
// is bound up front, and report what failed. Static initializers run here too.
//   dlopen-test /var/webporn/lib/WebKitLegacy.framework/WebKitLegacy ...
#include <dlfcn.h>
#include <stdio.h>

int main(int argc, char** argv)
{
    int failures = 0;
    for (int i = 1; i < argc; i++) {
        void* handle = dlopen(argv[i], RTLD_NOW | RTLD_GLOBAL);
        printf("%s: %s\n", argv[i], handle ? "ok" : dlerror());
        failures += !handle;
    }
    return failures;
}

// Print every selector implemented by any class or metaclass in the process, one
// per line, after dlopen()ing the images given as arguments (classes are only
// registered once their image is loaded). Ground truth for
// toolchain/objc-selector-audit.py:
//   objc-methods /System/Library/Frameworks/UIKit.framework/UIKit ... > selectors.txt
#include <dlfcn.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>

static void printMethods(Class cls)
{
    unsigned count = 0;
    Method* methods = class_copyMethodList(cls, &count);
    for (unsigned i = 0; i < count; i++)
        puts(sel_getName(method_getName(methods[i])));
    free(methods);
}

int main(int argc, char** argv)
{
    for (int i = 1; i < argc; i++) {
        if (!dlopen(argv[i], RTLD_LAZY | RTLD_GLOBAL))
            fprintf(stderr, "dlopen %s: %s\n", argv[i], dlerror());
    }
    unsigned count = 0;
    Class* classes = objc_copyClassList(&count);
    for (unsigned i = 0; i < count; i++) {
        printMethods(classes[i]);
        printMethods(object_getClass((id)classes[i]));
    }
    fprintf(stderr, "%u classes\n", count);
    free(classes);
    return 0;
}

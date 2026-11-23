// ExcLog: write ObjC exceptions (name, reason, call stack) of the filtered
// processes to /var/mobile/Media/webporn/exc-<process>.log; iOS 8 crash reports
// leave the reason out. Every throw is logged, caught or not ("thrown"): one that
// unwinds through WebCore's -fno-exceptions frames hangs instead of crashing.
#import <Foundation/Foundation.h>
#include <objc/objc-exception.h>

static NSUncaughtExceptionHandler* previousHandler;

static void appendLog(NSString* text)
{
    NSString* path = [NSString stringWithFormat:@"/var/mobile/Media/webporn/exc-%@.log", [[NSProcessInfo processInfo] processName]];
    NSFileHandle* file = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!file) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        file = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    [file seekToEndOfFile];
    [file writeData:[text dataUsingEncoding:NSUTF8StringEncoding]];
    [file closeFile];
}

static objc_exception_preprocessor previousPreprocessor;

static id logThrow(id object)
{
    @autoreleasepool {
        NSException* exception = object;
        NSString* description = [object isKindOfClass:[NSException class]] ? [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason] : [object description];
        appendLog([NSString stringWithFormat:@"%@ thrown on %@\n%@\n%@\n\n", [NSDate date], [NSThread isMainThread] ? @"main" : [NSThread currentThread].name ?: @"thread",
            description, [[NSThread callStackSymbols] componentsJoinedByString:@"\n"]]);
    }
    return previousPreprocessor ? previousPreprocessor(object) : object;
}

static void logException(NSException* exception)
{
    appendLog([NSString stringWithFormat:@"%@ uncaught\n%@: %@\n%@\n\n", [NSDate date], exception.name, exception.reason,
        [exception.callStackSymbols componentsJoinedByString:@"\n"]]);
    if (previousHandler)
        previousHandler(exception);
}

__attribute__((constructor)) static void excLogInit(void)
{
    previousHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(logException);
    previousPreprocessor = objc_setExceptionPreprocessor(logThrow);
}

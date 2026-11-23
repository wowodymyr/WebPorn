/* WebPorn overlay: macOS-only header, missing from iOS SDKs (same declaration as macOS). */
#pragma once
#include <objc/runtime.h>
#ifdef __OBJC__
#include <objc/NSObject.h>
@interface Protocol : NSObject
@end
#endif

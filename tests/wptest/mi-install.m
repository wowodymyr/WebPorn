// Install an .ipa as a user (container) app the way iTunes does, through
// LSApplicationWorkspace (iOS 8 dropped MobileInstallationInstall); AppSync
// Unified on the device accepts the unsigned bundle.
//   mi-install <path.ipa> <bundle-id>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@interface NSObject (LSApplicationWorkspace)
+ (id)defaultWorkspace;
- (BOOL)installApplication:(NSURL*)path withOptions:(NSDictionary*)options error:(NSError**)error;
@end

int main(int argc, char** argv)
{
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "usage: %s <path.ipa> <bundle-id>\n", argv[0]);
            return 2;
        }
        id workspace = [objc_getClass("LSApplicationWorkspace") defaultWorkspace];
        NSError* error = nil;
        BOOL installed = [workspace installApplication:[NSURL fileURLWithPath:@(argv[1])]
            withOptions:@{ @"CFBundleIdentifier": @(argv[2]), @"PackageType": @"Customer" } error:&error];
        printf("result %s %s\n", installed ? "installed" : "failed", error ? error.description.UTF8String : "");
        return installed ? 0 : 1;
    }
}

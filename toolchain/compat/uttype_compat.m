// UniformTypeIdentifiers (iOS 14) for iOS 8-10: the UTType class, the UTType*
// constants and the UTTagClass* keys WebCore uses, backed by the MobileCoreServices
// UTType C functions those iOS versions have. Linked hidden into WebCore.
// Built with -fobjc-arc against an SDK without UniformTypeIdentifiers (9.3).

#import <Foundation/Foundation.h>
#import <MobileCoreServices/MobileCoreServices.h>

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED < 140000

__attribute__((visibility("default")))
@interface UTType : NSObject <NSCopying>
@property (readonly) NSString *identifier;
@end

NSString *const UTTagClassFilenameExtension = @"public.filename-extension";
NSString *const UTTagClassMIMEType = @"public.mime-type";

@implementation UTType {
    NSString *_identifier;
}

- (instancetype)initWithIdentifier:(NSString *)identifier
{
    if (!(self = [super init]))
        return nil;
    _identifier = [identifier copy];
    return self;
}

+ (instancetype)typeWithIdentifier:(NSString *)identifier
{
    return identifier.length ? [[self alloc] initWithIdentifier:identifier] : nil;
}

+ (instancetype)typeWithTag:(NSString *)tag tagClass:(NSString *)tagClass conformingToType:(UTType *)supertype
{
    if (!tag || !tagClass)
        return nil;
    NSString *identifier = CFBridgingRelease(UTTypeCreatePreferredIdentifierForTag((__bridge CFStringRef)tagClass,
        (__bridge CFStringRef)tag, (__bridge CFStringRef)supertype.identifier));
    return [self typeWithIdentifier:identifier];
}

+ (instancetype)typeWithFilenameExtension:(NSString *)extension
{
    return [self typeWithTag:extension tagClass:UTTagClassFilenameExtension conformingToType:nil];
}

+ (instancetype)typeWithFilenameExtension:(NSString *)extension conformingToType:(UTType *)supertype
{
    return [self typeWithTag:extension tagClass:UTTagClassFilenameExtension conformingToType:supertype];
}

+ (instancetype)typeWithMIMEType:(NSString *)mimeType
{
    return [self typeWithTag:mimeType tagClass:UTTagClassMIMEType conformingToType:nil];
}

+ (instancetype)typeWithMIMEType:(NSString *)mimeType conformingToType:(UTType *)supertype
{
    return [self typeWithTag:mimeType tagClass:UTTagClassMIMEType conformingToType:supertype];
}

- (NSString *)identifier
{
    return _identifier;
}

- (NSString *)preferredFilenameExtension
{
    return CFBridgingRelease(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)_identifier, kUTTagClassFilenameExtension));
}

- (NSString *)preferredMIMEType
{
    return CFBridgingRelease(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)_identifier, kUTTagClassMIMEType));
}

- (NSString *)localizedDescription
{
    return CFBridgingRelease(UTTypeCopyDescription((__bridge CFStringRef)_identifier));
}

- (NSDictionary<NSString *, NSArray<NSString *> *> *)tags
{
    NSMutableDictionary *tags = [NSMutableDictionary dictionary];
    for (NSString *tagClass in @[ UTTagClassFilenameExtension, UTTagClassMIMEType ]) {
        NSArray *values = CFBridgingRelease(UTTypeCopyAllTagsWithClass((__bridge CFStringRef)_identifier, (__bridge CFStringRef)tagClass));
        if (values.count)
            tags[tagClass] = values;
    }
    return tags;
}

- (BOOL)conformsToType:(UTType *)type
{
    return type && UTTypeConformsTo((__bridge CFStringRef)_identifier, (__bridge CFStringRef)type.identifier);
}

- (BOOL)isSupertypeOfType:(UTType *)type
{
    return [type conformsToType:self];
}

- (BOOL)isSubtypeOfType:(UTType *)type
{
    return ![self isEqual:type] && [self conformsToType:type];
}

- (BOOL)isDynamic
{
    return UTTypeIsDynamic((__bridge CFStringRef)_identifier);
}

- (BOOL)isDeclared
{
    return UTTypeIsDeclared((__bridge CFStringRef)_identifier);
}

- (BOOL)isPublicType
{
    return [_identifier hasPrefix:@"public."];
}

- (NSOrderedSet<UTType *> *)_parentTypes
{
    NSDictionary *declaration = CFBridgingRelease(UTTypeCopyDeclaration((__bridge CFStringRef)_identifier));
    id conformsTo = declaration[(__bridge NSString *)kUTTypeConformsToKey];
    if ([conformsTo isKindOfClass:[NSString class]])
        conformsTo = @[ conformsTo ];
    NSMutableOrderedSet *parents = [NSMutableOrderedSet orderedSet];
    for (NSString *identifier in conformsTo)
        [parents addObject:[UTType typeWithIdentifier:identifier]];
    return parents;
}

- (NSSet<UTType *> *)supertypes
{
    NSMutableSet *result = [NSMutableSet set];
    NSMutableArray *pending = [[[self _parentTypes] array] mutableCopy];
    while (pending.count) {
        UTType *type = pending.lastObject;
        [pending removeLastObject];
        if ([result containsObject:type])
            continue;
        [result addObject:type];
        [pending addObjectsFromArray:[[type _parentTypes] array]];
    }
    return result;
}

// The old API cannot enumerate the type database; offer the types WebCore names.
+ (void)_enumerateAllDeclaredTypesUsingBlock:(void (__attribute__((noescape)) ^)(UTType *type, BOOL *stop))block
{
    extern NSArray<UTType *> *wpKnownTypes(void);
    BOOL stop = NO;
    for (UTType *type in wpKnownTypes()) {
        block(type, &stop);
        if (stop)
            break;
    }
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (BOOL)isEqual:(id)object
{
    return [object isKindOfClass:[UTType class]] && UTTypeEqual((__bridge CFStringRef)_identifier, (__bridge CFStringRef)((UTType *)object)->_identifier);
}

- (NSUInteger)hash
{
    return _identifier.lowercaseString.hash;
}

- (NSString *)description
{
    return _identifier;
}

@end

#define WP_UTTYPES(M) \
    M(CalendarEvent, "public.calendar-event") \
    M(Content, "public.content") \
    M(Data, "public.data") \
    M(Directory, "public.directory") \
    M(FileURL, "public.file-url") \
    M(FlatRTFD, "com.apple.flat-rtfd") \
    M(Folder, "public.folder") \
    M(GIF, "com.compuserve.gif") \
    M(HTML, "public.html") \
    M(Item, "public.item") \
    M(JPEG, "public.jpeg") \
    M(Package, "com.apple.package") \
    M(PDF, "com.adobe.pdf") \
    M(PlainText, "public.plain-text") \
    M(PNG, "public.png") \
    M(RTF, "public.rtf") \
    M(RTFD, "com.apple.rtfd") \
    M(Text, "public.text") \
    M(TIFF, "public.tiff") \
    M(URL, "public.url") \
    M(UTF16PlainText, "public.utf16-plain-text") \
    M(UTF8PlainText, "public.utf8-plain-text") \
    M(VCard, "public.vcard") \
    M(WebArchive, "com.apple.webarchive") \
    M(ZIP, "public.zip-archive")

#define WP_DEFINE_UTTYPE(name, identifier) __attribute__((visibility("default"))) UTType *UTType##name;
WP_UTTYPES(WP_DEFINE_UTTYPE)

__attribute__((constructor)) static void wpInitializeUTTypes(void)
{
#define WP_INIT_UTTYPE(name, identifier) UTType##name = [UTType typeWithIdentifier:@identifier];
    WP_UTTYPES(WP_INIT_UTTYPE)
}

NSArray<UTType *> *wpKnownTypes(void)
{
#define WP_LIST_UTTYPE(name, identifier) UTType##name,
    return @[ WP_UTTYPES(WP_LIST_UTTYPE) ];
}

#endif

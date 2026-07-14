#import "VSDraftStore.h"

@implementation VSDraftStore

+ (NSString *)directory {
    NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSString *directory = [documents stringByAppendingPathComponent:@"VibeSlopikDrafts"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return directory;
}

+ (NSString *)safeName:(NSString *)threadId {
    NSCharacterSet *unsafe = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    NSString *name = [[threadId componentsSeparatedByCharactersInSet:unsafe] componentsJoinedByString:@"_"];
    return [name length] ? name : @"unknown";
}

+ (NSString *)pathForThread:(NSString *)threadId {
    return [[self directory] stringByAppendingPathComponent:[[self safeName:threadId] stringByAppendingPathExtension:@"plist"]];
}

+ (NSDictionary *)draftForThread:(NSString *)threadId {
    NSDictionary *draft = [NSDictionary dictionaryWithContentsOfFile:[self pathForThread:threadId]];
    return [draft isKindOfClass:[NSDictionary class]] ? draft : nil;
}

+ (void)saveDraftForThread:(NSString *)threadId text:(NSString *)text images:(NSArray *)images {
    [self saveDraftForThread:threadId text:text images:images requestId:nil];
}

+ (void)saveDraftForThread:(NSString *)threadId text:(NSString *)text images:(NSArray *)images requestId:(NSString *)requestId {
    if (![threadId length]) return;
    if (![text length] && ![images count]) { [self removeDraftForThread:threadId]; return; }
    NSArray *safeImages = [images count] > 4 ? [images subarrayWithRange:NSMakeRange(0, 4)] : images;
    NSMutableDictionary *draft = [NSMutableDictionary dictionaryWithObjectsAndKeys:text ?: @"", @"text", safeImages ?: [NSArray array], @"images", [NSDate date], @"updatedAt", nil];
    if ([requestId length]) [draft setObject:requestId forKey:@"requestId"];
    [draft writeToFile:[self pathForThread:threadId] atomically:YES];
    [self enforceLimit];
}

+ (void)removeDraftForThread:(NSString *)threadId {
    if ([threadId length]) [[NSFileManager defaultManager] removeItemAtPath:[self pathForThread:threadId] error:nil];
}

+ (NSArray *)draftFiles {
    NSString *directory = [self directory];
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil] ?: [NSArray array];
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *name in names) {
        NSString *path = [directory stringByAppendingPathComponent:name];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        if (attributes) [files addObject:[NSDictionary dictionaryWithObjectsAndKeys:path, @"path", [attributes objectForKey:NSFileSize] ?: @0, @"size", [attributes objectForKey:NSFileModificationDate] ?: [NSDate distantPast], @"date", nil]];
    }
    return files;
}

+ (void)enforceLimit {
    NSMutableArray *files = [NSMutableArray arrayWithArray:[self draftFiles]];
    [files sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) { return [[left objectForKey:@"date"] compare:[right objectForKey:@"date"]]; }];
    unsigned long long total = 0; for (NSDictionary *file in files) total += [[file objectForKey:@"size"] unsignedLongLongValue];
    const unsigned long long limit = 50ULL * 1024ULL * 1024ULL;
    for (NSDictionary *file in files) { if (total <= limit) break; unsigned long long size = [[file objectForKey:@"size"] unsignedLongLongValue]; [[NSFileManager defaultManager] removeItemAtPath:[file objectForKey:@"path"] error:nil]; total = total > size ? total - size : 0; }
}

+ (NSDictionary *)statistics {
    NSArray *files = [self draftFiles]; unsigned long long bytes = 0; NSUInteger images = 0;
    for (NSDictionary *file in files) { bytes += [[file objectForKey:@"size"] unsignedLongLongValue]; NSDictionary *draft = [NSDictionary dictionaryWithContentsOfFile:[file objectForKey:@"path"]]; images += [[draft objectForKey:@"images"] count]; }
    return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInteger:[files count]], @"count", [NSNumber numberWithUnsignedLongLong:bytes], @"bytes", [NSNumber numberWithUnsignedInteger:images], @"images", nil];
}

+ (void)clearAll {
    for (NSDictionary *file in [self draftFiles]) [[NSFileManager defaultManager] removeItemAtPath:[file objectForKey:@"path"] error:nil];
}

@end

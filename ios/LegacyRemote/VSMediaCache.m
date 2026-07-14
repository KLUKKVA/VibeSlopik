#import "VSMediaCache.h"

@implementation VSMediaCache
+ (NSString *)directory {
    NSString *root = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *path = [root stringByAppendingPathComponent:@"VibeSlopikMedia"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}
+ (BOOL)autoDownload { NSUserDefaults *d = [NSUserDefaults standardUserDefaults]; return [d objectForKey:@"VSMediaAutoDownload"] ? [d boolForKey:@"VSMediaAutoDownload"] : YES; }
+ (void)setAutoDownload:(BOOL)value { [[NSUserDefaults standardUserDefaults] setBool:value forKey:@"VSMediaAutoDownload"]; [[NSUserDefaults standardUserDefaults] synchronize]; }
+ (NSString *)pathForKey:(NSString *)key { NSString *safe = [[key componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"_"]; return [[self directory] stringByAppendingPathComponent:safe]; }
+ (NSData *)dataForKey:(NSString *)key { NSString *path = [self pathForKey:key]; NSData *data = [NSData dataWithContentsOfFile:path]; if (data) [[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObject:[NSDate date] forKey:NSFileModificationDate] ofItemAtPath:path error:nil]; return data; }
+ (void)storeData:(NSData *)data forKey:(NSString *)key {
    if (![data length] || ![key length]) return; NSString *path = [self pathForKey:key]; NSString *temporary = [path stringByAppendingString:@".tmp"];
    if ([data writeToFile:temporary atomically:YES]) { [[NSFileManager defaultManager] removeItemAtPath:path error:nil]; [[NSFileManager defaultManager] moveItemAtPath:temporary toPath:path error:nil]; }
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self directory] error:nil]; NSMutableArray *files = [NSMutableArray array]; unsigned long long total = 0;
    for (NSString *name in names) { NSString *item = [[self directory] stringByAppendingPathComponent:name]; NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:item error:nil]; if (!attributes) continue; total += [attributes fileSize]; [files addObject:[NSDictionary dictionaryWithObjectsAndKeys:item, @"path", [attributes fileModificationDate], @"date", [NSNumber numberWithUnsignedLongLong:[attributes fileSize]], @"size", nil]]; }
    [files sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [[a objectForKey:@"date"] compare:[b objectForKey:@"date"]]; }];
    const unsigned long long limit = 50ULL * 1024ULL * 1024ULL; for (NSDictionary *item in files) { if (total <= limit) break; [[NSFileManager defaultManager] removeItemAtPath:[item objectForKey:@"path"] error:nil]; total -= [[item objectForKey:@"size"] unsignedLongLongValue]; }
}
+ (NSDictionary *)statistics { NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self directory] error:nil]; unsigned long long bytes = 0; for (NSString *name in names) bytes += [[[NSFileManager defaultManager] attributesOfItemAtPath:[[self directory] stringByAppendingPathComponent:name] error:nil] fileSize]; return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInteger:[names count]], @"count", [NSNumber numberWithUnsignedLongLong:bytes], @"bytes", nil]; }
+ (void)clear { [[NSFileManager defaultManager] removeItemAtPath:[self directory] error:nil]; [self directory]; }
+ (NSData *)decodeBase64:(NSString *)value {
    if (![value length]) return nil; static const signed char table[256] = {
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,62,-1,-1,-1,63,52,53,54,55,56,57,58,59,60,61,-1,-1,-1,-2,-1,-1,
        -1,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,-1,-1,-1,-1,-1,
        -1,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,-1,-1,-1,-1,-1
    };
    NSMutableData *result = [NSMutableData dataWithCapacity:[value length] * 3 / 4]; int accumulator = 0, bits = 0; const char *characters = [value UTF8String];
    for (NSUInteger i = 0; characters[i]; i++) { unsigned char c = characters[i]; if (c >= 128) continue; int decoded = table[c]; if (decoded == -2) break; if (decoded < 0) continue; accumulator = (accumulator << 6) | decoded; bits += 6; if (bits >= 8) { bits -= 8; unsigned char byte = (accumulator >> bits) & 255; [result appendBytes:&byte length:1]; } }
    return result;
}
@end

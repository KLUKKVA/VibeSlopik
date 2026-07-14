#import <Foundation/Foundation.h>

@interface VSMediaCache : NSObject
+ (BOOL)autoDownload;
+ (void)setAutoDownload:(BOOL)value;
+ (NSData *)dataForKey:(NSString *)key;
+ (void)storeData:(NSData *)data forKey:(NSString *)key;
+ (NSDictionary *)statistics;
+ (void)clear;
+ (NSData *)decodeBase64:(NSString *)value;
@end

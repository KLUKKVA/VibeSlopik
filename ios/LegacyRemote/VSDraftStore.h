#import <Foundation/Foundation.h>

@interface VSDraftStore : NSObject
+ (NSDictionary *)draftForThread:(NSString *)threadId;
+ (void)saveDraftForThread:(NSString *)threadId text:(NSString *)text images:(NSArray *)images;
+ (void)saveDraftForThread:(NSString *)threadId text:(NSString *)text images:(NSArray *)images requestId:(NSString *)requestId;
+ (void)removeDraftForThread:(NSString *)threadId;
+ (NSDictionary *)statistics;
+ (void)clearAll;
@end

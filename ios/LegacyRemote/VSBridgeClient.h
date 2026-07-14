#import <Foundation/Foundation.h>

typedef void (^VSBridgeCompletion)(NSDictionary *response, NSError *error);

@interface VSBridgeClient : NSObject

@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, copy) NSString *token;

+ (VSBridgeClient *)sharedClient;
- (void)getPath:(NSString *)path completion:(VSBridgeCompletion)completion;
- (void)postPath:(NSString *)path body:(NSDictionary *)body completion:(VSBridgeCompletion)completion;

@end

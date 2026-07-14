#import "VSBridgeClient.h"
#import "VSLocalization.h"

@implementation VSBridgeClient

- (NSString *)localizedBridgeError:(NSString *)message {
    if (!message) return VSL(@"\u041d\u0435\u0438\u0437\u0432\u0435\u0441\u0442\u043d\u0430\u044f \u043e\u0448\u0438\u0431\u043a\u0430", @"Unknown error");
    NSString *lower = [message lowercaseString];
    if ([lower rangeOfString:@"timed out"].location != NSNotFound) return VSL(@"\u0412\u0440\u0435\u043c\u044f \u043e\u0436\u0438\u0434\u0430\u043d\u0438\u044f \u0438\u0441\u0442\u0435\u043a\u043b\u043e. \u041f\u0440\u043e\u0432\u0435\u0440\u044c\u0442\u0435 Host \u043d\u0430 \u041f\u041a.", @"The request timed out. Check Host on your computer.");
    if ([lower rangeOfString:@"host is offline"].location != NSNotFound) return VSL(@"\u041a\u043e\u043c\u043f\u044c\u044e\u0442\u0435\u0440 \u043d\u0435 \u043d\u0430 \u0441\u0432\u044f\u0437\u0438. \u0417\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u0435 Host.", @"Computer is offline. Start Host.");
    if ([lower rangeOfString:@"unauthorized"].location != NSNotFound) return VSL(@"\u041d\u0435\u0432\u0435\u0440\u043d\u044b\u0439 \u0442\u043e\u043a\u0435\u043d.", @"Invalid token.");
    if ([lower rangeOfString:@"not found"].location != NSNotFound) return VSL(@"\u0410\u0434\u0440\u0435\u0441 \u0438\u043b\u0438 \u0441\u0435\u0441\u0441\u0438\u044f \u043d\u0435 \u043d\u0430\u0439\u0434\u0435\u043d\u044b.", @"Address or session was not found.");
    return message;
}

+ (VSBridgeClient *)sharedClient {
    static VSBridgeClient *client = nil;
    if (!client) {
        client = [[VSBridgeClient alloc] init];
        client.baseURL = [[NSUserDefaults standardUserDefaults] stringForKey:@"BridgeURL"];
        client.token = [[NSUserDefaults standardUserDefaults] stringForKey:@"BridgeToken"];
    }
    return client;
}

- (void)getPath:(NSString *)path completion:(VSBridgeCompletion)completion {
    [self requestWithMethod:@"GET" path:path body:nil completion:completion];
}

- (void)postPath:(NSString *)path body:(NSDictionary *)body completion:(VSBridgeCompletion)completion {
    [self requestWithMethod:@"POST" path:path body:body completion:completion];
}

- (void)requestWithMethod:(NSString *)method path:(NSString *)path body:(NSDictionary *)body completion:(VSBridgeCompletion)completion {
    if (!self.baseURL || [self.baseURL length] == 0) {
        NSError *error = [NSError errorWithDomain:@"VibeSlopik" code:1 userInfo:[NSDictionary dictionaryWithObject:VSL(@"URL Relay не настроен", @"Relay URL is not configured") forKey:NSLocalizedDescriptionKey]];
        completion(nil, error);
        return;
    }

    NSString *base = [self.baseURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([base hasSuffix:@"/"]) {
        base = [base substringToIndex:[base length] - 1];
    }

    NSString *urlText = [base stringByAppendingString:path];
    NSURL *url = [NSURL URLWithString:urlText];
    if (!url) {
        NSError *error = [NSError errorWithDomain:@"VibeSlopik" code:2 userInfo:[NSDictionary dictionaryWithObject:VSL(@"Некорректный URL Relay", @"Relay URL is invalid") forKey:NSLocalizedDescriptionKey]];
        completion(nil, error);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:method];
    [request setValue:@"application/json" forHTTPHeaderField:@"accept"];
    // A first transcription may download a model. Normal bridge calls must
    // fail promptly so the UI can offer retry instead of hanging for minutes.
    [request setTimeoutInterval:[path isEqual:@"/api/speech/transcriptions"] ? 300.0 : 45.0];

    if (self.token && [self.token length] > 0) {
        [request setValue:[@"Bearer " stringByAppendingString:self.token] forHTTPHeaderField:@"authorization"];
    }

    if (body) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        [request setHTTPBody:data];
        [request setValue:@"application/json" forHTTPHeaderField:@"content-type"];
    }

    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        if (error) {
            NSError *localized = [NSError errorWithDomain:@"VibeSlopik" code:[error code] userInfo:[NSDictionary dictionaryWithObject:[self localizedBridgeError:[error localizedDescription]] forKey:NSLocalizedDescriptionKey]];
            [[NSUserDefaults standardUserDefaults] setObject:[localized localizedDescription] forKey:@"VSLastBridgeError"];
            completion(nil, localized);
            return;
        }

        NSDictionary *json = nil;
        if (data) {
            json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        }

        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if ([http respondsToSelector:@selector(statusCode)] && [http statusCode] >= 400) {
            NSString *message = nil;
            if ([json isKindOfClass:[NSDictionary class]]) {
                message = [json objectForKey:@"error"];
            }
            if (!message && data) {
                message = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
            }
            if (!message) {
                message = [NSString stringWithFormat:@"HTTP %ld", (long)[http statusCode]];
            }
            NSError *statusError = [NSError errorWithDomain:@"VibeSlopik" code:[http statusCode] userInfo:[NSDictionary dictionaryWithObject:[self localizedBridgeError:message] forKey:NSLocalizedDescriptionKey]];
            [[NSUserDefaults standardUserDefaults] setObject:[statusError localizedDescription] forKey:@"VSLastBridgeError"];
            completion(nil, statusError);
            return;
        }

        if (data && !json) {
            NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
            NSError *parseError = [NSError errorWithDomain:@"VibeSlopik" code:3 userInfo:[NSDictionary dictionaryWithObject:(text ?: VSL(@"Некорректный ответ Relay", @"Invalid Relay response")) forKey:NSLocalizedDescriptionKey]];
            completion(nil, parseError);
            return;
        }
        [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:@"VSLastBridgeSuccess"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"VSLastBridgeError"];
        completion(json, nil);
    }];
}

- (void)dealloc {
    [_baseURL release];
    [_token release];
    [super dealloc];
}

@end

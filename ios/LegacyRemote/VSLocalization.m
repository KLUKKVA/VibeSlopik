#import "VSLocalization.h"

NSString *VSLanguage(void) {
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"VSLanguage"];
    if ([saved isEqual:@"ru"] || [saved isEqual:@"en"]) return saved;
    NSArray *languages = [[NSUserDefaults standardUserDefaults] objectForKey:@"AppleLanguages"];
    NSString *system = [languages count] ? [languages objectAtIndex:0] : @"en";
    return [[system lowercaseString] hasPrefix:@"ru"] ? @"ru" : @"en";
}

NSString *VSL(NSString *russian, NSString *english) { return [VSLanguage() isEqual:@"ru"] ? russian : english; }

void VSSetLanguage(NSString *language) {
    if (![language isEqual:@"ru"] && ![language isEqual:@"en"]) return;
    [[NSUserDefaults standardUserDefaults] setObject:language forKey:@"VSLanguage"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

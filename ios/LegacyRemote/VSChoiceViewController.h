#import <UIKit/UIKit.h>

typedef void (^VSChoiceCompletion)(NSDictionary *choice);

@interface VSChoiceViewController : UITableViewController
- (id)initWithTitle:(NSString *)title choices:(NSArray *)choices completion:(VSChoiceCompletion)completion;
@end

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
@interface VSChatViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIAlertViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, AVAudioRecorderDelegate>
- (id)initWithThread:(NSDictionary *)thread;
@end

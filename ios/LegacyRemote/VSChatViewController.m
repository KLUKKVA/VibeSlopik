#import "VSChatViewController.h"
#import "VSBridgeClient.h"
#import "VSUtilities.h"
#import "VSChoiceViewController.h"
#import "VSDraftStore.h"
#import "VSMediaCache.h"
#import "VSImageViewController.h"
#import "VSLocalization.h"
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>

typedef NS_ENUM(NSInteger, VSVoiceState) {
    VSVoiceStateIdle,
    VSVoiceStateRecording,
    VSVoiceStateFinishing,
    VSVoiceStateTranscribing,
};

@interface VSMicrophoneButton : UIButton
@end

@implementation VSMicrophoneButton
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    CGContextRef context = UIGraphicsGetCurrentContext();
    UIColor *color = self.enabled ? [UIColor colorWithRed:0.12 green:0.31 blue:0.53 alpha:1.0] : [UIColor lightGrayColor];
    CGContextSetStrokeColorWithColor(context, color.CGColor);
    CGContextSetLineWidth(context, 3.0);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGRect capsule = CGRectMake(rect.size.width / 2.0 - 5.5, 5, 11, 14);
    UIBezierPath *microphone = [UIBezierPath bezierPathWithRoundedRect:capsule cornerRadius:4.5];
    [microphone stroke];
    UIBezierPath *stand = [UIBezierPath bezierPath];
    [stand moveToPoint:CGPointMake(rect.size.width / 2.0 - 8, 15)];
    [stand addCurveToPoint:CGPointMake(rect.size.width / 2.0 + 8, 15) controlPoint1:CGPointMake(rect.size.width / 2.0 - 8, 23) controlPoint2:CGPointMake(rect.size.width / 2.0 + 8, 23)];
    [stand moveToPoint:CGPointMake(rect.size.width / 2.0, 23)];
    [stand addLineToPoint:CGPointMake(rect.size.width / 2.0, 27)];
    [stand moveToPoint:CGPointMake(rect.size.width / 2.0 - 5, 27)];
    [stand addLineToPoint:CGPointMake(rect.size.width / 2.0 + 5, 27)];
    [stand stroke];
}
@end

@interface VSMessageEditorViewController : UIViewController <UITextViewDelegate>
- (id)initWithTitle:(NSString *)title text:(NSString *)text confirmTitle:(NSString *)confirmTitle applyLive:(BOOL)applyLive change:(void (^)(NSString *text))change completion:(void (^)(BOOL accepted, NSString *text))completion;
@end

@interface VSMessageEditorViewController ()
@property (nonatomic, retain) UITextView *editor;
@property (nonatomic, copy) NSString *editorTitle;
@property (nonatomic, copy) NSString *confirmTitle;
@property (nonatomic, assign) BOOL applyLive;
@property (nonatomic, copy) void (^changeBlock)(NSString *text);
@property (nonatomic, copy) void (^completionBlock)(BOOL accepted, NSString *text);
@property (nonatomic, assign) CGFloat keyboardHeight;
@end

@implementation VSMessageEditorViewController
- (id)initWithTitle:(NSString *)title text:(NSString *)text confirmTitle:(NSString *)confirmTitle applyLive:(BOOL)applyLive change:(void (^)(NSString *text))change completion:(void (^)(BOOL accepted, NSString *text))completion {
    if ((self = [super init])) { self.editorTitle = title; self.confirmTitle = confirmTitle; self.applyLive = applyLive; self.changeBlock = change; self.completionBlock = completion; self.editor = [[[UITextView alloc] initWithFrame:CGRectZero] autorelease]; self.editor.text = text ?: @""; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = self.editorTitle; self.view.backgroundColor = [UIColor whiteColor];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:self.confirmTitle style:UIBarButtonItemStyleDone target:self action:@selector(confirm)] autorelease];
    self.editor.font = [UIFont systemFontOfSize:17]; self.editor.delegate = self; self.editor.scrollEnabled = YES; self.editor.alwaysBounceVertical = YES; self.editor.backgroundColor = [UIColor colorWithWhite:0.98 alpha:1.0]; self.editor.layer.borderColor = [UIColor colorWithWhite:0.72 alpha:1.0].CGColor; self.editor.layer.borderWidth = 1.0; self.editor.layer.cornerRadius = 8.0; [self.view addSubview:self.editor];
    if (!self.applyLive) self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)] autorelease];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    [self.editor becomeFirstResponder];
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; self.editor.frame = CGRectMake(10, 10, self.view.bounds.size.width - 20, self.view.bounds.size.height - self.keyboardHeight - 20); }
- (void)keyboardChanged:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo; CGRect endFrame = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue]; CGRect localFrame = [self.view convertRect:endFrame fromView:nil];
    self.keyboardHeight = [notification.name isEqualToString:UIKeyboardWillHideNotification] ? 0 : MAX(0, self.view.bounds.size.height - localFrame.origin.y);
    [UIView beginAnimations:nil context:NULL]; [UIView setAnimationDuration:[[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue]]; [self.view setNeedsLayout]; [self.view layoutIfNeeded]; [UIView commitAnimations];
}
- (void)textViewDidChange:(UITextView *)textView { if (self.applyLive && self.changeBlock) self.changeBlock(textView.text ?: @""); }
- (void)confirm { if (self.completionBlock) self.completionBlock(YES, self.editor.text ?: @""); [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)cancel { if (self.completionBlock) self.completionBlock(NO, self.editor.text ?: @""); [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [_editor release]; [_editorTitle release]; [_confirmTitle release]; [_changeBlock release]; [_completionBlock release]; [super dealloc]; }
@end

@protocol VSMediaCellTarget
- (void)mediaTapped:(UIButton *)button;
- (void)loadThumbnailForButton:(UIButton *)button media:(NSDictionary *)media;
@end

@interface VSMessageCell : UITableViewCell
@property (nonatomic, retain) UIView *bubble;
@property (nonatomic, retain) UILabel *body;
@property (nonatomic, retain) UILabel *role;
@property (nonatomic, retain) NSMutableArray *mediaButtons;
- (void)configure:(NSDictionary *)message text:(NSString *)text target:(id<VSMediaCellTarget>)target;
@end

@implementation VSMessageCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone; self.backgroundColor = [UIColor clearColor];
        self.bubble = [[[UIView alloc] initWithFrame:CGRectZero] autorelease]; self.bubble.layer.cornerRadius = 11; self.bubble.layer.borderWidth = 1; [self.contentView addSubview:self.bubble];
        self.body = [[[UILabel alloc] initWithFrame:CGRectZero] autorelease]; self.body.backgroundColor = [UIColor clearColor]; self.body.numberOfLines = 0; [self.bubble addSubview:self.body];
        self.role = [[[UILabel alloc] initWithFrame:CGRectZero] autorelease]; self.role.backgroundColor = [UIColor clearColor]; self.role.font = [UIFont systemFontOfSize:11]; self.role.textColor = [UIColor grayColor]; [self.bubble addSubview:self.role];
        self.mediaButtons = [NSMutableArray array];
    }
    return self;
}
- (void)configure:(NSDictionary *)message text:(NSString *)text target:(id<VSMediaCellTarget>)target {
    for (UIButton *button in self.mediaButtons) [button removeFromSuperview]; [self.mediaButtons removeAllObjects];
    NSString *kind = VSString([message objectForKey:@"kind"], @""); NSString *raw = VSString([message objectForKey:@"text"], @""); NSString *ticks = [NSString stringWithFormat:@"%c%c%c", 96, 96, 96]; BOOL user = [kind isEqual:@"user"]; BOOL command = [kind isEqual:@"command"];
    NSArray *media = VSArray([message objectForKey:@"media"]); CGFloat mediaHeight = [media count] ? 76.0 : 0.0; CGFloat width = command ? 286 : 270; CGFloat x = user ? 320 - width - 8 : 8; CGSize textSize = [text sizeWithFont:command ? [UIFont fontWithName:@"Courier" size:13] : [UIFont systemFontOfSize:15] constrainedToSize:CGSizeMake(width - 20, 2000)];
    self.bubble.frame = CGRectMake(x, 5, width, textSize.height + mediaHeight + 34); self.body.frame = CGRectMake(10, 8, width - 20, textSize.height + 2); self.role.frame = CGRectMake(10, textSize.height + mediaHeight + 11, width - 20, 17);
    NSUInteger mediaIndex = 0; for (NSDictionary *item in media) { if (mediaIndex >= 4) break; UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom]; button.frame = CGRectMake(10 + mediaIndex * 63, textSize.height + 8, 58, 68); button.accessibilityLabel = VSString([item objectForKey:@"id"], @""); button.titleLabel.font = [UIFont boldSystemFontOfSize:10]; button.titleLabel.numberOfLines = 2; button.titleLabel.textAlignment = NSTextAlignmentCenter; [button setTitle:VSL(@"Фото\nзагрузить", @"Load\nimage") forState:UIControlStateNormal]; [button setTitleColor:[UIColor colorWithRed:0.12 green:0.31 blue:0.53 alpha:1] forState:UIControlStateNormal]; button.backgroundColor = [UIColor colorWithWhite:0.90 alpha:1]; button.layer.cornerRadius = 6; button.clipsToBounds = YES; [button addTarget:target action:@selector(mediaTapped:) forControlEvents:UIControlEventTouchUpInside]; [self.bubble addSubview:button]; [self.mediaButtons addObject:button]; if ([VSMediaCache autoDownload] || [VSMediaCache dataForKey:[NSString stringWithFormat:@"%@-thumb", button.accessibilityLabel]]) [target loadThumbnailForButton:button media:item]; mediaIndex++; }
    UIFont *font = command ? [UIFont fontWithName:@"Courier" size:13] : [UIFont systemFontOfSize:15]; NSMutableAttributedString *styled = [[[NSMutableAttributedString alloc] initWithString:text attributes:[NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]] autorelease];
    if (!command) {
        NSRegularExpression *bold = [NSRegularExpression regularExpressionWithPattern:@"\\*\\*([^*]+)\\*\\*" options:0 error:nil];
        for (NSTextCheckingResult *match in [bold matchesInString:raw options:0 range:NSMakeRange(0, [raw length])]) { NSString *part = [raw substringWithRange:[match rangeAtIndex:1]]; NSRange found = [text rangeOfString:part]; if (found.location != NSNotFound) [styled addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:15] range:found]; }
        NSRegularExpression *heading = [NSRegularExpression regularExpressionWithPattern:@"(?m)^#{1,4}\\s+(.+)$" options:0 error:nil];
        for (NSTextCheckingResult *match in [heading matchesInString:raw options:0 range:NSMakeRange(0, [raw length])]) { NSString *part = [raw substringWithRange:[match rangeAtIndex:1]]; NSRange found = [text rangeOfString:part]; if (found.location != NSNotFound) [styled addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:17] range:found]; }
        NSString *inlinePattern = [NSString stringWithFormat:@"%c([^%c]+)%c", 96, 96, 96]; NSRegularExpression *inlineCode = [NSRegularExpression regularExpressionWithPattern:inlinePattern options:0 error:nil];
        for (NSTextCheckingResult *match in [inlineCode matchesInString:raw options:0 range:NSMakeRange(0, [raw length])]) { NSString *part = [raw substringWithRange:[match rangeAtIndex:1]]; NSRange found = [text rangeOfString:part]; if (found.location != NSNotFound) { [styled addAttribute:NSFontAttributeName value:[UIFont fontWithName:@"Courier" size:13] range:found]; [styled addAttribute:NSBackgroundColorAttributeName value:[UIColor colorWithWhite:0.90 alpha:1.0] range:found]; } }
        NSString *blockPattern = [NSString stringWithFormat:@"%@(?:[A-Za-z0-9_+-]+)?\\n([\\s\\S]*?)%@", ticks, ticks]; NSRegularExpression *codeBlock = [NSRegularExpression regularExpressionWithPattern:blockPattern options:0 error:nil];
        for (NSTextCheckingResult *match in [codeBlock matchesInString:raw options:0 range:NSMakeRange(0, [raw length])]) { NSString *part = [raw substringWithRange:[match rangeAtIndex:1]]; NSRange found = [text rangeOfString:part]; if (found.location != NSNotFound) { [styled addAttribute:NSFontAttributeName value:[UIFont fontWithName:@"Courier" size:13] range:found]; [styled addAttribute:NSBackgroundColorAttributeName value:[UIColor colorWithWhite:0.91 alpha:1.0] range:found]; } }
        NSRegularExpression *link = [NSRegularExpression regularExpressionWithPattern:@"\\[([^]]+)\\]\\([^)]+\\)" options:0 error:nil];
        for (NSTextCheckingResult *match in [link matchesInString:raw options:0 range:NSMakeRange(0, [raw length])]) { NSString *part = [raw substringWithRange:[match rangeAtIndex:1]]; NSRange found = [text rangeOfString:part]; if (found.location != NSNotFound) { [styled addAttribute:NSForegroundColorAttributeName value:[UIColor colorWithRed:0.05 green:0.32 blue:0.67 alpha:1.0] range:found]; [styled addAttribute:NSUnderlineStyleAttributeName value:[NSNumber numberWithInt:NSUnderlineStyleSingle] range:found]; } }
    }
    self.body.attributedText = styled; self.body.font = font; self.body.textColor = [UIColor colorWithWhite:0.08 alpha:1.0]; self.role.text = VSString([message objectForKey:@"title"], user ? VSL(@"Вы", @"You") : @"Codex");
    if (command) { self.bubble.backgroundColor = [UIColor colorWithWhite:0.91 alpha:1.0]; self.bubble.layer.borderColor = [UIColor colorWithWhite:0.72 alpha:1.0].CGColor; }
    else if (user) { self.bubble.backgroundColor = [UIColor colorWithRed:0.82 green:0.91 blue:0.98 alpha:1.0]; self.bubble.layer.borderColor = [UIColor colorWithRed:0.50 green:0.70 blue:0.86 alpha:1.0].CGColor; }
    else { self.bubble.backgroundColor = [UIColor colorWithWhite:0.99 alpha:1.0]; self.bubble.layer.borderColor = [UIColor colorWithWhite:0.78 alpha:1.0].CGColor; }
}
- (void)dealloc { [_bubble release]; [_body release]; [_role release]; [_mediaButtons release]; [super dealloc]; }
@end

@interface VSChatViewController () <VSMediaCellTarget>
@property (nonatomic, retain) NSDictionary *thread;
@property (nonatomic, retain) NSArray *messages;
@property (nonatomic, retain) UITableView *table;
@property (nonatomic, retain) UITextField *input;
@property (nonatomic, retain) UILabel *activity;
@property (nonatomic, retain) NSTimer *pollTimer;
@property (nonatomic, retain) NSDictionary *usage;
@property (nonatomic, retain) NSDictionary *limits;
@property (nonatomic, assign) CGFloat keyboardHeight;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL sending;
@property (nonatomic, retain) NSDate *limitsUpdatedAt;
@property (nonatomic, retain) NSMutableArray *pendingImages;
@property (nonatomic, retain) NSArray *models;
@property (nonatomic, retain) NSArray *visibleModels;
@property (nonatomic, retain) NSArray *visibleEfforts;
@property (nonatomic, copy) NSString *selectedModel;
@property (nonatomic, copy) NSString *selectedEffort;
@property (nonatomic, copy) NSString *selectedApprovalMode;
@property (nonatomic, copy) NSString *activeApprovalId;
@property (nonatomic, retain) UIButton *optionsButton;
@property (nonatomic, assign) BOOL hasLoadedMessages;
@property (nonatomic, retain) AVAudioRecorder *recorder;
@property (nonatomic, retain) NSURL *recordingURL;
@property (nonatomic, assign) BOOL recording;
@property (nonatomic, assign) BOOL speechEnabled;
@property (nonatomic, assign) VSVoiceState voiceState;
@property (nonatomic, copy) NSString *voiceOperationId;
@property (nonatomic, retain) UIButton *voiceButton;
@property (nonatomic, retain) UIButton *retryButton;
@property (nonatomic, retain) UIButton *approvalButton;
@property (nonatomic, retain) NSDictionary *activeTurn;
@property (nonatomic, assign) NSInteger selectedMessageIndex;
@property (nonatomic, copy) NSString *pendingRequestId;
@end

static NSString *VSBase64(NSData *data) {
    static const char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const unsigned char *bytes = [data bytes]; NSUInteger length = [data length];
    NSMutableString *result = [NSMutableString stringWithCapacity:((length + 2) / 3) * 4];
    for (NSUInteger i = 0; i < length; i += 3) {
        unsigned long value = bytes[i] << 16;
        if (i + 1 < length) value |= bytes[i + 1] << 8;
        if (i + 2 < length) value |= bytes[i + 2];
        [result appendFormat:@"%c%c%c%c", table[(value >> 18) & 63], table[(value >> 12) & 63], i + 1 < length ? table[(value >> 6) & 63] : '=', i + 2 < length ? table[value & 63] : '='];
    }
    return result;
}

@implementation VSChatViewController

- (id)initWithThread:(NSDictionary *)thread { if ((self = [super init])) { self.thread = thread; self.messages = [NSArray array]; self.pendingImages = [NSMutableArray array]; self.selectedModel = @""; self.selectedEffort = @""; self.selectedApprovalMode = @"inherit"; } return self; }
- (NSString *)threadId { return VSString([self.thread objectForKey:@"id"], VSString([self.thread objectForKey:@"threadId"], @"")); }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = VSString([self.thread objectForKey:@"name"], VSString([self.thread objectForKey:@"preview"], VSL(@"\u0427\u0430\u0442", @"Chat")));
    self.view.backgroundColor = [UIColor whiteColor];
    self.navigationItem.rightBarButtonItems = [NSArray arrayWithObjects:[[[UIBarButtonItem alloc] initWithTitle:@"..." style:UIBarButtonItemStyleBordered target:self action:@selector(showMenu)] autorelease], [[[UIBarButtonItem alloc] initWithTitle:@"i" style:UIBarButtonItemStyleBordered target:self action:@selector(showContext)] autorelease], nil];
    self.table = [[[UITableView alloc] initWithFrame:CGRectMake(0, 0, 0, 0) style:UITableViewStylePlain] autorelease]; self.table.dataSource = self; self.table.delegate = self; self.table.separatorStyle = UITableViewCellSeparatorStyleNone; [self.view addSubview:self.table];
    UILongPressGestureRecognizer *longPress = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(messageLongPressed:)] autorelease]; [self.table addGestureRecognizer:longPress];
    UIView *attachmentBar = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 0)] autorelease]; attachmentBar.tag = 72; attachmentBar.backgroundColor = [UIColor colorWithWhite:0.88 alpha:1.0]; attachmentBar.hidden = YES; [self.view addSubview:attachmentBar];
    UIView *composer = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 0)] autorelease]; composer.tag = 71; composer.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0]; [self.view addSubview:composer];
    self.optionsButton = [UIButton buttonWithType:UIButtonTypeCustom]; self.optionsButton.frame = CGRectMake(42, 1, 270, 20); self.optionsButton.titleLabel.font = [UIFont boldSystemFontOfSize:10]; [self.optionsButton setTitleColor:[UIColor colorWithRed:0.13 green:0.31 blue:0.46 alpha:1] forState:UIControlStateNormal]; [self.optionsButton setBackgroundImage:VSBeveledButtonImage(NO) forState:UIControlStateNormal]; [self.optionsButton setBackgroundImage:VSBeveledButtonImage(YES) forState:UIControlStateHighlighted]; [self.optionsButton addTarget:self action:@selector(showOptionsMenu) forControlEvents:UIControlEventTouchUpInside]; [composer addSubview:self.optionsButton]; [self updateOptionsTitle];
    UIButton *plus = [UIButton buttonWithType:UIButtonTypeContactAdd]; plus.frame = CGRectMake(8, 27, 32, 32); [plus addTarget:self action:@selector(showAttachmentNote) forControlEvents:UIControlEventTouchUpInside]; [composer addSubview:plus];
    self.input = [[[UITextField alloc] initWithFrame:CGRectMake(45, 27, 123, 32)] autorelease]; self.input.borderStyle = UITextBorderStyleRoundedRect; self.input.placeholder = VSL(@"\u0421\u043f\u0440\u043e\u0441\u0438\u0442\u044c Codex", @"Ask Codex"); self.input.delegate = self; self.input.returnKeyType = UIReturnKeySend; self.input.clearButtonMode = UITextFieldViewModeWhileEditing; [composer addSubview:self.input];
    [self.input addTarget:self action:@selector(draftChanged) forControlEvents:UIControlEventEditingChanged];
    UIButton *editor = [UIButton buttonWithType:UIButtonTypeCustom]; editor.frame = CGRectMake(171, 27, 29, 32); [editor setBackgroundImage:VSBeveledButtonImage(NO) forState:UIControlStateNormal]; [editor setBackgroundImage:VSBeveledButtonImage(YES) forState:UIControlStateHighlighted]; [editor setImage:VSInterfaceIcon(@"editor") forState:UIControlStateNormal]; editor.accessibilityLabel = VSL(@"Развернуть текст", @"Open full editor"); [editor addTarget:self action:@selector(showFullEditor) forControlEvents:UIControlEventTouchUpInside]; [composer addSubview:editor];
    self.voiceButton = [VSMicrophoneButton buttonWithType:UIButtonTypeCustom]; self.voiceButton.frame = CGRectMake(203, 27, 29, 32); [self.voiceButton setBackgroundImage:VSBeveledButtonImage(NO) forState:UIControlStateNormal]; [self.voiceButton setBackgroundImage:VSBeveledButtonImage(YES) forState:UIControlStateHighlighted]; self.voiceButton.accessibilityLabel = VSL(@"Диктовка", @"Dictation"); [self.voiceButton addTarget:self action:@selector(toggleVoice) forControlEvents:UIControlEventTouchUpInside]; [composer addSubview:self.voiceButton];
    UIButton *send = [UIButton buttonWithType:UIButtonTypeCustom]; send.frame = CGRectMake(235, 27, 77, 32); [send setBackgroundImage:VSBeveledButtonImage(NO) forState:UIControlStateNormal]; [send setBackgroundImage:VSBeveledButtonImage(YES) forState:UIControlStateHighlighted]; [send setTitleColor:[UIColor colorWithRed:0.13 green:0.31 blue:0.50 alpha:1] forState:UIControlStateNormal]; [send setTitle:VSL(@"\u041e\u0442\u043f\u0440\u0430\u0432\u0438\u0442\u044c", @"Send") forState:UIControlStateNormal]; send.titleLabel.font = [UIFont boldSystemFontOfSize:12]; [send addTarget:self action:@selector(sendText) forControlEvents:UIControlEventTouchUpInside]; [composer addSubview:send];
    self.activity = [[[UILabel alloc] initWithFrame:CGRectMake(8, 0, 300, 18)] autorelease]; self.activity.font = [UIFont systemFontOfSize:11]; self.activity.textColor = [UIColor grayColor]; self.activity.text = @""; [self.view addSubview:self.activity];
    self.retryButton = [UIButton buttonWithType:UIButtonTypeCustom]; self.retryButton.hidden = YES; self.retryButton.titleLabel.font = [UIFont boldSystemFontOfSize:11]; self.retryButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft; [self.retryButton setTitleColor:[UIColor colorWithRed:0.65 green:0.08 blue:0.08 alpha:1] forState:UIControlStateNormal]; [self.retryButton addTarget:self action:@selector(sendText) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:self.retryButton];
    self.approvalButton = [UIButton buttonWithType:UIButtonTypeCustom]; self.approvalButton.hidden = YES; self.approvalButton.titleLabel.font = [UIFont boldSystemFontOfSize:11]; self.approvalButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft; [self.approvalButton setTitleColor:[UIColor colorWithRed:0.62 green:0.38 blue:0.0 alpha:1] forState:UIControlStateNormal]; [self.approvalButton setTitle:VSL(@"Codex \u0436\u0434\u0451\u0442 \u0440\u0430\u0437\u0440\u0435\u0448\u0435\u043d\u0438\u0435 \u2014 \u043d\u0430\u0436\u043c\u0438\u0442\u0435", @"Codex needs approval — tap here") forState:UIControlStateNormal]; [self.approvalButton addTarget:self action:@selector(showPendingApproval) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:self.approvalButton];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveDraftNow) name:UIApplicationWillResignActiveNotification object:nil];
    [[VSBridgeClient sharedClient] getPath:@"/api/models" completion:^(NSDictionary *response, NSError *error) { if (!error) self.models = VSArray([response objectForKey:@"data"]); }];
    [[VSBridgeClient sharedClient] getPath:@"/api/capabilities" completion:^(NSDictionary *response, NSError *error) { if (!error) self.speechEnabled = [[[response objectForKey:@"speech"] objectForKey:@"enabled"] boolValue]; }];
    [self restoreDraft];
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.pollTimer invalidate]; self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(refresh) userInfo:nil repeats:YES]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self saveDraftNow]; [self.pollTimer invalidate]; self.pollTimer = nil; }
- (void)keyboardChanged:(NSNotification *)notification { NSDictionary *info = [notification userInfo]; CGRect endFrame = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue]; CGRect localFrame = [self.view convertRect:endFrame fromView:nil]; self.keyboardHeight = [[notification name] isEqualToString:UIKeyboardWillHideNotification] ? 0 : MAX(0, self.view.bounds.size.height - localFrame.origin.y); [UIView beginAnimations:nil context:NULL]; [UIView setAnimationDuration:[[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue]]; [self.view setNeedsLayout]; [self.view layoutIfNeeded]; [UIView commitAnimations]; }
- (void)viewDidLayoutSubviews { CGRect bounds = self.view.bounds; CGFloat bottom = self.keyboardHeight; CGFloat attachments = [self.pendingImages count] ? 62.0 : 0.0; UIView *composer = [self.view viewWithTag:71]; UIView *attachmentBar = [self.view viewWithTag:72]; composer.frame = CGRectMake(0, bounds.size.height - bottom - 66, bounds.size.width, 66); attachmentBar.frame = CGRectMake(0, bounds.size.height - bottom - 66 - attachments, bounds.size.width, attachments); self.table.frame = CGRectMake(0, 18, bounds.size.width, bounds.size.height - bottom - 84 - attachments); self.activity.frame = CGRectMake(8, 0, bounds.size.width - 16, 18); self.retryButton.frame = self.activity.frame; self.approvalButton.frame = self.activity.frame; }

- (void)restoreDraft { NSDictionary *draft = [VSDraftStore draftForThread:[self threadId]]; if (!draft) return; self.input.text = VSString([draft objectForKey:@"text"], @""); self.pendingRequestId = VSString([draft objectForKey:@"requestId"], @""); [self.pendingImages setArray:VSArray([draft objectForKey:@"images"])]; [self rebuildAttachmentBar]; }
- (void)draftChanged { if (!self.sending) self.pendingRequestId = @""; [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveDraftNow) object:nil]; [self performSelector:@selector(saveDraftNow) withObject:nil afterDelay:0.7]; }
- (void)saveDraftNow { [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveDraftNow) object:nil]; [VSDraftStore saveDraftForThread:[self threadId] text:self.input.text images:self.pendingImages requestId:self.pendingRequestId]; }
- (void)showRetry:(NSString *)message { self.retryButton.hidden = NO; self.activity.hidden = YES; [self.retryButton setTitle:[NSString stringWithFormat:VSL(@"\u041d\u0435 \u043e\u0442\u043f\u0440\u0430\u0432\u043b\u0435\u043d\u043e: %@. \u041f\u043e\u0432\u0442\u043e\u0440\u0438\u0442\u044c", @"Not sent: %@. Retry"), message ?: VSL(@"\u043e\u0448\u0438\u0431\u043a\u0430", @"error")] forState:UIControlStateNormal]; }
- (void)hideRetry { self.retryButton.hidden = YES; self.activity.hidden = NO; }

- (BOOL)isNearBottom { if (self.table.contentSize.height <= self.table.bounds.size.height) return YES; return self.table.contentOffset.y + self.table.bounds.size.height >= self.table.contentSize.height - 90.0; }
- (NSString *)approvalTitle { if ([self.selectedApprovalMode isEqual:@"ask"]) return VSL(@"\u0441\u043f\u0440\u0430\u0448\u0438\u0432\u0430\u0442\u044c", @"ask me"); if ([self.selectedApprovalMode isEqual:@"auto"]) return VSL(@"\u0430\u0432\u0442\u043e\u043f\u0440\u043e\u0432\u0435\u0440\u043a\u0430", @"auto review"); if ([self.selectedApprovalMode isEqual:@"never"]) return VSL(@"\u0431\u0435\u0437 \u0437\u0430\u043f\u0440\u043e\u0441\u043e\u0432", @"no prompts"); return VSL(@"\u043d\u0430\u0441\u043b\u0435\u0434\u043e\u0432\u0430\u043d\u0438\u0435", @"inherit"); }
- (void)updateOptionsTitle { if (![self.selectedModel length] && ![self.selectedEffort length] && [self.selectedApprovalMode isEqual:@"inherit"]) { [self.optionsButton setTitle:VSL(@"\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438 \u0432\u0435\u0442\u043a\u0438: \u043d\u0430\u0441\u043b\u0435\u0434\u043e\u0432\u0430\u0442\u044c", @"Thread settings: inherit") forState:UIControlStateNormal]; return; } NSString *model = [self.selectedModel length] ? self.selectedModel : VSL(@"\u041c\u043e\u0434\u0435\u043b\u044c \u0432\u0435\u0442\u043a\u0438", @"Thread model"); NSString *effort = [self.selectedEffort length] ? [self effortTitle:self.selectedEffort] : VSL(@"\u043f\u043e \u0443\u043c\u043e\u043b\u0447\u0430\u043d\u0438\u044e", @"default"); [self.optionsButton setTitle:[NSString stringWithFormat:@"%@ \u2022 %@ \u2022 %@", model, effort, [self approvalTitle]] forState:UIControlStateNormal]; }
- (NSString *)effortTitle:(NSString *)effort { if ([effort isEqual:@"low"]) return VSL(@"\u043d\u0438\u0437\u043a\u0438\u0439", @"low"); if ([effort isEqual:@"medium"]) return VSL(@"\u0441\u0440\u0435\u0434\u043d\u0438\u0439", @"medium"); if ([effort isEqual:@"high"]) return VSL(@"\u0432\u044b\u0441\u043e\u043a\u0438\u0439", @"high"); if ([effort isEqual:@"xhigh"]) return VSL(@"\u043e\u0447\u0435\u043d\u044c \u0432\u044b\u0441\u043e\u043a\u0438\u0439", @"extra high"); return effort; }
- (void)saveOptions { [self updateOptionsTitle]; }
- (void)rebuildAttachmentBar { UIView *bar = [self.view viewWithTag:72]; for (UIView *view in [NSArray arrayWithArray:[bar subviews]]) [view removeFromSuperview]; NSInteger index = 0; for (NSData *data in self.pendingImages) { CGFloat x = 8 + index * 58; UIImageView *thumbnail = [[[UIImageView alloc] initWithFrame:CGRectMake(x, 6, 50, 50)] autorelease]; thumbnail.image = [UIImage imageWithData:data]; thumbnail.contentMode = UIViewContentModeScaleAspectFill; thumbnail.clipsToBounds = YES; thumbnail.layer.cornerRadius = 6; thumbnail.layer.borderWidth = 1; thumbnail.layer.borderColor = [UIColor darkGrayColor].CGColor; [bar addSubview:thumbnail]; UIButton *remove = [UIButton buttonWithType:UIButtonTypeCustom]; remove.tag = index; remove.frame = CGRectMake(x + 32, 0, 24, 24); [remove setTitle:@"\u00d7" forState:UIControlStateNormal]; remove.titleLabel.font = [UIFont boldSystemFontOfSize:22]; [remove setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; remove.backgroundColor = [UIColor colorWithRed:0.65 green:0.08 blue:0.08 alpha:0.9]; remove.layer.cornerRadius = 12; [remove addTarget:self action:@selector(removeAttachment:) forControlEvents:UIControlEventTouchUpInside]; [bar addSubview:remove]; index++; } bar.hidden = ![self.pendingImages count]; [self.view setNeedsLayout]; }
- (void)removeAttachment:(UIButton *)button { if (button.tag < [self.pendingImages count]) [self.pendingImages removeObjectAtIndex:button.tag]; [self rebuildAttachmentBar]; [self draftChanged]; self.activity.text = [self.pendingImages count] ? [NSString stringWithFormat:VSL(@"\u0424\u043e\u0442\u043e: %lu", @"Images: %lu"), (unsigned long)[self.pendingImages count]] : @""; }
- (NSString *)displayText:(NSString *)text {
    NSMutableString *value = [NSMutableString stringWithString:(text ?: @"")]; [value replaceOccurrencesOfString:@"\r\n" withString:@"\n" options:0 range:NSMakeRange(0, [value length])];
    NSString *ticks = [NSString stringWithFormat:@"%c%c%c", 96, 96, 96]; NSString *openingPattern = [NSString stringWithFormat:@"(?m)^%@[A-Za-z0-9_+-]*\\n", ticks]; NSRegularExpression *opening = [NSRegularExpression regularExpressionWithPattern:openingPattern options:0 error:nil]; [opening replaceMatchesInString:value options:0 range:NSMakeRange(0, [value length]) withTemplate:@""];
    NSRegularExpression *links = [NSRegularExpression regularExpressionWithPattern:@"\\[([^]]+)\\]\\([^)]+\\)" options:0 error:nil]; [links replaceMatchesInString:value options:0 range:NSMakeRange(0, [value length]) withTemplate:@"$1"];
    NSArray *markers = [NSArray arrayWithObjects:ticks, [NSString stringWithFormat:@"%c", 96], @"**", @"__", nil]; for (NSString *marker in markers) [value replaceOccurrencesOfString:marker withString:@"" options:0 range:NSMakeRange(0, [value length])];
    [value replaceOccurrencesOfString:@"\n- " withString:@"\n\u2022 " options:0 range:NSMakeRange(0, [value length])]; [value replaceOccurrencesOfString:@"\n* " withString:@"\n\u2022 " options:0 range:NSMakeRange(0, [value length])]; [value replaceOccurrencesOfString:@"\n> " withString:@"\n\u275d " options:0 range:NSMakeRange(0, [value length])];
    if ([value hasPrefix:@"- "] || [value hasPrefix:@"* "]) [value replaceCharactersInRange:NSMakeRange(0, 2) withString:@"\u2022 "]; if ([value hasPrefix:@"> "]) [value replaceCharactersInRange:NSMakeRange(0, 2) withString:@"\u275d "];
    NSRegularExpression *headings = [NSRegularExpression regularExpressionWithPattern:@"(?m)^#{1,4}\\s+" options:0 error:nil]; [headings replaceMatchesInString:value options:0 range:NSMakeRange(0, [value length]) withTemplate:@""];
    return value;
}
- (void)showTurnStatus:(NSDictionary *)turn {
    NSString *status = VSString([turn objectForKey:@"status"], @"");
    if ([status isEqual:@"starting"]) self.activity.text = VSL(@"Codex принимает сообщение...", @"Codex is accepting the message...");
    else if ([status isEqual:@"inProgress"]) self.activity.text = VSL(@"Codex работает...", @"Codex is working...");
    else if ([status isEqual:@"failed"]) self.activity.text = VSString([turn objectForKey:@"error"], VSL(@"Codex завершил запрос с ошибкой", @"Codex failed to complete the request"));
    else if ([status isEqual:@"completed"]) self.activity.text = VSL(@"\u0413\u043e\u0442\u043e\u0432\u043e", @"Done");
    else self.activity.text = @"";
}

- (void)refresh {
    if (![[self threadId] length] || self.loading || self.sending) return;
    self.loading = YES;
    NSString *escaped = [[self threadId] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    [[VSBridgeClient sharedClient] getPath:[NSString stringWithFormat:@"/api/threads/%@", escaped] completion:^(NSDictionary *response, NSError *error) {
        self.loading = NO;
        if (error || ![[response objectForKey:@"ok"] boolValue]) { self.activity.text = error ? [error localizedDescription] : VSL(@"\u041d\u0435\u0442 \u0441\u0432\u044f\u0437\u0438", @"No connection"); return; }
        BOOL stickToBottom = [self isNearBottom]; NSInteger previousCount = [self.messages count]; BOOL firstLoad = !self.hasLoadedMessages;
        NSDictionary *loaded = [response objectForKey:@"thread"] ?: response;
        self.thread = loaded; self.messages = VSArray([loaded objectForKey:@"messages"]); self.usage = VSDictionary([loaded objectForKey:@"tokenUsage"]); self.title = VSString([loaded objectForKey:@"name"], self.title);
        NSDictionary *actualSettings = VSDictionary([loaded objectForKey:@"threadSettings"]);
        NSDictionary *remoteOverride = VSDictionary([loaded objectForKey:@"override"]);
        if ([actualSettings count]) {
            self.selectedModel = VSString([actualSettings objectForKey:@"model"], @"");
            self.selectedEffort = VSString([actualSettings objectForKey:@"effort"], @"");
            NSString *reviewer = VSString([actualSettings objectForKey:@"approvalsReviewer"], @"");
            NSString *policy = VSString([actualSettings objectForKey:@"approvalPolicy"], @"");
            self.selectedApprovalMode = [policy isEqual:@"never"] ? @"never" : ([reviewer isEqual:@"auto_review"] ? @"auto" : @"ask");
            [self updateOptionsTitle];
        } else if ([[remoteOverride objectForKey:@"mode"] isEqual:@"persistent"]) {
            self.selectedModel = VSString([remoteOverride objectForKey:@"model"], @"");
            self.selectedEffort = VSString([remoteOverride objectForKey:@"reasoningEffort"], @"");
            NSString *reviewer = VSString([remoteOverride objectForKey:@"approvalsReviewer"], @"");
            NSString *policy = VSString([remoteOverride objectForKey:@"approvalPolicy"], @"");
            self.selectedApprovalMode = [policy isEqual:@"never"] ? @"never" : ([reviewer isEqual:@"auto_review"] ? @"auto" : ([policy length] ? @"ask" : @"inherit"));
            [self updateOptionsTitle];
        }
        self.activeTurn = VSDictionary([loaded objectForKey:@"activeTurn"]); [self showTurnStatus:self.activeTurn];
        [self.table reloadData]; self.hasLoadedMessages = YES; if ([self.messages count] && (firstLoad || (stickToBottom && [self.messages count] > previousCount))) [self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:[self.messages count] - 1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
    }];
    if (!self.limitsUpdatedAt || [[NSDate date] timeIntervalSinceDate:self.limitsUpdatedAt] > 60.0) {
        self.limitsUpdatedAt = [NSDate date];
        [[VSBridgeClient sharedClient] getPath:@"/api/account/limits" completion:^(NSDictionary *response, NSError *error) { if (!error) self.limits = [response objectForKey:@"rateLimits"]; }];
    }
    if (!self.activeApprovalId) { NSString *approvalPath = [NSString stringWithFormat:@"/api/approvals?threadId=%@", escaped]; [[VSBridgeClient sharedClient] getPath:approvalPath completion:^(NSDictionary *response, NSError *error) { NSArray *items = VSArray([response objectForKey:@"data"]); if (error || ![items count] || self.activeApprovalId) return; NSDictionary *approval = [items objectAtIndex:0]; self.activeApprovalId = VSString([approval objectForKey:@"id"], @""); self.approvalButton.hidden = NO; self.activity.hidden = YES; [self showPendingApproval]; }]; }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return MAX((NSInteger)[self.messages count], 1); }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { if (![self.messages count]) return 70; NSDictionary *m = [self.messages objectAtIndex:indexPath.row]; NSString *t = [self displayText:VSString([m objectForKey:@"text"], @"")]; BOOL command = [[m objectForKey:@"kind"] isEqual:@"command"]; CGSize size = [t sizeWithFont:command ? [UIFont fontWithName:@"Courier" size:13] : [UIFont systemFontOfSize:15] constrainedToSize:CGSizeMake(command ? 266 : 250, 2000)]; CGFloat mediaHeight = [VSArray([m objectForKey:@"media"]) count] ? 76.0 : 0.0; return MAX(50, size.height + mediaHeight + 44); }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![self.messages count]) { static NSString *emptyId = @"Empty"; UITableViewCell *empty = [tableView dequeueReusableCellWithIdentifier:emptyId]; if (!empty) empty = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:emptyId] autorelease]; empty.textLabel.text = VSL(@"\u041d\u0430\u043f\u0438\u0448\u0438\u0442\u0435 \u043f\u0435\u0440\u0432\u043e\u0435 \u0441\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u0435", @"Write the first message"); empty.detailTextLabel.text = VSL(@"/compact \u0442\u043e\u0436\u0435 \u0440\u0430\u0431\u043e\u0442\u0430\u0435\u0442", @"/compact works too"); return empty; }
    static NSString *cid = @"BubbleMessage"; VSMessageCell *cell = (VSMessageCell *)[tableView dequeueReusableCellWithIdentifier:cid]; if (!cell) cell = [[[VSMessageCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid] autorelease]; NSDictionary *message = [self.messages objectAtIndex:indexPath.row]; [cell configure:message text:[self displayText:VSString([message objectForKey:@"text"], @"")] target:self]; return cell;
}
- (NSDictionary *)mediaWithID:(NSString *)mediaID { for (NSDictionary *message in self.messages) for (NSDictionary *media in VSArray([message objectForKey:@"media"])) if ([[media objectForKey:@"id"] isEqual:mediaID]) return media; return nil; }
- (void)loadThumbnailForButton:(UIButton *)button media:(NSDictionary *)media { NSString *mediaID = VSString([media objectForKey:@"id"], @""); NSString *key = [NSString stringWithFormat:@"%@-thumb", mediaID]; NSData *cached = [VSMediaCache dataForKey:key]; if (cached) { [button setImage:[UIImage imageWithData:cached] forState:UIControlStateNormal]; [button setTitle:nil forState:UIControlStateNormal]; button.imageView.contentMode = UIViewContentModeScaleAspectFill; return; } [button setTitle:VSL(@"Загрузка...", @"Loading...") forState:UIControlStateNormal]; [[VSBridgeClient sharedClient] getPath:[media objectForKey:@"thumbnailPath"] completion:^(NSDictionary *response, NSError *error) { if (![[button accessibilityLabel] isEqual:mediaID]) return; if (error) { [button setTitle:VSL(@"Ошибка\nповторить", @"Error\nretry") forState:UIControlStateNormal]; return; } NSData *data = [VSMediaCache decodeBase64:[response objectForKey:@"base64"]]; if (data) { [VSMediaCache storeData:data forKey:key]; [button setImage:[UIImage imageWithData:data] forState:UIControlStateNormal]; [button setTitle:nil forState:UIControlStateNormal]; button.imageView.contentMode = UIViewContentModeScaleAspectFill; } }]; }
- (void)mediaTapped:(UIButton *)button { NSDictionary *media = [self mediaWithID:button.accessibilityLabel]; if (!media) return; NSString *key = [NSString stringWithFormat:@"%@-thumb", button.accessibilityLabel]; if (![VSMediaCache dataForKey:key]) { [self loadThumbnailForButton:button media:media]; return; } VSImageViewController *viewer = [[[VSImageViewController alloc] initWithMedia:media] autorelease]; [self.navigationController pushViewController:viewer animated:YES]; }
- (void)showMessageDetailsAtIndex:(NSInteger)index { if (index < 0 || index >= [self.messages count]) return; NSDictionary *message = [self.messages objectAtIndex:index]; NSString *details = [NSString stringWithFormat:VSL(@"Роль: %@\nTurn: %@\nВремя: %@\nМодель: %@\nМышление: %@\nСтатус: %@", @"Role: %@\nTurn: %@\nTime: %@\nModel: %@\nReasoning: %@\nStatus: %@"), VSString([message objectForKey:@"title"], @"—"), VSString([message objectForKey:@"turnId"], @"—"), VSString([message objectForKey:@"createdAt"], @"—"), VSString([message objectForKey:@"model"], @"—"), VSString([message objectForKey:@"reasoningEffort"], @"—"), VSString([message objectForKey:@"status"], @"—")]; [[[UIAlertView alloc] initWithTitle:VSL(@"Сведения о сообщении", @"Message details") message:details delegate:nil cancelButtonTitle:VSL(@"Закрыть", @"Close") otherButtonTitles:nil] show]; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { [tableView deselectRowAtIndexPath:indexPath animated:YES]; if ([self.messages count]) [self showMessageDetailsAtIndex:indexPath.row]; }
- (void)messageLongPressed:(UILongPressGestureRecognizer *)gesture { if (gesture.state != UIGestureRecognizerStateBegan) return; NSIndexPath *indexPath = [self.table indexPathForRowAtPoint:[gesture locationInView:self.table]]; if (!indexPath || indexPath.row >= [self.messages count]) return; self.selectedMessageIndex = indexPath.row; UIAlertView *menu = [[[UIAlertView alloc] initWithTitle:VSL(@"Сообщение", @"Message") message:nil delegate:self cancelButtonTitle:VSL(@"Закрыть", @"Close") otherButtonTitles:VSL(@"Скопировать текст", @"Copy text"), VSL(@"Сведения", @"Details"), nil] autorelease]; menu.tag = 601; [menu show]; }

- (BOOL)textFieldShouldReturn:(UITextField *)textField { [self sendText]; return NO; }
- (BOOL)textFieldShouldClear:(UITextField *)textField {
    if (![textField.text length]) return YES;
    UIAlertView *prompt = [[[UIAlertView alloc] initWithTitle:VSL(@"Очистить сообщение?", @"Clear the message?") message:VSL(@"Фото останутся прикреплёнными.", @"Attached images will remain.") delegate:self cancelButtonTitle:VSL(@"Отмена", @"Cancel") otherButtonTitles:VSL(@"Очистить", @"Clear"), nil] autorelease];
    prompt.tag = 501; [prompt show]; return NO;
}
- (void)showFullEditor {
    VSMessageEditorViewController *editor = [[[VSMessageEditorViewController alloc] initWithTitle:VSL(@"Сообщение", @"Message") text:self.input.text confirmTitle:VSL(@"Закрыть", @"Close") applyLive:YES change:^(NSString *text) { self.input.text = text; [self draftChanged]; } completion:^(BOOL accepted, NSString *text) { self.input.text = text; [self saveDraftNow]; }] autorelease];
    UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:editor] autorelease]; [self presentViewController:navigation animated:YES completion:nil];
}
- (void)showTranscriptEditor:(NSString *)transcript {
    self.activity.text = VSL(@"Текст готов: проверьте и вставьте.", @"Text is ready: review and insert it.");
    VSMessageEditorViewController *editor = [[[VSMessageEditorViewController alloc] initWithTitle:VSL(@"Текст диктовки", @"Dictated text") text:transcript confirmTitle:VSL(@"Вставить", @"Insert") applyLive:NO change:nil completion:^(BOOL accepted, NSString *text) {
        if (!accepted) { self.activity.text = VSL(@"Диктовка отменена.", @"Dictation cancelled."); return; }
        NSString *existing = self.input.text ?: @""; NSString *separator = [existing length] && ![[existing substringFromIndex:[existing length] - 1] isEqualToString:@" "] ? @" " : @"";
        self.input.text = [existing stringByAppendingFormat:@"%@%@", separator, text]; [self saveDraftNow]; self.activity.text = VSL(@"Текст диктовки вставлен.", @"Dictated text inserted.");
    }] autorelease];
    UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:editor] autorelease]; [self presentViewController:navigation animated:YES completion:nil];
}
- (void)sendText {
    NSString *text = [self.input.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ((![text length] && ![self.pendingImages count]) || self.sending) return;
    [self hideRetry];
    if (![self.pendingRequestId length]) self.pendingRequestId = [[NSUUID UUID] UUIDString];
    [self saveDraftNow]; self.sending = YES; self.input.enabled = NO;
    self.activity.text = VSL(@"Отправка...", @"Sending...");
    NSString *threadPath = [[self threadId] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *path = [NSString stringWithFormat:@"/api/threads/%@/turns", threadPath];
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    if ([text length]) [body setObject:text forKey:@"text"];
    [body setObject:self.pendingRequestId forKey:@"clientRequestId"];
    NSMutableArray *images = [NSMutableArray array];
    for (NSData *data in self.pendingImages) [images addObject:VSBase64(data)];
    if ([images count]) [body setObject:images forKey:@"imagesBase64"];
    NSString *cwd = VSString([self.thread objectForKey:@"cwd"], @"");
    if ([cwd length]) [body setObject:cwd forKey:@"cwd"];

    BOOL hasOverride = [self.selectedModel length] || [self.selectedEffort length] || ![self.selectedApprovalMode isEqual:@"inherit"];
    NSMutableDictionary *override = [NSMutableDictionary dictionaryWithObject:(hasOverride ? @"next_turn" : @"inherit") forKey:@"mode"];
    if ([self.selectedModel length]) [override setObject:self.selectedModel forKey:@"model"];
    if ([self.selectedEffort length]) [override setObject:self.selectedEffort forKey:@"reasoningEffort"];
    if ([self.selectedApprovalMode isEqual:@"auto"]) {
        [override setObject:@"on-request" forKey:@"approvalPolicy"]; [override setObject:@"auto_review" forKey:@"approvalsReviewer"];
    } else if ([self.selectedApprovalMode isEqual:@"never"]) {
        [override setObject:@"never" forKey:@"approvalPolicy"]; [override setObject:@"user" forKey:@"approvalsReviewer"];
    } else if ([self.selectedApprovalMode isEqual:@"ask"]) {
        [override setObject:@"on-request" forKey:@"approvalPolicy"]; [override setObject:@"user" forKey:@"approvalsReviewer"];
    }
    NSString *overridePath = [NSString stringWithFormat:@"/api/threads/%@/overrides", threadPath];
    [[VSBridgeClient sharedClient] postPath:overridePath body:override completion:^(NSDictionary *ignored, NSError *overrideError) {
        if (overrideError) { self.sending = NO; self.input.enabled = YES; [self showRetry:[overrideError localizedDescription]]; return; }
        [[VSBridgeClient sharedClient] postPath:path body:body completion:^(NSDictionary *response, NSError *error) {
            self.sending = NO; self.input.enabled = YES;
            if (error || ![[response objectForKey:@"ok"] boolValue]) {
                NSString *message = error ? [error localizedDescription] : VSString([response objectForKey:@"error"], VSL(@"Отправка не принята", @"Message was not accepted"));
                self.input.text = text; [self showRetry:message]; [self saveDraftNow]; return;
            }
            [self hideRetry]; self.activity.text = VSL(@"Принято Codex", @"Accepted by Codex"); self.input.text = @""; self.pendingRequestId = @"";
            [self.pendingImages removeAllObjects]; [self rebuildAttachmentBar]; [VSDraftStore removeDraftForThread:[self threadId]];
            self.selectedModel = @""; self.selectedEffort = @""; self.selectedApprovalMode = @"inherit"; [self updateOptionsTitle];
            [self refresh]; [self performSelector:@selector(refresh) withObject:nil afterDelay:1.0]; [self performSelector:@selector(refresh) withObject:nil afterDelay:2.5];
        }];
    }];
}
- (void)setVoiceState:(VSVoiceState)state { _voiceState = state; self.recording = state == VSVoiceStateRecording; self.voiceButton.enabled = state == VSVoiceStateIdle || state == VSVoiceStateRecording; [self.voiceButton setNeedsDisplay]; }
- (void)toggleVoice {
    if (self.voiceState == VSVoiceStateRecording) { [self finishVoice]; return; }
    if (self.voiceState != VSVoiceStateIdle) return;
    if (!self.speechEnabled) { [[[UIAlertView alloc] initWithTitle:VSL(@"\u0420\u0430\u0441\u043f\u043e\u0437\u043d\u0430\u0432\u0430\u043d\u0438\u0435 \u0432\u044b\u043a\u043b\u044e\u0447\u0435\u043d\u043e", @"Speech recognition is disabled") message:VSL(@"\u0412\u043a\u043b\u044e\u0447\u0438\u0442\u0435 \u0435\u0433\u043e \u0432 \u043c\u0435\u043d\u044e Speech Pack \u043d\u0430 Host.", @"Enable it from the Speech Pack menu on Host.") delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show]; return; }
    NSError *error = nil; AVAudioSession *session = [AVAudioSession sharedInstance]; [session setCategory:AVAudioSessionCategoryRecord error:&error]; [session setActive:YES error:&error];
    NSString *operationId = [[NSUUID UUID] UUIDString]; NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"vibeslopik-voice-%@.wav", operationId]]];
    NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kAudioFormatLinearPCM], AVFormatIDKey, [NSNumber numberWithFloat:16000.0], AVSampleRateKey, [NSNumber numberWithInt:1], AVNumberOfChannelsKey, [NSNumber numberWithInt:16], AVLinearPCMBitDepthKey, [NSNumber numberWithBool:NO], AVLinearPCMIsFloatKey, [NSNumber numberWithBool:NO], AVLinearPCMIsBigEndianKey, nil];
    self.recorder = [[[AVAudioRecorder alloc] initWithURL:url settings:settings error:&error] autorelease]; if (error || ![self.recorder prepareToRecord]) { self.activity.text = VSL(@"\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043d\u0430\u0447\u0430\u0442\u044c \u0437\u0430\u043f\u0438\u0441\u044c: \u043c\u0438\u043a\u0440\u043e\u0444\u043e\u043d \u043d\u0435\u0434\u043e\u0441\u0442\u0443\u043f\u0435\u043d", @"Could not record: microphone is unavailable"); [self setVoiceState:VSVoiceStateIdle]; return; }
    self.voiceOperationId = operationId; self.recordingURL = url; self.recorder.delegate = self; [self.recorder record]; [self setVoiceState:VSVoiceStateRecording]; self.activity.text = VSL(@"\u0417\u0430\u043f\u0438\u0441\u044c. \u0413\u043e\u0432\u043e\u0440\u0438\u0442\u0435; \u043d\u0430\u0436\u043c\u0438\u0442\u0435 \u043c\u0438\u043a\u0440\u043e\u0444\u043e\u043d, \u043a\u043e\u0433\u0434\u0430 \u0437\u0430\u043a\u043e\u043d\u0447\u0438\u0442\u0435.", @"Recording. Speak, then tap the microphone again.");
}
- (void)finishVoice { [self setVoiceState:VSVoiceStateFinishing]; self.activity.text = VSL(@"\u0417\u0430\u0432\u0435\u0440\u0448\u0430\u044e \u0437\u0430\u043f\u0438\u0441\u044c...", @"Finishing recording..."); [self.recorder stop]; }
- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)success {
    NSString *operationId = [[self.voiceOperationId copy] autorelease]; NSURL *url = [[self.recordingURL retain] autorelease]; NSData *data = success ? [NSData dataWithContentsOfURL:url] : nil;
    if (![data length]) { self.activity.text = VSL(@"\u0417\u0430\u043f\u0438\u0441\u044c \u043f\u0443\u0441\u0442\u0430 \u0438\u043b\u0438 \u043c\u0438\u043a\u0440\u043e\u0444\u043e\u043d \u043d\u0435\u0434\u043e\u0441\u0442\u0443\u043f\u0435\u043d.", @"Recording is empty or microphone is unavailable."); [self setVoiceState:VSVoiceStateIdle]; return; }
    [self setVoiceState:VSVoiceStateTranscribing]; self.activity.text = VSL(@"\u0420\u0430\u0441\u043f\u043e\u0437\u043d\u0430\u044e \u043d\u0430 \u043a\u043e\u043c\u043f\u044c\u044e\u0442\u0435\u0440\u0435...", @"Transcribing on your computer...");
    [[VSBridgeClient sharedClient] postPath:@"/api/speech/transcriptions" body:[NSDictionary dictionaryWithObjectsAndKeys:VSBase64(data), @"audioBase64", @"wav", @"format", nil] completion:^(NSDictionary *response, NSError *error) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        if (![operationId isEqual:self.voiceOperationId]) return;
        [self setVoiceState:VSVoiceStateIdle];
        if (error || ![[response objectForKey:@"ok"] boolValue]) { self.activity.text = error ? [NSString stringWithFormat:VSL(@"Ошибка распознавания: %@", @"Recognition error: %@"), [error localizedDescription]] : VSString([response objectForKey:@"error"], VSL(@"Не удалось распознать голос", @"Speech could not be recognized")); return; }
        NSString *transcript = VSString([response objectForKey:@"text"], @""); if (![transcript length]) { self.activity.text = VSL(@"Речь не распознана.", @"No speech was recognized."); return; }
        [self showTranscriptEditor:transcript];
    }];
}
- (void)showAttachmentNote { if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) return; UIImagePickerController *picker = [[[UIImagePickerController alloc] init] autorelease]; picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary; picker.delegate = self; [self presentViewController:picker animated:YES completion:nil]; }
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info { UIImage *image = [info objectForKey:UIImagePickerControllerOriginalImage]; CGFloat maximum = 1280.0; CGFloat scale = MIN(1.0, maximum / MAX(image.size.width, image.size.height)); CGSize size = CGSizeMake(MAX(1, floor(image.size.width * scale)), MAX(1, floor(image.size.height * scale))); UIGraphicsBeginImageContextWithOptions(size, YES, 1.0); [image drawInRect:CGRectMake(0, 0, size.width, size.height)]; UIImage *resized = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); NSData *data = UIImageJPEGRepresentation(resized, 0.62); if (data && [self.pendingImages count] < 4) [self.pendingImages addObject:data]; [self saveDraftNow]; self.activity.text = [NSString stringWithFormat:VSL(@"Фото: %lu", @"Images: %lu"), (unsigned long)[self.pendingImages count]]; [self rebuildAttachmentBar]; [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSString *)limitLine:(NSDictionary *)limit title:(NSString *)title { if (!limit) return [NSString stringWithFormat:@"%@: -", title]; NSNumber *used = [limit objectForKey:@"usedPercent"] ?: [limit objectForKey:@"used_percent"]; NSNumber *reset = [limit objectForKey:@"resetsAt"] ?: [limit objectForKey:@"resets_at"]; NSString *when = @"-"; if (reset) { NSTimeInterval value = [reset doubleValue]; if (value > 100000000000) value /= 1000.0; NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease]; [f setDateFormat:@"dd.MM HH:mm"]; when = [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:value]]; } return [NSString stringWithFormat:VSL(@"%@: %@%%, сброс %@", @"%@: %@%%, resets %@"), title, used ?: @"?", when]; }
- (void)showContext { NSDictionary *u = self.usage; NSNumber *used = [u objectForKey:@"totalTokens"] ?: [u objectForKey:@"total_tokens"]; NSNumber *window = [u objectForKey:@"modelContextWindow"] ?: [u objectForKey:@"model_context_window"]; NSString *context = (used && window) ? [NSString stringWithFormat:VSL(@"Контекст: %@ / %@ токенов", @"Context: %@ / %@ tokens"), used, window] : VSL(@"Контекст появится после ответа Codex", @"Context will appear after a Codex response"); NSString *message = [NSString stringWithFormat:@"%@\n\n%@\n%@", context, [self limitLine:[self.limits objectForKey:@"primary"] title:VSL(@"5 ч.", @"5 hr")], [self limitLine:[self.limits objectForKey:@"secondary"] title:VSL(@"7 дн.", @"7 days")]]; [[[UIAlertView alloc] initWithTitle:VSL(@"Статус", @"Status") message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show]; }
- (void)showMenu { UIAlertView *menu = [[[UIAlertView alloc] initWithTitle:VSL(@"\u0414\u0435\u0439\u0441\u0442\u0432\u0438\u044f \u0447\u0430\u0442\u0430", @"Chat actions") message:nil delegate:self cancelButtonTitle:VSL(@"\u0417\u0430\u043a\u0440\u044b\u0442\u044c", @"Close") otherButtonTitles:VSL(@"\u0421\u0432\u043e\u0434\u043a\u0430 \u0447\u0430\u0442\u0430", @"Chat summary"), @"/compact", VSL(@"\u041e\u0431\u043d\u043e\u0432\u0438\u0442\u044c", @"Refresh"), VSL(@"\u041c\u043e\u0434\u0435\u043b\u044c \u0438 \u0440\u0435\u0436\u0438\u043c", @"Model and mode"), VSL(@"\u0421\u043a\u043e\u043f\u0438\u0440\u043e\u0432\u0430\u0442\u044c ID", @"Copy ID"), nil] autorelease]; menu.tag = 201; [menu show]; }
- (void)showChatSummary {
    NSString *cwd = VSString([self.thread objectForKey:@"cwd"], @"—"); NSString *model = VSString([self.activeTurn objectForKey:@"model"], [self.selectedModel length] ? self.selectedModel : VSL(@"наследуется", @"inherited")); NSString *effort = VSString([self.activeTurn objectForKey:@"reasoningEffort"], [self.selectedEffort length] ? [self effortTitle:self.selectedEffort] : VSL(@"по умолчанию", @"default")); NSString *status = VSString([self.activeTurn objectForKey:@"status"], VSL(@"нет активного turn", @"no active turn")); NSDictionary *draft = [VSDraftStore draftForThread:[self threadId]];
    NSString *message = [NSString stringWithFormat:VSL(@"Каталог: %@\nМодель: %@\nМышление: %@\nСтатус: %@\nРазрешение: %@\nЧерновик: %@", @"Directory: %@\nModel: %@\nReasoning: %@\nStatus: %@\nApproval: %@\nDraft: %@"), cwd, model, effort, status, [self.activeApprovalId length] ? VSL(@"ожидается", @"pending") : VSL(@"нет", @"none"), draft ? VSL(@"сохранён", @"saved") : VSL(@"нет", @"none")]; [[[UIAlertView alloc] initWithTitle:VSL(@"Сводка чата", @"Chat summary") message:message delegate:nil cancelButtonTitle:VSL(@"Закрыть", @"Close") otherButtonTitles:nil] show];
}
- (void)showOptionsMenu { UIAlertView *menu = [[[UIAlertView alloc] initWithTitle:VSL(@"\u041c\u043e\u0434\u0435\u043b\u044c \u0438 \u0440\u0435\u0436\u0438\u043c", @"Model and mode") message:nil delegate:self cancelButtonTitle:VSL(@"\u0417\u0430\u043a\u0440\u044b\u0442\u044c", @"Close") otherButtonTitles:VSL(@"\u041c\u043e\u0434\u0435\u043b\u044c", @"Model"), VSL(@"\u0423\u0440\u043e\u0432\u0435\u043d\u044c \u043c\u044b\u0448\u043b\u0435\u043d\u0438\u044f", @"Reasoning effort"), VSL(@"\u041f\u043e\u0434\u0442\u0432\u0435\u0440\u0436\u0434\u0435\u043d\u0438\u044f", @"Approvals"), nil] autorelease]; menu.tag = 401; [menu show]; }
- (void)showModelMenu { [[VSBridgeClient sharedClient] getPath:@"/api/models" completion:^(NSDictionary *response, NSError *error) { if (error) { self.activity.text = [error localizedDescription]; return; } self.models = VSArray([response objectForKey:@"data"]); NSMutableArray *choices = [NSMutableArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:VSL(@"Наследовать ветку", @"Inherit from thread"), @"title", VSL(@"Не менять модель в следующем сообщении", @"Keep the thread model for the next message"), @"subtitle", @"", @"value", [NSNumber numberWithBool:![self.selectedModel length]], @"selected", nil]]; for (NSDictionary *model in self.models) { NSString *value = VSString([model objectForKey:@"model"], VSString([model objectForKey:@"id"], @"")); NSString *subtitle = VSString([model objectForKey:@"description"], VSString([model objectForKey:@"upgradeInfo"], @"")); if ([[model objectForKey:@"hidden"] boolValue]) subtitle = [VSL(@"Другая модель. ", @"Other model. ") stringByAppendingString:subtitle]; [choices addObject:[NSDictionary dictionaryWithObjectsAndKeys:VSString([model objectForKey:@"displayName"], value), @"title", subtitle, @"subtitle", value, @"value", [NSNumber numberWithBool:[value isEqual:self.selectedModel]], @"selected", nil]]; } VSChoiceViewController *picker = [[[VSChoiceViewController alloc] initWithTitle:VSL(@"Модель", @"Model") choices:choices completion:^(NSDictionary *choice) { self.selectedModel = VSString([choice objectForKey:@"value"], @""); self.selectedEffort = @""; [self updateOptionsTitle]; }] autorelease]; [self.navigationController pushViewController:picker animated:YES]; }]; }
- (void)showEffortMenu { NSDictionary *selected = nil; for (NSDictionary *model in self.models) if ([[model objectForKey:@"model"] isEqual:self.selectedModel] || [[model objectForKey:@"id"] isEqual:self.selectedModel]) selected = model; NSArray *items = VSArray([selected objectForKey:@"supportedReasoningEfforts"]); if (![items count]) { [[[UIAlertView alloc] initWithTitle:VSL(@"Уровень мышления", @"Reasoning effort") message:VSL(@"Сначала выберите модель.", @"Choose a model first.") delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show]; return; } NSMutableArray *choices = [NSMutableArray array]; for (NSDictionary *item in items) { NSString *value = VSString([item objectForKey:@"reasoningEffort"], @""); [choices addObject:[NSDictionary dictionaryWithObjectsAndKeys:[self effortTitle:value], @"title", VSString([item objectForKey:@"description"], @""), @"subtitle", value, @"value", [NSNumber numberWithBool:[value isEqual:self.selectedEffort]], @"selected", nil]]; } VSChoiceViewController *picker = [[[VSChoiceViewController alloc] initWithTitle:VSL(@"Интеллект", @"Reasoning") choices:choices completion:^(NSDictionary *choice) { self.selectedEffort = VSString([choice objectForKey:@"value"], @""); [self updateOptionsTitle]; }] autorelease]; [self.navigationController pushViewController:picker animated:YES]; }
- (void)showApprovalMenu { UIAlertView *menu = [[[UIAlertView alloc] initWithTitle:VSL(@"\u041f\u043e\u0434\u0442\u0432\u0435\u0440\u0436\u0434\u0435\u043d\u0438\u044f", @"Approvals") message:nil delegate:self cancelButtonTitle:VSL(@"\u0417\u0430\u043a\u0440\u044b\u0442\u044c", @"Close") otherButtonTitles:VSL(@"\u0421\u043f\u0440\u0430\u0448\u0438\u0432\u0430\u0442\u044c \u043c\u0435\u043d\u044f", @"Ask me"), VSL(@"\u0410\u0432\u0442\u043e\u043f\u0440\u043e\u0432\u0435\u0440\u043a\u0430", @"Auto review"), VSL(@"\u0411\u0435\u0437 \u0437\u0430\u043f\u0440\u043e\u0441\u043e\u0432", @"No prompts"), nil] autorelease]; menu.tag = 404; [menu show]; }
- (void)showPendingApproval { if (![self.activeApprovalId length]) return; NSString *escaped = [[self threadId] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]; [[VSBridgeClient sharedClient] getPath:[NSString stringWithFormat:@"/api/approvals?threadId=%@", escaped] completion:^(NSDictionary *response, NSError *error) { NSArray *items = VSArray([response objectForKey:@"data"]); if (error || ![items count]) { self.activeApprovalId = nil; self.approvalButton.hidden = YES; self.activity.hidden = NO; return; } NSDictionary *approval = [items objectAtIndex:0]; NSString *command = VSString([approval objectForKey:@"command"], VSString([approval objectForKey:@"reason"], VSL(@"Codex просит разрешение", @"Codex requests permission"))); UIAlertView *prompt = [[[UIAlertView alloc] initWithTitle:VSL(@"Требуется разрешение", @"Permission required") message:command delegate:self cancelButtonTitle:VSL(@"Отклонить", @"Decline") otherButtonTitles:VSL(@"Разрешить", @"Allow"), VSL(@"На сессию", @"For session"), nil] autorelease]; prompt.tag = 301; [prompt show]; }]; }
- (void)respondToApproval:(NSString *)decision { NSString *approvalId = [[self.activeApprovalId copy] autorelease]; if (![approvalId length]) return; NSString *path = [NSString stringWithFormat:@"/api/approvals/%@", [approvalId stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]; [[VSBridgeClient sharedClient] postPath:path body:[NSDictionary dictionaryWithObject:decision forKey:@"decision"] completion:^(NSDictionary *response, NSError *error) { self.activeApprovalId = nil; self.approvalButton.hidden = YES; self.activity.hidden = NO; self.activity.text = error ? [error localizedDescription] : VSL(@"\u0420\u0435\u0448\u0435\u043d\u0438\u0435 \u043e\u0442\u043f\u0440\u0430\u0432\u043b\u0435\u043d\u043e", @"Decision sent"); }]; }
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index {
    if (alert.tag == 301) { [self respondToApproval:index == alert.cancelButtonIndex ? @"decline" : (index == 2 ? @"acceptForSession" : @"accept")]; return; }
    if (alert.tag == 501) { if (index != alert.cancelButtonIndex) { self.input.text = @""; [self saveDraftNow]; } return; }
    if (alert.tag == 601) { if (index == 1 && self.selectedMessageIndex < [self.messages count]) [UIPasteboard generalPasteboard].string = VSString([[self.messages objectAtIndex:self.selectedMessageIndex] objectForKey:@"text"], @""); else if (index == 2) [self showMessageDetailsAtIndex:self.selectedMessageIndex]; return; }
    if (index == alert.cancelButtonIndex) return;
    if (alert.tag == 201) {
        if (index == 1) [self showChatSummary];
        else if (index == 2) { self.input.text = @"/compact"; [self sendText]; }
        else if (index == 3) [self refresh];
        else if (index == 4) [self showOptionsMenu];
        else if (index == 5) [UIPasteboard generalPasteboard].string = [self threadId];
    } else if (alert.tag == 401) {
        if (index == 1) [self showModelMenu]; else if (index == 2) [self showEffortMenu]; else if (index == 3) [self showApprovalMenu];
    } else if (alert.tag == 402) {
        if (index == 1) { self.selectedModel = @""; self.selectedEffort = @""; }
        else { NSInteger modelIndex = index - 2; if (modelIndex >= 0 && modelIndex < [self.visibleModels count]) { NSDictionary *model = [self.visibleModels objectAtIndex:modelIndex]; self.selectedModel = VSString([model objectForKey:@"model"], VSString([model objectForKey:@"id"], @"")); self.selectedEffort = VSString([model objectForKey:@"defaultReasoningEffort"], @""); } }
        [self saveOptions];
    } else if (alert.tag == 403) {
        NSInteger effortIndex = index - 1; if (effortIndex >= 0 && effortIndex < [self.visibleEfforts count]) self.selectedEffort = VSString([[self.visibleEfforts objectAtIndex:effortIndex] objectForKey:@"reasoningEffort"], @""); [self saveOptions];
    } else if (alert.tag == 404) {
        self.selectedApprovalMode = index == 1 ? @"ask" : (index == 2 ? @"auto" : @"never"); [self saveOptions];
    }
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [_thread release]; [_messages release]; [_table release]; [_input release]; [_activity release]; [_pollTimer release]; [_usage release]; [_limits release]; [_limitsUpdatedAt release]; [_pendingImages release]; [_models release]; [_visibleModels release]; [_visibleEfforts release]; [_selectedModel release]; [_selectedEffort release]; [_selectedApprovalMode release]; [_activeApprovalId release]; [_optionsButton release]; [_recorder release]; [_recordingURL release]; [_voiceOperationId release]; [_voiceButton release]; [_retryButton release]; [_approvalButton release]; [_activeTurn release]; [_pendingRequestId release]; [super dealloc]; }
@end

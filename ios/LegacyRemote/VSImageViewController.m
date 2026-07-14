#import "VSImageViewController.h"
#import "VSBridgeClient.h"
#import "VSMediaCache.h"
#import "VSLocalization.h"

@interface VSImageViewController ()
@property (nonatomic, retain) NSDictionary *media;
@property (nonatomic, retain) UIScrollView *scroll;
@property (nonatomic, retain) UIImageView *imageView;
@property (nonatomic, retain) UIActivityIndicatorView *spinner;
@property (nonatomic, retain) NSData *imageData;
@end

@implementation VSImageViewController
- (id)initWithMedia:(NSDictionary *)media { if ((self = [super init])) self.media = media; return self; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = VSL(@"Изображение", @"Image"); self.view.backgroundColor = [UIColor blackColor];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(actions)] autorelease];
    self.navigationItem.rightBarButtonItem.enabled = NO;
    self.scroll = [[[UIScrollView alloc] initWithFrame:self.view.bounds] autorelease];
    self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; self.scroll.delegate = self;
    self.scroll.minimumZoomScale = 1; self.scroll.maximumZoomScale = 4; [self.view addSubview:self.scroll];
    self.imageView = [[[UIImageView alloc] initWithFrame:self.scroll.bounds] autorelease];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit; self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.scroll addSubview:self.imageView];
    self.spinner = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge] autorelease];
    self.spinner.center = self.view.center; self.spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:self.spinner]; [self loadOriginal];
}
- (void)loadOriginal {
    NSString *key = [NSString stringWithFormat:@"%@-original", [self.media objectForKey:@"id"]];
    NSData *cached = [VSMediaCache dataForKey:key]; if (cached) { [self showData:cached]; return; }
    [self.spinner startAnimating];
    [[VSBridgeClient sharedClient] getPath:[self.media objectForKey:@"originalPath"] completion:^(NSDictionary *response, NSError *error) {
        [self.spinner stopAnimating];
        if (error) { [[[UIAlertView alloc] initWithTitle:VSL(@"Ошибка загрузки", @"Download failed") message:[error localizedDescription] delegate:nil cancelButtonTitle:VSL(@"Закрыть", @"Close") otherButtonTitles:nil] show]; return; }
        NSData *data = [VSMediaCache decodeBase64:[response objectForKey:@"base64"]];
        if (data) { [VSMediaCache storeData:data forKey:key]; [self showData:data]; }
    }];
}
- (void)showData:(NSData *)data { UIImage *image = [UIImage imageWithData:data]; if (!image) return; self.imageData = data; self.imageView.image = image; self.navigationItem.rightBarButtonItem.enabled = YES; }
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return self.imageView; }
- (void)actions { if (!self.imageView.image) return; UIActivityViewController *controller = [[[UIActivityViewController alloc] initWithActivityItems:[NSArray arrayWithObject:self.imageView.image] applicationActivities:nil] autorelease]; [self presentViewController:controller animated:YES completion:nil]; }
- (void)dealloc { [_media release]; [_scroll release]; [_imageView release]; [_spinner release]; [_imageData release]; [super dealloc]; }
@end

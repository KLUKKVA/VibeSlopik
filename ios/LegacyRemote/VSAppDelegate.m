#import "VSAppDelegate.h"
#import "VSSessionsViewController.h"
#import "VSSettingsViewController.h"
#import "VSLocalization.h"

@implementation VSAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    VSSessionsViewController *sessions = [[[VSSessionsViewController alloc] initWithStyle:UITableViewStylePlain] autorelease];
    UINavigationController *sessionsNav = [[[UINavigationController alloc] initWithRootViewController:sessions] autorelease];
    sessionsNav.navigationBar.tintColor = [UIColor colorWithRed:0.12 green:0.29 blue:0.43 alpha:1.0];
    sessionsNav.tabBarItem = [[[UITabBarItem alloc] initWithTitle:VSL(@"Кодекс", @"Codex") image:[UIImage imageNamed:@"TabCodex.png"] tag:0] autorelease];
    VSSettingsViewController *settings = [[[VSSettingsViewController alloc] initWithStyle:UITableViewStyleGrouped] autorelease];
    UINavigationController *settingsNav = [[[UINavigationController alloc] initWithRootViewController:settings] autorelease];
    settingsNav.navigationBar.tintColor = [UIColor colorWithRed:0.12 green:0.29 blue:0.43 alpha:1.0];
    settingsNav.tabBarItem = [[[UITabBarItem alloc] initWithTitle:VSL(@"Настройки", @"Settings") image:[UIImage imageNamed:@"TabSettings.png"] tag:1] autorelease];
    UITabBarController *tabs = [[[UITabBarController alloc] init] autorelease]; tabs.viewControllers = [NSArray arrayWithObjects:sessionsNav, settingsNav, nil]; tabs.tabBar.selectedImageTintColor = [UIColor colorWithRed:0.15 green:0.65 blue:0.88 alpha:1.0]; self.window.rootViewController = tabs; [self.window makeKeyAndVisible]; return YES;
}
- (void)dealloc { [_window release]; [super dealloc]; }
@end

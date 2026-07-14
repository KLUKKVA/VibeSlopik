#import "VSProjectViewController.h"
#import "VSBridgeClient.h"
#import "VSChatViewController.h"
#import "VSUtilities.h"
#import "VSDraftStore.h"
#import "VSLocalization.h"

@interface VSProjectViewController ()
@property (nonatomic, retain) NSDictionary *project;
@property (nonatomic, retain) NSArray *threads;
@end
@implementation VSProjectViewController
- (id)initWithProject:(NSDictionary *)project { if ((self = [super initWithStyle:UITableViewStylePlain])) { self.project = project; self.threads = [NSArray array]; } return self; }
- (void)viewDidLoad { [super viewDidLoad]; self.title = VSString([self.project objectForKey:@"name"], VSL(@"\u041f\u0440\u043e\u0435\u043a\u0442", @"Project")); self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(newThread)] autorelease]; [self refresh]; }
- (void)refresh { NSString *path = [VSString([self.project objectForKey:@"path"], @"") stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]; [[VSBridgeClient sharedClient] getPath:[NSString stringWithFormat:@"/api/threads?cwd=%@", path] completion:^(NSDictionary *response, NSError *error) { if (!error && [[response objectForKey:@"ok"] boolValue]) self.threads = VSArray([response objectForKey:@"data"]); [self.tableView reloadData]; }]; }
- (void)newThread { NSDictionary *body = [NSDictionary dictionaryWithObject:([self.project objectForKey:@"path"] ?: @"") forKey:@"cwd"]; [[VSBridgeClient sharedClient] postPath:@"/api/threads" body:body completion:^(NSDictionary *response, NSError *error) { NSDictionary *thread = [response objectForKey:@"thread"] ?: response; if (!error && [[response objectForKey:@"ok"] boolValue]) [self.navigationController pushViewController:[[[VSChatViewController alloc] initWithThread:thread] autorelease] animated:YES]; }]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return MAX((NSInteger)[self.threads count], 1); }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { static NSString *cellId = @"ProjectThread"; UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId]; if (!cell) cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId] autorelease]; cell.imageView.image = nil; if (![self.threads count]) { cell.textLabel.text = VSL(@"\u0412 \u044d\u0442\u043e\u043c \u043f\u0440\u043e\u0435\u043a\u0442\u0435 \u043d\u0435\u0442 \u0447\u0430\u0442\u043e\u0432", @"No chats in this project"); cell.detailTextLabel.text = VSL(@"\u041d\u0430\u0436\u043c\u0438\u0442\u0435 +", @"Tap +"); } else { NSDictionary *thread = [self.threads objectAtIndex:indexPath.row]; cell.imageView.image = VSInterfaceIcon(@"chat"); cell.textLabel.text = VSString([thread objectForKey:@"name"], VSString([thread objectForKey:@"preview"], VSL(@"\u0427\u0430\u0442", @"Chat"))); BOOL draft = [VSDraftStore draftForThread:VSString([thread objectForKey:@"id"], @"")] != nil; cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@", draft ? VSL(@"\u0427\u0435\u0440\u043d\u043e\u0432\u0438\u043a \u2022 ", @"Draft \u2022 ") : @"", VSString([thread objectForKey:@"preview"], @"Codex")]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; } return cell; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { if ([self.threads count]) [self.navigationController pushViewController:[[[VSChatViewController alloc] initWithThread:[self.threads objectAtIndex:indexPath.row]] autorelease] animated:YES]; }
- (void)dealloc { [_project release]; [_threads release]; [super dealloc]; }
@end

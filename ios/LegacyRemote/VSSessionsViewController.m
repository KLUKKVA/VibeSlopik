#import "VSSessionsViewController.h"
#import "VSBridgeClient.h"
#import "VSChatViewController.h"
#import "VSProjectViewController.h"
#import "VSUtilities.h"
#import "VSDraftStore.h"
#import "VSLocalization.h"

@interface VSSessionsViewController ()
@property (nonatomic, retain) NSArray *projects;
@property (nonatomic, retain) NSArray *recentThreads;
@property (nonatomic, copy) NSString *connectionText;
@property (nonatomic, assign) BOOL loading;
@end

@implementation VSSessionsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = VSL(@"\u041a\u043e\u0434\u0435\u043a\u0441", @"Codex");
    self.projects = [NSArray array];
    self.recentThreads = [NSArray array];
    self.connectionText = VSL(@"\u041f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u0435...", @"Connecting...");
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)] autorelease];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(newThread)] autorelease];
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh]; }

- (void)refresh {
    if (self.loading) return;
    self.loading = YES;
    self.connectionText = VSL(@"\u041e\u0431\u043d\u043e\u0432\u043b\u0435\u043d\u0438\u0435...", @"Refreshing...");
    self.navigationItem.leftBarButtonItem.enabled = NO;
    [self.tableView reloadData];
    [[VSBridgeClient sharedClient] getPath:@"/api/home" completion:^(NSDictionary *response, NSError *error) {
        if (error || ![[response objectForKey:@"ok"] boolValue]) {
            self.connectionText = error ? [error localizedDescription] : VSL(@"Bridge \u043d\u0435 \u043e\u0442\u0432\u0435\u0447\u0430\u0435\u0442", @"Bridge is not responding");
        } else {
            NSString *computer = VSString([response objectForKey:@"computer"], @"Codex Host");
            self.connectionText = [NSString stringWithFormat:VSL(@"%@ \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d", @"%@ connected"), computer];
            self.projects = VSArray([response objectForKey:@"projects"]);
            self.recentThreads = VSArray([response objectForKey:@"recentThreads"]);
        }
        self.loading = NO;
        self.navigationItem.leftBarButtonItem.enabled = YES;
        [self.tableView reloadData];
    }];
}

- (void)newThread {
    if (self.loading) return;
    UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:VSL(@"Выберите проект для нового чата", @"Choose a project for the new chat") delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil] autorelease];
    sheet.tag = 701;
    for (NSDictionary *project in self.projects) [sheet addButtonWithTitle:VSString([project objectForKey:@"name"], VSL(@"Проект", @"Project"))];
    [sheet addButtonWithTitle:VSL(@"Отмена", @"Cancel")];
    sheet.cancelButtonIndex = [self.projects count];
    [sheet showInView:self.view];
}
- (void)createThreadInProject:(NSDictionary *)project {
    if (self.loading) return; self.loading = YES; self.navigationItem.rightBarButtonItem.enabled = NO;
    [[VSBridgeClient sharedClient] postPath:@"/api/threads" body:[NSDictionary dictionaryWithObject:VSString([project objectForKey:@"path"], @"") forKey:@"cwd"] completion:^(NSDictionary *response, NSError *error) {
        NSDictionary *thread = [response objectForKey:@"thread"] ?: response;
        self.loading = NO;
        self.navigationItem.rightBarButtonItem.enabled = YES;
        if (!error && [[response objectForKey:@"ok"] boolValue] && [thread objectForKey:@"id"]) {
            [self.navigationController pushViewController:[[[VSChatViewController alloc] initWithThread:thread] autorelease] animated:YES];
        } else {
            NSString *message = error ? [error localizedDescription] : VSL(@"\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u0441\u043e\u0437\u0434\u0430\u0442\u044c \u0447\u0430\u0442", @"Could not create the chat");
            [[[UIAlertView alloc] initWithTitle:VSL(@"\u041e\u0448\u0438\u0431\u043a\u0430", @"Error") message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }
    }];
}
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)index {
    if (actionSheet.tag != 701 || index == actionSheet.cancelButtonIndex) return;
    if (index >= 0 && index < [self.projects count]) { [self createThreadInProject:[self.projects objectAtIndex:index]]; return; }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return VSL(@"\u041a\u043e\u043c\u043f\u044c\u044e\u0442\u0435\u0440", @"Computer");
    if (section == 1) return VSL(@"\u041f\u0440\u043e\u0435\u043a\u0442\u044b", @"Projects");
    return VSL(@"\u041d\u0435\u0434\u0430\u0432\u043d\u0438\u0435 \u0447\u0430\u0442\u044b", @"Recent chats");
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    return MAX((NSInteger)(section == 1 ? [self.projects count] : [self.recentThreads count]), 1);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"HomeCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier] autorelease];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.image = nil;
    if (indexPath.section == 0) { cell.textLabel.text = self.connectionText; cell.detailTextLabel.text = @"Codex app-server"; return cell; }
    NSArray *items = indexPath.section == 1 ? self.projects : self.recentThreads;
    if (![items count]) { cell.textLabel.text = VSL(@"\u041f\u043e\u043a\u0430 \u043f\u0443\u0441\u0442\u043e", @"Nothing here yet"); cell.detailTextLabel.text = VSL(@"\u0421\u043e\u0437\u0434\u0430\u0439\u0442\u0435 \u0447\u0430\u0442 \u043a\u043d\u043e\u043f\u043a\u043e\u0439 +", @"Create a chat with the + button"); return cell; }
    NSDictionary *item = [items objectAtIndex:indexPath.row];
    cell.imageView.image = VSInterfaceIcon(indexPath.section == 1 ? @"folder" : @"chat");
    cell.textLabel.text = VSString([item objectForKey:@"name"], VSString([item objectForKey:@"preview"], VSString([item objectForKey:@"id"], VSL(@"\u0427\u0430\u0442", @"Chat"))));
    if (indexPath.section == 1) cell.detailTextLabel.text = [NSString stringWithFormat:VSL(@"%@ \u2022 %@ \u0447\u0430\u0442\u043e\u0432", @"%@ \u2022 %@ chats"), VSString([item objectForKey:@"path"], @""), VSString([item objectForKey:@"threadCount"], @"0")];
    else { BOOL draft = [VSDraftStore draftForThread:VSString([item objectForKey:@"id"], @"")] != nil; cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@", draft ? VSL(@"\u0427\u0435\u0440\u043d\u043e\u0432\u0438\u043a \u2022 ", @"Draft \u2022 ") : @"", VSString([item objectForKey:@"cwd"], @"Codex")]; }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && [self.projects count]) [self.navigationController pushViewController:[[[VSProjectViewController alloc] initWithProject:[self.projects objectAtIndex:indexPath.row]] autorelease] animated:YES];
    if (indexPath.section == 2 && [self.recentThreads count]) [self.navigationController pushViewController:[[[VSChatViewController alloc] initWithThread:[self.recentThreads objectAtIndex:indexPath.row]] autorelease] animated:YES];
}
- (void)dealloc { [_projects release]; [_recentThreads release]; [_connectionText release]; [super dealloc]; }
@end

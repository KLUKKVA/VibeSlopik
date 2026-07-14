#import "VSChoiceViewController.h"

@interface VSChoiceViewController ()
@property (nonatomic, retain) NSArray *choices;
@property (nonatomic, copy) VSChoiceCompletion completion;
@end

@implementation VSChoiceViewController
- (id)initWithTitle:(NSString *)title choices:(NSArray *)choices completion:(VSChoiceCompletion)completion { if ((self = [super initWithStyle:UITableViewStyleGrouped])) { self.title = title; self.choices = choices; self.completion = completion; } return self; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.choices count]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { static NSString *identifier = @"Choice"; UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier]; if (!cell) cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier] autorelease]; NSDictionary *choice = [self.choices objectAtIndex:indexPath.row]; cell.textLabel.text = [choice objectForKey:@"title"]; cell.detailTextLabel.text = [choice objectForKey:@"subtitle"]; cell.textLabel.numberOfLines = 1; cell.detailTextLabel.numberOfLines = 2; cell.accessoryType = [[choice objectForKey:@"selected"] boolValue] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone; return cell; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { NSDictionary *choice = [self.choices objectAtIndex:indexPath.row]; return [[choice objectForKey:@"subtitle"] length] ? 58 : 44; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { NSDictionary *choice = [self.choices objectAtIndex:indexPath.row]; if (self.completion) self.completion(choice); [self.navigationController popViewControllerAnimated:YES]; }
- (void)dealloc { [_choices release]; [_completion release]; [super dealloc]; }
@end

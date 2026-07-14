#import "VSSettingsViewController.h"
#import "VSBridgeClient.h"
#import "VSDraftStore.h"
#import "VSMediaCache.h"
#import "VSLocalization.h"

@interface VSSettingsViewController ()
@property (nonatomic, retain) UITextField *urlField;
@property (nonatomic, retain) UITextField *tokenField;
@end

@implementation VSSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = VSL(@"Настройки", @"Settings");
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:VSL(@"Сохранить", @"Save") style:UIBarButtonItemStyleBordered target:self action:@selector(save)] autorelease];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0 || section == 2) return 2;
    if (section == 1) return 5;
    return 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"VPS Relay";
    if (section == 1) return VSL(@"Хранилище", @"Storage");
    if (section == 2) return VSL(@"Диагностика", @"Diagnostics");
    if (section == 3) return VSL(@"Язык", @"Language");
    return VSL(@"Помощь", @"Help");
}

- (UITableViewCell *)connectionCell:(NSIndexPath *)indexPath {
    static NSString *identifier = @"ConnectionField";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.backgroundColor = [UIColor clearColor];
        cell.contentView.backgroundColor = [UIColor clearColor];
        UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(15, 0, 68, 44)] autorelease];
        label.tag = 10; label.font = [UIFont boldSystemFontOfSize:13]; label.backgroundColor = [UIColor clearColor];
        [cell.contentView addSubview:label];
        UITextField *field = [[[UITextField alloc] initWithFrame:CGRectMake(84, 7, 205, 30)] autorelease];
        field.tag = 11; field.borderStyle = UITextBorderStyleNone; field.backgroundColor = [UIColor clearColor];
        field.font = [UIFont systemFontOfSize:14]; field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo; field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.delegate = self; field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cell.contentView addSubview:field];
    }
    UILabel *label = (UILabel *)[cell.contentView viewWithTag:10];
    UITextField *field = (UITextField *)[cell.contentView viewWithTag:11];
    if (indexPath.row == 0) {
        label.text = @"URL"; field.placeholder = @"URL VPS Relay";
        field.secureTextEntry = NO; field.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"BridgeURL"];
        self.urlField = field;
    } else {
        label.text = VSL(@"Токен", @"Token"); field.placeholder = VSL(@"Токен из Host", @"Token from Host");
        field.secureTextEntry = YES; field.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"BridgeToken"];
        self.tokenField = field;
    }
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return [self connectionCell:indexPath];
    UITableViewCell *cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil] autorelease];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (indexPath.section == 1) {
        NSDictionary *stats = [VSDraftStore statistics]; NSDictionary *media = [VSMediaCache statistics];
        double draftMB = [[stats objectForKey:@"bytes"] unsignedLongLongValue] / 1048576.0;
        if (indexPath.row == 0) {
            cell.textLabel.text = VSL(@"Черновики на iPhone", @"Drafts on iPhone");
            cell.detailTextLabel.text = [NSString stringWithFormat:VSL(@"%@ чатов, %@ фото, %.1f МБ из 50 МБ", @"%@ chats, %@ photos, %.1f MB of 50 MB"), [stats objectForKey:@"count"], [stats objectForKey:@"images"], draftMB];
            cell.accessoryType = UITableViewCellAccessoryNone;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = VSL(@"Очистить черновики", @"Clear drafts");
            cell.detailTextLabel.text = VSL(@"Текст и копии фото на iPhone", @"Text and temporary photo copies on iPhone");
        } else if (indexPath.row == 2) {
            cell.textLabel.text = VSL(@"Автозагрузка миниатюр", @"Load thumbnails automatically");
            cell.detailTextLabel.text = VSL(@"Выключите для медленной сети", @"Disable for slow connections");
            UISwitch *toggle = [[[UISwitch alloc] init] autorelease]; toggle.on = [VSMediaCache autoDownload];
            [toggle addTarget:self action:@selector(mediaAutoChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle; cell.accessoryType = UITableViewCellAccessoryNone;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = VSL(@"Очистить медиа-кэш", @"Clear media cache");
            cell.detailTextLabel.text = [NSString stringWithFormat:VSL(@"%@ файлов, %.1f МБ из 50 МБ", @"%@ files, %.1f MB of 50 MB"), [media objectForKey:@"count"], [[media objectForKey:@"bytes"] unsignedLongLongValue] / 1048576.0];
        } else {
            cell.textLabel.text = VSL(@"Очистить кэш Host", @"Clear Host cache");
            cell.detailTextLabel.text = VSL(@"Временные файлы на компьютере", @"Temporary files on your computer");
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            NSDate *date = [[NSUserDefaults standardUserDefaults] objectForKey:@"VSLastBridgeSuccess"];
            cell.textLabel.text = VSL(@"Состояние связи", @"Connection status");
            cell.detailTextLabel.text = date ? [NSString stringWithFormat:VSL(@"Последний успех: %@", @"Last success: %@"), date] : VSL(@"Ещё не проверялась", @"Not checked yet");
        } else {
            cell.textLabel.text = VSL(@"Скопировать отчёт", @"Copy diagnostic report");
            cell.detailTextLabel.text = VSL(@"Без URL, токена, чатов и фото", @"Excludes URL, token, chats and photos");
        }
    } else if (indexPath.section == 3) {
        cell.textLabel.text = VSL(@"Русский", @"English");
        cell.detailTextLabel.text = VSL(@"Нажмите, чтобы выбрать English", @"Tap to choose Russian");
    } else {
        cell.textLabel.text = VSL(@"Как подключиться", @"How to connect");
        cell.detailTextLabel.text = VSL(@"Нажмите для краткой инструкции", @"Tap for a short guide");
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && indexPath.row == 1) {
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:VSL(@"Очистить все черновики?", @"Clear all drafts?") message:VSL(@"Неотправленный текст и копии фото будут удалены.", @"Unsent text and temporary photo copies will be removed.") delegate:self cancelButtonTitle:VSL(@"Отмена", @"Cancel") otherButtonTitles:VSL(@"Очистить", @"Clear"), nil] autorelease];
        alert.tag = 801; [alert show]; return;
    }
    if (indexPath.section == 1 && indexPath.row == 3) {
        [VSMediaCache clear]; [tableView reloadData];
        [[[UIAlertView alloc] initWithTitle:VSL(@"Готово", @"Done") message:VSL(@"Медиа-кэш iPhone очищен.", @"iPhone media cache was cleared.") delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show]; return;
    }
    if (indexPath.section == 1 && indexPath.row == 4) {
        [[VSBridgeClient sharedClient] postPath:@"/api/cache/clear" body:[NSDictionary dictionary] completion:^(NSDictionary *response, NSError *error) {
            [[[UIAlertView alloc] initWithTitle:error ? VSL(@"Ошибка", @"Error") : VSL(@"Кэш Host очищен", @"Host cache cleared") message:error ? [error localizedDescription] : VSL(@"Временные файлы удалены.", @"Temporary files were removed.") delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }]; return;
    }
    if (indexPath.section == 2 && indexPath.row == 0) {
        NSString *error = [[NSUserDefaults standardUserDefaults] stringForKey:@"VSLastBridgeError"] ?: VSL(@"нет", @"none");
        NSString *message = [NSString stringWithFormat:VSL(@"Версия: 1.0.0\nПоследняя ошибка: %@", @"Version: 1.0.0\nLast error: %@"), error];
        [[[UIAlertView alloc] initWithTitle:VSL(@"Состояние связи", @"Connection status") message:message delegate:nil cancelButtonTitle:VSL(@"Закрыть", @"Close") otherButtonTitles:nil] show]; return;
    }
    if (indexPath.section == 2 && indexPath.row == 1) {
        NSDictionary *stats = [VSDraftStore statistics]; NSString *error = [[NSUserDefaults standardUserDefaults] stringForKey:@"VSLastBridgeError"] ?: VSL(@"нет", @"none");
        [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"VibeSlopik 1.0.0\niOS %@\nDrafts: %@\nConnection error: %@", [[UIDevice currentDevice] systemVersion], [stats objectForKey:@"count"], error];
        [[[UIAlertView alloc] initWithTitle:VSL(@"Отчёт скопирован", @"Report copied") message:VSL(@"Секретные данные в отчёт не вошли.", @"The report contains no secrets.") delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show]; return;
    }
    if (indexPath.section == 3) {
        UIAlertView *language = [[[UIAlertView alloc] initWithTitle:@"Language / Язык" message:nil delegate:self cancelButtonTitle:VSL(@"Отмена", @"Cancel") otherButtonTitles:@"Русский", @"English", nil] autorelease];
        language.tag = 901; [language show]; return;
    }
    if (indexPath.section == 4) [[[UIAlertView alloc] initWithTitle:VSL(@"Подключение", @"Connection") message:VSL(@"1. Запустите VibeSlopik Host.\n2. Введите URL VPS Relay и токен Host.\n3. Нажмите «Сохранить».", @"1. Start VibeSlopik Host.\n2. Enter the VPS Relay URL and Host token.\n3. Tap Save.") delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 901 && buttonIndex != alertView.cancelButtonIndex) {
        VSSetLanguage(buttonIndex == 1 ? @"ru" : @"en"); [self.tableView reloadData]; self.title = VSL(@"Настройки", @"Settings");
        [[[UIAlertView alloc] initWithTitle:VSL(@"Язык сохранён", @"Language saved") message:VSL(@"Перезапустите приложение, чтобы обновить все вкладки.", @"Restart the app to update every tab.") delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show]; return;
    }
    if (alertView.tag == 801 && buttonIndex != alertView.cancelButtonIndex) {
        [VSDraftStore clearAll]; [self.tableView reloadData];
        [[[UIAlertView alloc] initWithTitle:VSL(@"Готово", @"Done") message:VSL(@"Черновики и их временные фотографии удалены.", @"Drafts and their temporary photos were removed.") delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return 48; }
- (void)mediaAutoChanged:(UISwitch *)sender { [VSMediaCache setAutoDownload:sender.on]; }
- (void)save {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:(self.urlField.text ?: @"") forKey:@"BridgeURL"]; [defaults setObject:(self.tokenField.text ?: @"") forKey:@"BridgeToken"]; [defaults synchronize];
    [VSBridgeClient sharedClient].baseURL = self.urlField.text; [VSBridgeClient sharedClient].token = self.tokenField.text;
    [[[UIAlertView alloc] initWithTitle:VSL(@"Сохранено", @"Saved") message:VSL(@"Подключение обновлено.", @"Connection settings were updated.") delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}
- (BOOL)textFieldShouldReturn:(UITextField *)textField { [textField resignFirstResponder]; return YES; }
- (void)dealloc { [_urlField release]; [_tokenField release]; [super dealloc]; }
@end

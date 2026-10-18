#import "RXMainController.h"
#import "RXDaemonClient.h"

enum {
    RXSectionStream,
    RXSectionConnect,
    RXSectionQuality,
    RXSectionCount,
};

@interface RXMainController ()
@property (nonatomic, strong) RXDaemonClient *daemon;
@property (nonatomic, strong) NSDictionary *status;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UISegmentedControl *fpsControl;
@property (nonatomic, strong) UISegmentedControl *sizeControl;
@property (nonatomic, strong) UISegmentedControl *bitrateControl;
@end

static NSArray *RXFpsValues(void) { return @[ @15, @24, @30 ]; }
static NSArray *RXBitrateValues(void) { return @[ @1500000, @3000000, @6000000 ]; }

@implementation RXMainController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.title = @"RecTunnelX";
        _daemon = [RXDaemonClient new];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.enabledSwitch = [UISwitch new];
    [self.enabledSwitch addTarget:self action:@selector(enabledChanged) forControlEvents:UIControlEventValueChanged];
    self.fpsControl = [self segmentsWithItems:@[ @"15", @"24", @"30" ] action:@selector(fpsChanged)];
    self.sizeControl = [self segmentsWithItems:@[ @"640x960", @"320x480" ] action:@selector(sizeChanged)];
    self.bitrateControl = [self segmentsWithItems:@[ @"1.5", @"3", @"6" ] action:@selector(bitrateChanged)];
}

- (UISegmentedControl *)segmentsWithItems:(NSArray *)items action:(SEL)action {
    UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:items];
    control.segmentedControlStyle = UISegmentedControlStyleBar;
    control.frame = CGRectMake(0, 0, 170, 30);
    [control addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return control;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(refresh)
                                                userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.timer invalidate];
    self.timer = nil;
}

- (void)refresh {
    [self.daemon fetchStatus:^(NSDictionary *status) {
        self.status = status;
        [self showSettings];
        [self.tableView reloadData];
    }];
}

- (NSDictionary *)settings {
    return self.status[@"settings"];
}

- (void)showSettings {
    NSDictionary *settings = self.settings;
    if (!settings) return;
    self.enabledSwitch.on = [settings[@"enabled"] boolValue];
    NSUInteger fps = [RXFpsValues() indexOfObject:settings[@"fps"]];
    self.fpsControl.selectedSegmentIndex = fps == NSNotFound ? UISegmentedControlNoSegment : (NSInteger)fps;
    self.sizeControl.selectedSegmentIndex = [settings[@"scale"] intValue] == 2 ? 1 : 0;
    NSUInteger bitrate = [RXBitrateValues() indexOfObject:settings[@"bitrate"]];
    self.bitrateControl.selectedSegmentIndex = bitrate == NSNotFound ? UISegmentedControlNoSegment : (NSInteger)bitrate;
}

- (void)send:(NSDictionary *)query {
    [self.daemon control:query completion:^(NSDictionary *result) {
        if (result[@"error"]) {
            [[[UIAlertView alloc] initWithTitle:@"RecTunnelX" message:result[@"error"] delegate:nil
                              cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }
        [self refresh];
    }];
}

- (void)enabledChanged {
    [self send:@{ @"enabled": self.enabledSwitch.on ? @"1" : @"0" }];
}

- (void)fpsChanged {
    [self send:@{ @"fps": [RXFpsValues()[self.fpsControl.selectedSegmentIndex] stringValue] }];
}

- (void)sizeChanged {
    [self send:@{ @"scale": self.sizeControl.selectedSegmentIndex == 1 ? @"2" : @"1" }];
}

- (void)bitrateChanged {
    [self send:@{ @"bitrate": [RXBitrateValues()[self.bitrateControl.selectedSegmentIndex] stringValue] }];
}

// The text of the state row.
- (NSString *)stateText {
    if (!self.status) return @"The daemon does not answer";
    if (self.status[@"error"]) return self.status[@"error"];
    if (![self.settings[@"enabled"] boolValue]) return @"Off";
    int clients = [self.status[@"clients"] intValue];
    if (clients == 0) return @"Waiting for OBS";
    return [NSString stringWithFormat:@"Streaming to %d %@", clients, clients == 1 ? @"client" : @"clients"];
}

- (NSArray *)connectRows {
    int port = [self.status[@"port"] intValue] ?: 7272;
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:@[ @"USB", [NSString stringWithFormat:@"tcp://127.0.0.1:%d", port] ]];
    for (NSDictionary *address in self.status[@"addresses"]) {
        NSString *name = [address[@"interface"] hasPrefix:@"en"] ? @"Wi-Fi" : address[@"interface"];
        [rows addObject:@[ name, [NSString stringWithFormat:@"tcp://%@:%d", address[@"address"], port] ]];
    }
    return rows;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return RXSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
    case RXSectionStream: return 2;
    case RXSectionConnect: return (NSInteger)self.connectRows.count;
    default: return 3;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
    case RXSectionConnect: return @"OBS Media Source input";
    case RXSectionQuality: return @"Quality";
    default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == RXSectionConnect) {
        return @"In OBS, add a Media Source. Clear \"Local File\" and put an address in \"Input\". "
               @"For USB, run \"iproxy 7272 7272\" on the computer first. Tap an address to copy it.";
    }
    if (section == RXSectionQuality && self.status) {
        double megabytes = [self.status[@"bytes"] doubleValue] / 1e6;
        return [NSString stringWithFormat:@"Sent %@ frames, %.1f MB.", self.status[@"frames"], megabytes];
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (indexPath.section == RXSectionStream) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Stream";
            cell.accessoryView = self.enabledSwitch;
            self.enabledSwitch.enabled = self.status != nil;
        } else {
            cell.textLabel.text = @"State";
            cell.detailTextLabel.text = self.stateText;
        }
    } else if (indexPath.section == RXSectionConnect) {
        NSArray *row = self.connectRows[indexPath.row];
        cell.textLabel.text = row[0];
        cell.detailTextLabel.text = row[1];
        cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    } else {
        NSArray *titles = @[ @"Frames/s", @"Size", @"Mbit/s" ];
        NSArray *views = @[ self.fpsControl, self.sizeControl, self.bitrateControl ];
        cell.textLabel.text = titles[indexPath.row];
        cell.accessoryView = views[indexPath.row];
        ((UIControl *)views[indexPath.row]).enabled = self.status != nil;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != RXSectionConnect) return;
    NSString *address = self.connectRows[indexPath.row][1];
    [UIPasteboard generalPasteboard].string = address;
    [[[UIAlertView alloc] initWithTitle:@"Copied" message:address delegate:nil cancelButtonTitle:@"OK"
                      otherButtonTitles:nil] show];
}

@end

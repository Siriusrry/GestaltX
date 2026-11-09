// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>
#import "ProbeRunner.h"

@interface WalletProbeViewController : UIViewController
@property (nonatomic, strong) UITextField *cardField;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UITextView *reportView;
@property (nonatomic, copy) NSString *lastJSON;
- (void)executeProbeWithCanary:(BOOL)includeCanary cardIDOverride:(nullable NSString *)cardOverride;
@end

@implementation WalletProbeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"WalletProbe (iOS 27.3 Diagnostic)";
    titleLabel.font = [UIFont boldSystemFontOfSize:18.0];

    self.cardField = [[UITextField alloc] init];
    self.cardField.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardField.borderStyle = UITextBorderStyleRoundedRect;
    self.cardField.placeholder = @"Optional Card ID (without .pkpass)";
    self.cardField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.cardField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.cardField.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightRegular];

    UIButton *readButton = [UIButton buttonWithType:UIButtonTypeSystem];
    readButton.translatesAutoresizingMaskIntoConstraints = NO;
    [readButton setTitle:@"Run Read Probe" forState:UIControlStateNormal];
    readButton.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
    [readButton addTarget:self action:@selector(onRunRead) forControlEvents:UIControlEventTouchUpInside];

    UIButton *canaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    canaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [canaryButton setTitle:@"Run + Canary" forState:UIControlStateNormal];
    canaryButton.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
    [canaryButton addTarget:self action:@selector(onRunCanary) forControlEvents:UIControlEventTouchUpInside];

    UIButton *copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    copyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [copyButton setTitle:@"Copy JSON" forState:UIControlStateNormal];
    copyButton.titleLabel.font = [UIFont systemFontOfSize:14.0];
    [copyButton addTarget:self action:@selector(onCopyJSON) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *buttonRow = [[UIStackView alloc] initWithArrangedSubviews:@[readButton, canaryButton, copyButton]];
    buttonRow.translatesAutoresizingMaskIntoConstraints = NO;
    buttonRow.axis = UILayoutConstraintAxisHorizontal;
    buttonRow.distribution = UIStackViewDistributionFillEqually;
    buttonRow.spacing = 8.0;

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.text = @"Ready. Diagnostic mode only (no card image modification).";
    self.statusLabel.font = [UIFont systemFontOfSize:12.0];
    self.statusLabel.numberOfLines = 0;

    self.reportView = [[UITextView alloc] init];
    self.reportView.translatesAutoresizingMaskIntoConstraints = NO;
    self.reportView.editable = NO;
    self.reportView.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    self.reportView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.reportView.layer.cornerRadius = 8.0;
    self.reportView.text = @"Tap 'Run Read Probe' to execute worse_query stage diagnostics.";

    [self.view addSubview:titleLabel];
    [self.view addSubview:self.cardField];
    [self.view addSubview:buttonRow];
    [self.view addSubview:self.statusLabel];
    [self.view addSubview:self.reportView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16.0],

        [self.cardField.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8.0],
        [self.cardField.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16.0],
        [self.cardField.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16.0],

        [buttonRow.topAnchor constraintEqualToAnchor:self.cardField.bottomAnchor constant:8.0],
        [buttonRow.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16.0],
        [buttonRow.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16.0],
        [buttonRow.heightAnchor constraintEqualToConstant:36.0],

        [self.statusLabel.topAnchor constraintEqualToAnchor:buttonRow.bottomAnchor constant:8.0],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16.0],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16.0],

        [self.reportView.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:8.0],
        [self.reportView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16.0],
        [self.reportView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16.0],
        [self.reportView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12.0],
    ]];
}

- (void)onRunRead {
    [self.view endEditing:YES];
    [self executeProbeWithCanary:NO cardIDOverride:nil];
}

- (void)onRunCanary {
    [self.view endEditing:YES];
    [self executeProbeWithCanary:YES cardIDOverride:nil];
}

- (void)onCopyJSON {
    if (self.lastJSON.length > 0) {
        UIPasteboard.generalPasteboard.string = self.lastJSON;
        self.statusLabel.text = @"Copied redacted JSON report to clipboard.";
    }
}

- (void)executeProbeWithCanary:(BOOL)includeCanary cardIDOverride:(nullable NSString *)cardOverride {
    NSString *inputCard = cardOverride ?: self.cardField.text;
    self.statusLabel.text = includeCanary ? @"Running read + canary probe..." : @"Running read-only probe...";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *report = [ProbeRunner runProbeWithCardID:inputCard includeCanary:includeCanary];
        NSString *json = [ProbeRunner formatReportJSON:report];
        NSString *savedPath = [ProbeRunner writeReportToDocuments:report];
        NSLog(@"[WalletProbe] REPORT_BEGIN\n%@\n[WalletProbe] REPORT_END", json);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.lastJSON = json;
            self.reportView.text = json;
            self.statusLabel.text = savedPath
                ? @"Completed. Redacted JSON saved to Documents/walletprobe-report.json."
                : @"Completed (in-memory only).";
        });
    });
}

@end

@interface WalletProbeAppDelegate : UIResponder <UIApplicationDelegate, UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) WalletProbeViewController *rootController;
@property (nonatomic, assign) BOOL didTriggerAutorun;
@end

@implementation WalletProbeAppDelegate

- (WalletProbeViewController *)ensureRootController {
    if (!self.rootController) {
        self.rootController = [[WalletProbeViewController alloc] init];
    }
    return self.rootController;
}

- (void)checkAutorunIfNeeded {
    if (self.didTriggerAutorun) return;
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    NSDictionary<NSString *, NSString *> *env = NSProcessInfo.processInfo.environment;
    BOOL autorunRead = [args containsObject:@"--autorun-read"] || [env[@"WALLETPROBE_AUTORUN"] isEqualToString:@"read"];
    BOOL autorunCanary = [args containsObject:@"--autorun-canary"] || [env[@"WALLETPROBE_AUTORUN"] isEqualToString:@"canary"];
    if (!autorunRead && !autorunCanary) return;
    self.didTriggerAutorun = YES;

    NSString *cardID = env[@"WALLETPROBE_CARD_ID"];
    NSUInteger idx = [args indexOfObject:@"--card-id"];
    if (idx != NSNotFound && idx + 1 < args.count) {
        cardID = args[idx + 1];
    }
    WalletProbeViewController *vc = [self ensureRootController];
    [vc loadViewIfNeeded];
    if (cardID.length > 0) vc.cardField.text = cardID;
    [vc executeProbeWithCanary:autorunCanary cardIDOverride:cardID];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [self ensureRootController];
    [self.window makeKeyAndVisible];
    [self checkAutorunIfNeeded];
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                              options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Default"
                                                                  sessionRole:connectingSceneSession.role];
    config.delegateClass = [WalletProbeAppDelegate class];
    return config;
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if ([scene isKindOfClass:[UIWindowScene class]]) {
        self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
        self.window.rootViewController = [self ensureRootController];
        [self.window makeKeyAndVisible];
        [self checkAutorunIfNeeded];
    }
}

@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([WalletProbeAppDelegate class]));
    }
}

// The control app of RecTunnelX.

#import <UIKit/UIKit.h>
#import "RXMainController.h"

@interface RXAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation RXAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:[RXMainController new]];
    navigation.navigationBar.tintColor = [UIColor colorWithRed:0.62 green:0.11 blue:0.11 alpha:1];
    self.window.rootViewController = navigation;
    [self.window makeKeyAndVisible];
    return YES;
}

@end

int main(int argc, char **argv) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([RXAppDelegate class]));
    }
}

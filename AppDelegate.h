//
//  AppDelegate.h


#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
    NSTimer *refreshTimer;
    CFArrayRef devices;
    int iterator;
}


@end


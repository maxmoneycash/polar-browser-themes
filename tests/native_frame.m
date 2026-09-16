#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "../native/ThemeRuntime.h"

extern void PTApplyFrame(NSView *, BOOL);
static CGFloat inset = 20;
NSColor *PTColor(NSString *section, NSString *key) { return NSColor.grayColor; }
CGFloat PTNumber(NSString *section, NSString *key) {
    return [key isEqual:@"inset"] ? inset : [key isEqual:@"radius"] ? 12 : 0;
}
static void require(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Class pageClass = objc_allocateClassPair(NSView.class, "PolarApp.ContentInteractionContainerView", 0);
        objc_registerClassPair(pageClass);
        NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 700)];
        NSView *page = [[pageClass alloc] initWithFrame:NSMakeRect(6, 6, 988, 688)];
        NSView *host = [[NSView alloc] initWithFrame:page.bounds];
        NSView *overlay = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 988, 1)];
        NSView *hiddenHost = [[NSView alloc] initWithFrame:NSZeroRect];
        [root addSubview:page];
        [page addSubview:host]; [page addSubview:overlay]; [page addSubview:hiddenHost];
        PTApplyFrame(root, YES);
        require(NSEqualRects(page.frame, NSMakeRect(20, 20, 960, 660)), @"Page inset is symmetric");
        require(NSEqualRects(host.frame, page.bounds), @"Browser host follows the inset viewport");
        require(overlay.frame.size.width == 960 && overlay.frame.size.height == 1, @"Thin overlay follows width without growing in height");
        require(NSEqualRects(hiddenHost.frame, NSZeroRect), @"Inactive zero-sized hosts stay inactive");
        require(page.layer.masksToBounds && page.layer.cornerRadius == 12, @"Page corners clip content");

        NSView *backdrop = root.subviews.firstObject;
        NSView *glass = [[NSView alloc] initWithFrame:root.bounds];
        [root addSubview:glass positioned:NSWindowBelow relativeTo:page];
        // Simulate another native layout after a window resize.
        root.frame = NSMakeRect(0, 0, 900, 660);
        page.frame = NSMakeRect(6, 6, 888, 648);
        host.frame = page.bounds; overlay.frame = NSMakeRect(0, 0, 888, 1);
        PTApplyFrame(root, YES);
        require(NSEqualRects(host.frame, NSMakeRect(0, 0, 860, 620)), @"Window resizing preserves host alignment");
        require([root.subviews indexOfObject:backdrop] > [root.subviews indexOfObject:glass], @"Frame remains above Polar's reordered glass");
        require([root.subviews indexOfObject:backdrop] < [root.subviews indexOfObject:page], @"Frame stays behind page content");
        PTApplyFrame(root, NO);
        require(backdrop.hidden, @"Showing original controls hides the themed backdrop");
        puts("Native frame geometry checks passed");
    }
    return 0;
}

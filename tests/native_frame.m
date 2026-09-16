#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "../native/ThemeRuntime.h"

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
        Class hostClass = objc_allocateClassPair(NSView.class, "PolarApp.LayerHostSurfaceView", 0);
        objc_registerClassPair(hostClass);
        NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 700)];
        NSView *page = [[pageClass alloc] initWithFrame:NSZeroRect];
        NSView *host = [[hostClass alloc] initWithFrame:NSZeroRect];
        NSView *overlay = [[NSView alloc] initWithFrame:NSZeroRect];
        NSView *hiddenHost = [[hostClass alloc] initWithFrame:NSZeroRect];
        NSView *peer = [[NSView alloc] initWithFrame:NSZeroRect];
        [root addSubview:page]; [root addSubview:peer];
        [page addSubview:host]; [page addSubview:overlay]; [page addSubview:hiddenHost];
        NSMutableArray<NSValue *> *published = [NSMutableArray array];
        host.postsFrameChangedNotifications = YES;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:NSViewFrameDidChangeNotification object:host queue:nil usingBlock:^(NSNotification *note) {
            [published addObject:[NSValue valueWithSize:host.bounds.size]];
        }];
        void (^nativeLayout)(void) = ^{
            NSRect original = NSInsetRect(root.bounds, 6, 6);
            page.frame = original;
            // Native code can use cached dimensions instead of page.bounds.
            host.frame = NSMakeRect(0, 0, original.size.width, original.size.height);
            overlay.frame = NSMakeRect(0, 0, original.size.width, 1);
            hiddenHost.frame = NSZeroRect;
            peer.frame = original;
            require(NSEqualRects(host.frame, page.bounds), @"Host receives final bounds before native layout can publish them");
        };
        PTLayoutFrame(root, YES, nativeLayout);
        require(NSEqualRects(page.frame, NSMakeRect(20, 20, 960, 660)), @"Page inset is symmetric");
        require(NSEqualRects(peer.frame, page.frame), @"Sibling overlays align with the page");
        require(overlay.frame.size.width == 960 && overlay.frame.size.height == 1, @"Thin overlay follows width without growing in height");
        require(NSEqualRects(hiddenHost.frame, NSZeroRect), @"Inactive zero-sized hosts stay inactive");
        require(page.layer.masksToBounds && page.layer.cornerRadius == 12, @"Page corners clip content");
        for (NSValue *value in published)
            require(NSEqualSizes(value.sizeValue, NSMakeSize(960, 660)), @"No intermediate viewport is published");
        [published removeAllObjects];
        for (int i = 0; i < 5; i++) PTLayoutFrame(root, YES, nativeLayout);
        require(published.count == 0, @"Repeated layout does not oscillate the browser viewport");

        NSView *backdrop = root.subviews.firstObject;
        NSView *glass = [[NSView alloc] initWithFrame:root.bounds];
        [root addSubview:glass positioned:NSWindowBelow relativeTo:page];
        root.frame = NSMakeRect(0, 0, 900, 660);
        PTLayoutFrame(root, YES, nativeLayout);
        require(NSEqualRects(host.frame, NSMakeRect(0, 0, 860, 620)), @"Window resizing preserves host alignment");
        for (NSValue *value in published)
            require(NSEqualSizes(value.sizeValue, NSMakeSize(860, 620)), @"Window resize publishes only final themed bounds");
        require([root.subviews indexOfObject:backdrop] > [root.subviews indexOfObject:glass], @"Frame remains above Polar's reordered glass");
        require([root.subviews indexOfObject:backdrop] < [root.subviews indexOfObject:page], @"Frame stays behind page content");
        inset = 8;
        PTLayoutFrame(root, YES, nativeLayout);
        require(NSEqualRects(host.frame, NSMakeRect(0, 0, 884, 644)), @"Theme changes recompute from native geometry without accumulating inset");
        PTLayoutFrame(root, NO, nativeLayout);
        require(backdrop.hidden, @"Showing original controls hides the themed backdrop");
        require(NSEqualRects(page.frame, NSMakeRect(6, 6, 888, 648)), @"Disabled adapter preserves original geometry");
        NSView *unrelated = [[NSView alloc] initWithFrame:NSZeroRect];
        PTLayoutFrame(root, YES, ^{ unrelated.frame = NSMakeRect(6, 6, 888, 648); });
        require(NSEqualRects(unrelated.frame, NSMakeRect(6, 6, 888, 648)), @"Unrelated views are untouched");
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        puts("Native frame geometry and viewport stability checks passed");
    }
    return 0;
}

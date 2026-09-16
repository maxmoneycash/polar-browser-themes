#import "ThemeRuntime.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface PTFrameView : NSView
@end
@implementation PTFrameView
- (BOOL)isFlipped { return YES; }
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (BOOL)isAccessibilityElement { return NO; }
- (void)drawRect:(NSRect)rect {
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:PTColor(@"frame", @"color") endingColor:PTColor(@"frame", @"endColor")];
    [gradient drawInRect:self.bounds angle:PTNumber(@"frame", @"angle")];
}
@end

static void collectPages(NSView *view, NSMutableArray *pages) {
    for (NSView *child in view.subviews) {
        if ([NSStringFromClass(child.class) isEqual:@"PolarApp.ContentInteractionContainerView"]) [pages addObject:child];
        else if (![child isKindOfClass:PTFrameView.class]) collectPages(child, pages);
    }
}

void PTApplyFrame(NSView *root, BOOL enabled) {
    NSMutableArray<NSView *> *pages = [NSMutableArray array]; collectPages(root, pages);
    for (NSView *page in pages) {
        NSView *parent = page.superview;
        PTFrameView *frame = objc_getAssociatedObject(page, @selector(PTApplyFrame));
        if (!enabled) { frame.hidden = YES; continue; }
        if (!frame) {
            frame = [[PTFrameView alloc] initWithFrame:parent.bounds];
            frame.wantsLayer = YES;
            frame.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            [parent addSubview:frame positioned:NSWindowBelow relativeTo:page];
            objc_setAssociatedObject(page, @selector(PTApplyFrame), frame, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        // Polar may reorder its glass backdrop during layout. Keep our layer
        // immediately behind the page on every pass, above that backdrop.
        [parent addSubview:frame positioned:NSWindowBelow relativeTo:page];
        frame.layer.zPosition = page.layer.zPosition;
        frame.hidden = page.hidden; frame.frame = parent.bounds; frame.needsDisplay = YES;
        if (page.hidden || page.frame.size.width < 100) continue;
        // Polar's original layout has just run. Inset matching sibling overlays
        // along with the content container, preserving their coordinate alignment.
        NSRect original = page.frame;
        NSSize contentSize = page.bounds.size;
        CGFloat extra = PTNumber(@"frame", @"inset") - 6;
        if (extra > 0 && original.size.width > extra * 2 && original.size.height > extra * 2) {
            for (NSView *peer in parent.subviews) {
                if (peer != frame && NSEqualRects(peer.frame, original)) peer.frame = NSInsetRect(original, extra, extra);
            }
            // Polar lays out its host surfaces and SwiftUI overlays explicitly;
            // their autoresizing masks do not follow the container's new size.
            // Update each formerly full-width/full-height child, then let the
            // host's own layout synchronize the Chromium viewport.
            for (NSView *child in page.subviews) {
                NSRect childFrame = child.frame;
                if (childFrame.origin.x == 0 && childFrame.size.width == contentSize.width)
                    childFrame.size.width = page.bounds.size.width;
                if (childFrame.origin.y == 0 && childFrame.size.height == contentSize.height)
                    childFrame.size.height = page.bounds.size.height;
                if (!NSEqualRects(child.frame, childFrame)) {
                    child.frame = childFrame;
                    child.needsLayout = YES;
                }
            }
            [page layoutSubtreeIfNeeded];
        }
        page.wantsLayer = YES;
        page.layer.cornerRadius = PTNumber(@"frame", @"radius");
        page.layer.cornerCurve = kCACornerCurveContinuous;
        page.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        page.layer.masksToBounds = YES;
    }
}

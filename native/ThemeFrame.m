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

// Transform native frame assignments before LayerHostSurfaceView can publish
// them to Chromium. Resizing the host after layout alternates between two
// viewport sizes and feeds another layout back into the browser indefinitely.
// Only these two Polar classes are hooked; unrelated NSViews are untouched.
static __unsafe_unretained NSView *layoutRoot;
static CGFloat layoutExtra;
static char nativeFrameKey;
static void (*originalPageSetFrame)(NSView *, SEL, NSRect);
static void (*originalHostSetFrame)(NSView *, SEL, NSRect);

static NSRect adjustedChildFrame(NSView *page, NSRect rect) {
    NSValue *nativeValue = objc_getAssociatedObject(page, &nativeFrameKey);
    if (!nativeValue) return rect;
    NSSize nativeSize = nativeValue.rectValue.size;
    if (rect.origin.x == 0 && rect.size.width > 0 && rect.size.width == nativeSize.width)
        rect.size.width = page.bounds.size.width;
    if (rect.origin.y == 0 && rect.size.height > 0 && rect.size.height == nativeSize.height)
        rect.size.height = page.bounds.size.height;
    return rect;
}

static void pageSetFrame(NSView *page, SEL selector, NSRect rect) {
    if (layoutRoot && [page isDescendantOf:layoutRoot]) {
        objc_setAssociatedObject(page, &nativeFrameKey, [NSValue valueWithRect:rect], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (layoutExtra > 0 && rect.size.width > 100 && rect.size.height > layoutExtra * 2)
            rect = NSInsetRect(rect, layoutExtra, layoutExtra);
    }
    originalPageSetFrame(page, selector, rect);
}

static void hostSetFrame(NSView *host, SEL selector, NSRect rect) {
    if (layoutRoot && layoutExtra > 0 && [host isDescendantOf:layoutRoot])
        rect = adjustedChildFrame(host.superview, rect);
    originalHostSetFrame(host, selector, rect);
}

static IMP installFrameHook(NSString *name, IMP replacement) {
    Class cls = NSClassFromString(name);
    Method inherited = class_getInstanceMethod(cls, @selector(setFrame:));
    if (!inherited) return NULL;
    IMP original = method_getImplementation(inherited);
    // Adding an override must not mutate the inherited NSView implementation.
    if (!class_addMethod(cls, @selector(setFrame:), replacement, method_getTypeEncoding(inherited)))
        class_replaceMethod(cls, @selector(setFrame:), replacement, method_getTypeEncoding(inherited));
    return original;
}

static void collectPages(NSView *view, NSMutableArray *pages) {
    for (NSView *child in view.subviews) {
        if ([NSStringFromClass(child.class) isEqual:@"PolarApp.ContentInteractionContainerView"]) [pages addObject:child];
        else if (![child isKindOfClass:PTFrameView.class]) collectPages(child, pages);
    }
}

static void applyFrame(NSView *root, BOOL enabled) {
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
        NSValue *nativeValue = objc_getAssociatedObject(page, &nativeFrameKey);
        NSRect original = nativeValue.rectValue;
        if (nativeValue && !NSEqualRects(original, page.frame)) {
            for (NSView *peer in parent.subviews) {
                if (peer != frame && peer != page && NSEqualRects(peer.frame, original)) peer.frame = page.frame;
            }
            // Non-browser overlays may still use the original native dimensions.
            // The browser host has already received its final size during layout.
            for (NSView *child in page.subviews) {
                if ([NSStringFromClass(child.class) isEqual:@"PolarApp.LayerHostSurfaceView"]) continue;
                NSRect childFrame = adjustedChildFrame(page, child.frame);
                if (!NSEqualRects(child.frame, childFrame)) {
                    child.frame = childFrame;
                    child.needsLayout = YES;
                }
            }
        }
        page.wantsLayer = YES;
        page.layer.cornerRadius = PTNumber(@"frame", @"radius");
        page.layer.cornerCurve = kCACornerCurveContinuous;
        page.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        page.layer.masksToBounds = YES;
    }
}

void PTLayoutFrame(NSView *root, BOOL enabled, void (^nativeLayout)(void)) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        originalPageSetFrame = (void *)installFrameHook(@"PolarApp.ContentInteractionContainerView", (IMP)pageSetFrame);
        originalHostSetFrame = (void *)installFrameHook(@"PolarApp.LayerHostSurfaceView", (IMP)hostSetFrame);
    });
    NSView *previousRoot = layoutRoot;
    CGFloat previousExtra = layoutExtra;
    layoutRoot = root;
    layoutExtra = enabled ? PTNumber(@"frame", @"inset") - 6 : 0;
    @try {
        nativeLayout();
    } @finally {
        layoutRoot = previousRoot;
        layoutExtra = previousExtra;
    }
    applyFrame(root, enabled);
}

#import <AppKit/AppKit.h>
#import "ThemeRuntime.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>

extern void ZenOpenPalette(NSWindow *, BOOL);
extern BOOL ZenPaletteIsOpen(void);
extern void ZenClosePalette(void);
extern void ZenWithString(const char *, void *, void (*)(uintptr_t, uintptr_t, void *));
extern void *ZenTakeString(uintptr_t, uintptr_t);
extern void ZenEnumerateTabs(uintptr_t, void *, void (*)(intptr_t, void *, void *));

// Version locked by scripts/native_adapter.py to Polar 0.1.92. This byte occupies verified
// unused zero-fill padding, rather than executable memory. No runtime code writes.
static volatile uint8_t *controls;
static BOOL temporaryControls;
static void (*originalSendEvent)(id, SEL, NSEvent *);
static void (*originalBrowserLayout)(id, SEL);
static const NSEventModifierFlags relevant = NSEventModifierFlagCommand |
    NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl;

static NSWindow *browserWindow(void) {
    NSWindow *key = NSApp.keyWindow;
    if ([NSStringFromClass(key.contentView.class) containsString:@"BrowserContainerView"]) return key;
    for (NSWindow *w in NSApp.orderedWindows)
        if (w.visible && [NSStringFromClass(w.contentView.class) containsString:@"BrowserContainerView"]) return w;
    return nil;
}

static void showControls(BOOL show, BOOL temporary) {
    *controls = show;
    temporaryControls = show && temporary;
    for (NSWindow *w in NSApp.windows) {
        if (![NSStringFromClass(w.contentView.class) containsString:@"BrowserContainerView"]) continue;
        w.contentView.needsLayout = YES;
        [w.contentView layoutSubtreeIfNeeded];
        [w displayIfNeeded];
    }
}

static BOOL perform(NSString *name) {
    SEL action = NSSelectorFromString(name);
    NSWindow *w = browserWindow();
    if (w && !w.keyWindow) [w makeKeyWindow];
    id target = nil;
    if ([w.windowController respondsToSelector:action]) target = w.windowController;
    else if ([NSApp.delegate respondsToSelector:action]) target = NSApp.delegate;
    return [NSApp sendAction:action to:target from:nil];
}

static void *field(void *object, uintptr_t fieldSymbol) {
    if (!object) return NULL;
    intptr_t slide = _dyld_get_image_vmaddr_slide(0);
    uintptr_t offset = *(uintptr_t *)(fieldSymbol + slide);
    return *(void **)((uint8_t *)object + offset);
}

static void *windowGroup(NSWindow *window) {
    void *controller = field((__bridge void *)window.contentView, 0x100d34bc0);
    return field(controller, 0x100a5df68);
}

typedef struct { uintptr_t first, second; } ZenSwiftString;
static void collectTab(intptr_t index, void *tab, void *context) {
    typedef ZenSwiftString (*Title)(void * __attribute__((swift_context)) context) __attribute__((swiftcall));
    Title titleGetter = (Title)(0x1006b64f4 + _dyld_get_image_vmaddr_slide(0));
    ZenSwiftString text = titleGetter(tab);
    NSString *title = CFBridgingRelease(ZenTakeString(text.first, text.second));
    NSMutableArray *rows = (__bridge NSMutableArray *)context;
    [rows addObject:@{@"title":title.length ? title : @"New Tab", @"tab":(__bridge id)tab, @"index":@(index)}];
}

NSArray<NSDictionary *> *ZenNativeTabs(NSWindow *window) {
    void *group = windowGroup(window);
    if (!group) return @[];
    typedef uintptr_t (*Tabs)(void * __attribute__((swift_context)) context) __attribute__((swiftcall));
    uintptr_t storage = ((Tabs)(0x100702c5c + _dyld_get_image_vmaddr_slide(0)))(group);
    NSMutableArray *rows = [NSMutableArray array];
    ZenEnumerateTabs(storage, (__bridge void *)rows, collectTab);
    return rows;
}

void ZenSelectTab(NSWindow *window, id tab) {
    // Resolve the current index, since tabs may change while the palette is open.
    for (NSDictionary *row in ZenNativeTabs(window)) {
        if (row[@"tab"] != tab) continue;
        typedef void (*Activate)(intptr_t, void * __attribute__((swift_context)) context) __attribute__((swiftcall));
        ((Activate)(0x1006e9cd0 + _dyld_get_image_vmaddr_slide(0)))([row[@"index"] integerValue], windowGroup(window));
        return;
    }
}

typedef struct { void *group; uint8_t disposition; } NavigationContext;
static void navigateString(uintptr_t first, uintptr_t second, void *context) {
    NavigationContext *nav = context;
    typedef void (*OpenURL)(uintptr_t, uintptr_t, uint8_t, uint8_t,
                           void * __attribute__((swift_context)) context) __attribute__((swiftcall));
    ((OpenURL)(0x1006f5408 + _dyld_get_image_vmaddr_slide(0)))(first, second, nav->disposition, 1, nav->group);
}

void ZenNavigate(NSWindow *window, NSString *input, BOOL newTab) {
    NSString *text = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length || !windowGroup(window)) return;
    NSString *url = text;
    NSURLComponents *parts = [NSURLComponents componentsWithString:text];
    if (!parts.scheme.length) {
        BOOL address = [text rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet].location == NSNotFound &&
            ([text containsString:@"."] || [text hasPrefix:@"localhost"] || [text hasPrefix:@"["]);
        if (address) url = [@"https://" stringByAppendingString:text];
        else {
            NSURLComponents *search = [NSURLComponents componentsWithString:@"https://www.google.com/search"];
            search.queryItems = @[[NSURLQueryItem queryItemWithName:@"q" value:text]];
            url = search.string;
        }
    }
    NavigationContext nav = {windowGroup(window), newTab ? 3 : 1};
    ZenWithString(url.UTF8String, &nav, navigateString);
}

static void zenBrowserLayout(NSView *view, SEL selector) {
    PTLayoutFrame(view, !*controls, ^{ originalBrowserLayout(view, selector); });
}

static NSMenuItem *menuItem(NSMenu *menu, NSString *title) {
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.title isEqualToString:title]) return item;
        NSMenuItem *found = item.submenu ? menuItem(item.submenu, title) : nil;
        if (found) return found;
    }
    return nil;
}

static BOOL performMenu(NSString *title) {
    NSMenuItem *item = menuItem(NSApp.mainMenu, title);
    return item && item.action && [NSApp sendAction:item.action to:item.target from:item];
}

static BOOL pinTab(void) {
    NSWindow *w = browserWindow();
    if (!w) return NO;
    void *controller = field((__bridge void *)w.contentView, 0x100d34bc0);
    void *group = field(controller, 0x100a5df68);
    if (!group) return NO;
    typedef intptr_t (*Index)(void * __attribute__((swift_context)) context) __attribute__((swiftcall));
    typedef void (*Toggle)(intptr_t index, void * __attribute__((swift_context)) context) __attribute__((swiftcall));
    intptr_t slide = _dyld_get_image_vmaddr_slide(0);
    intptr_t index = ((Index)(0x100703cf8 + slide))(group);
    if (index < 0) return NO;
    ((Toggle)(0x1006e6bf8 + slide))(index, group);
    return YES;
}

static void formattedURL(BOOL quote) {
    NSString *title = browserWindow().title ?: @"Page";
    if (!perform(@"copyURLAction:")) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        NSPasteboard *pb = NSPasteboard.generalPasteboard;
        NSString *url = [pb stringForType:NSPasteboardTypeString];
        if (!url.length) return;
        NSString *escaped = [[title stringByReplacingOccurrencesOfString:@"[" withString:@"\\["]
                                    stringByReplacingOccurrencesOfString:@"]" withString:@"\\]"];
        NSString *text = quote ? [NSString stringWithFormat:@"> %@\n\n[%@](%@)", title, escaped, url]
                               : [NSString stringWithFormat:@"[%@](%@)", escaped, url];
        [pb clearContents];
        [pb setString:text forType:NSPasteboardTypeString];
    });
}

@interface PolarZenCommands : NSObject
@end
@implementation PolarZenCommands
- (void)toggleToolbar:(id)sender { showControls(!*controls, NO); }
- (void)toggleSidebar:(id)sender { perform(@"toggleWorkspaceSidebarAction:"); }
- (void)pinTab:(id)sender { pinTab(); }
- (void)copyMarkdown:(id)sender { formattedURL(NO); }
- (void)copyQuote:(id)sender { formattedURL(YES); }
@end

static void remap(NSMenu *menu, NSString *title, NSString *key, NSEventModifierFlags mods) {
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.title isEqualToString:title]) {
            item.keyEquivalent = key;
            item.keyEquivalentModifierMask = mods;
        }
        if (item.submenu) remap(item.submenu, title, key, mods);
    }
}

static void installMenus(void) {
    static PolarZenCommands *commands;
    if (commands || !NSApp.mainMenu) return;
    commands = [PolarZenCommands new];
    NSEventModifierFlags cmd = NSEventModifierFlagCommand, shift = NSEventModifierFlagShift;
    remap(NSApp.mainMenu, @"Save Page As…", @"s", cmd | shift);
    remap(NSApp.mainMenu, @"Bookmark This Page", @"", 0);
    remap(NSApp.mainMenu, @"Bookmark All Tabs…", @"", 0);
    remap(NSApp.mainMenu, @"Enter Full Screen", @"f", cmd | NSEventModifierFlagControl);
    remap(NSApp.mainMenu, @"Zoom In", @"+", cmd);
    NSMenu *view = [NSApp.mainMenu itemWithTitle:@"View"].submenu;
    NSMenu *edit = [NSApp.mainMenu itemWithTitle:@"Edit"].submenu;
    for (NSArray *spec in @[
        @[@"Toggle Sidebar", @"toggleSidebar:", @"s", @(cmd), view ?: NSNull.null],
        @[@"Show / Hide Browser Controls", @"toggleToolbar:", @"d", @(cmd | shift), view ?: NSNull.null],
        @[@"Pin / Unpin Tab", @"pinTab:", @"d", @(cmd), view ?: NSNull.null],
        @[@"Copy URL as Markdown", @"copyMarkdown:", @"c", @(cmd | shift | NSEventModifierFlagOption), edit ?: NSNull.null],
        @[@"Copy URL as Quote", @"copyQuote:", @"c", @(cmd | shift | NSEventModifierFlagControl), edit ?: NSNull.null]
    ]) {
        if (spec[4] == NSNull.null) continue;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:spec[0] action:NSSelectorFromString(spec[1]) keyEquivalent:spec[2]];
        item.target = commands;
        item.keyEquivalentModifierMask = [spec[3] unsignedLongLongValue];
        [spec[4] addItem:item];
    }
    NSLog(@"[Polar Themes] Native palette, frame adapter, and keyboard shortcuts loaded");
}

static BOOL handleKey(NSEvent *event) {
    if (event.type != NSEventTypeKeyDown || !browserWindow() || NSApp.modalWindow || browserWindow().attachedSheet) return NO;
    NSEventModifierFlags mods = event.modifierFlags & relevant;
    NSEventModifierFlags cmd = NSEventModifierFlagCommand, shift = NSEventModifierFlagShift;
    NSEventModifierFlags opt = NSEventModifierFlagOption, ctrl = NSEventModifierFlagControl;
    NSString *key = event.charactersIgnoringModifiers.lowercaseString;
    if (mods == cmd && ([key isEqualToString:@"l"] || [key isEqualToString:@"t"])) {
        showControls(NO, NO);
        ZenOpenPalette(browserWindow(), [key isEqualToString:@"t"]);
        return YES;
    }
    if (ZenPaletteIsOpen() && event.keyCode == 53) { ZenClosePalette(); return YES; }
    if (mods == cmd && [key isEqualToString:@"s"]) return perform(@"toggleWorkspaceSidebarAction:");
    if (mods == (cmd | shift) && [key isEqualToString:@"d"]) { showControls(!*controls, NO); return YES; }
    if (mods == cmd && [key isEqualToString:@"d"]) return pinTab();
    if (mods == (cmd | shift) && [key isEqualToString:@"s"]) return perform(@"savePageAction:");
    if (mods == (cmd | ctrl) && [key isEqualToString:@"f"]) { [browserWindow() toggleFullScreen:nil]; return YES; }
    if (mods == (cmd | opt) && event.keyCode == 125) return perform(@"nextTabAction:");
    if (mods == (cmd | opt) && event.keyCode == 126) return perform(@"previousTabAction:");
    if (mods == ctrl && event.keyCode == 48) return perform(@"nextTabAction:");
    if (mods == (ctrl | shift) && event.keyCode == 48) return perform(@"previousTabAction:");
    if (mods == (cmd | shift) && [key isEqualToString:@"l"]) return perform(@"bookmarkManagerAction:");
    if (mods == (cmd | shift | opt) && [key isEqualToString:@"c"]) { formattedURL(NO); return YES; }
    if (mods == (cmd | shift | ctrl) && [key isEqualToString:@"c"]) { formattedURL(YES); return YES; }
    if (mods == (cmd | shift) && event.keyCode == 19) {
        NSTask *task = [NSTask new]; task.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/screencapture"];
        task.arguments = @[@"-i", @"-c"]; [task launchAndReturnError:nil]; return YES;
    }
    if (mods == (cmd | ctrl) && [key isEqualToString:@"n"]) return performMenu(@"New Window");
    if (mods == (cmd | opt) && [key isEqualToString:@"n"]) {
        if (!performMenu(@"New Window")) return NO;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            NSWindow *w = browserWindow(); NSRect f = w.frame; f.size = NSMakeSize(720, 540); [w setFrame:f display:YES];
        });
        return YES;
    }
    if (event.keyCode == 53 && temporaryControls) {
        perform(@"escapeAction:"); showControls(NO, NO); return YES;
    }
    if ((event.keyCode == 36 || event.keyCode == 76) && temporaryControls) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            if (temporaryControls) showControls(NO, NO);
        });
    }
    return NO;
}

static void zenSendEvent(id app, SEL selector, NSEvent *event) {
    installMenus();
    if (!handleKey(event)) originalSendEvent(app, selector, event);
}

__attribute__((constructor)) static void startZen(void) {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    if (![info[@"CFBundleShortVersionString"] isEqual:@"0.1.92"] ||
        ![info[@"CFBundleVersion"] isEqual:@"20260913071337"]) return;
    controls = (volatile uint8_t *)(0x100de3f00 + _dyld_get_image_vmaddr_slide(0));
    *controls = 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        PTThemeStart();
        *controls = ![PTTheme()[@"controls"][@"hidden"] boolValue];
        [NSNotificationCenter.defaultCenter addObserverForName:PTThemeDidChange object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            showControls(![PTTheme()[@"controls"][@"hidden"] boolValue], NO);
        }];
        Method method = class_getInstanceMethod(NSApplication.class, @selector(sendEvent:));
        originalSendEvent = (void *)method_setImplementation(method, (IMP)zenSendEvent);
        Class browserClass = NSClassFromString(@"PolarApp.BrowserContainerView");
        Method layout = class_getInstanceMethod(browserClass, @selector(layout));
        if (layout) originalBrowserLayout = (void *)method_setImplementation(layout, (IMP)zenBrowserLayout);
        installMenus();
    });
}

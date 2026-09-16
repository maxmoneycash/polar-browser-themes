#import <AppKit/AppKit.h>
#import "ThemeRuntime.h"

extern NSArray<NSDictionary *> *ZenNativeTabs(NSWindow *window);
extern void ZenNavigate(NSWindow *window, NSString *text, BOOL newTab);
extern void ZenSelectTab(NSWindow *window, id tab);

@interface ZenPaletteBackground : NSView
@end
@implementation ZenPaletteBackground
- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, .5, .5) xRadius:PTNumber(@"palette", @"radius") yRadius:PTNumber(@"palette", @"radius")];
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:PTColor(@"palette", @"color")
                                                    endingColor:PTColor(@"palette", @"endColor")];
    [gradient drawInBezierPath:shape angle:PTNumber(@"palette", @"angle")];
    [PTColor(@"palette", @"border") setStroke]; shape.lineWidth = 1; [shape stroke];
}
@end

@interface ZenPaletteRow : NSButton
@property BOOL selected;
@property(copy) NSString *label;
@property(copy) NSString *hint;
@end
@implementation ZenPaletteRow
- (void)drawRect:(NSRect)dirtyRect {
    if (self.selected) {
        [PTColor(@"palette", @"accent") setFill];
        [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:PTNumber(@"palette", @"rowRadius") yRadius:PTNumber(@"palette", @"rowRadius")] fill];
    }
    NSImageSymbolConfiguration *tint = [NSImageSymbolConfiguration configurationWithPaletteColors:@[
        PTColor(@"palette", self.selected ? @"accentText" : @"muted")]];
    NSImage *icon = [[NSImage imageWithSystemSymbolName:@"globe" accessibilityDescription:nil] imageWithSymbolConfiguration:tint];
    [icon drawInRect:NSMakeRect(14, (self.bounds.size.height - 18) / 2, 18, 18)];
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new]; paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attrs = @{ NSFontAttributeName:[NSFont systemFontOfSize:PTNumber(@"palette", @"fontSize") weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName:PTColor(@"palette", self.selected ? @"accentText" : @"text"), NSParagraphStyleAttributeName:paragraph };
    [self.label drawInRect:NSMakeRect(44, (self.bounds.size.height - PTNumber(@"palette", @"fontSize") - 5) / 2, self.bounds.size.width - 196, PTNumber(@"palette", @"fontSize") + 6) withAttributes:attrs];
    NSDictionary *hintAttrs = @{NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName:PTColor(@"palette", self.selected ? @"accentText" : @"muted")};
    [self.hint drawAtPoint:NSMakePoint(self.bounds.size.width - 132, (self.bounds.size.height - 16) / 2) withAttributes:hintAttrs];
    NSImage *arrow = [[NSImage imageWithSystemSymbolName:@"arrow.right" accessibilityDescription:nil] imageWithSymbolConfiguration:tint];
    [arrow drawInRect:NSMakeRect(self.bounds.size.width - 30, (self.bounds.size.height - 18) / 2, 18, 18)];
}
@end

@interface ZenURLPalette : NSPanel <NSTextFieldDelegate>
@property(strong) NSTextField *search;
@property(strong) NSImageView *searchIcon;
@property(strong) NSBox *separator;
@property(strong) NSView *rowsView;
@property(strong) NSWindow *browser;
@property(copy) NSArray<NSDictionary *> *tabs;
@property(copy) NSArray<NSDictionary *> *results;
@property NSInteger selectedIndex;
@property BOOL createsTab;
- (void)refresh;
- (void)dismiss;
@end
static ZenURLPalette *palette;

@implementation ZenURLPalette
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (instancetype)init {
    self = [super initWithContentRect:NSMakeRect(0, 0, 640, 340) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    if (!self) return nil;
    self.opaque = NO; self.backgroundColor = NSColor.clearColor; self.hasShadow = YES;
    self.hidesOnDeactivate = YES; self.releasedWhenClosed = NO;
    self.contentView = [[ZenPaletteBackground alloc] initWithFrame:NSMakeRect(0, 0, 640, 340)];
    self.search = [[NSTextField alloc] initWithFrame:NSMakeRect(44, 282, 538, 30)];
    self.search.bordered = NO; self.search.drawsBackground = NO; self.search.focusRingType = NSFocusRingTypeNone;
    self.search.font = [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold]; self.search.textColor = NSColor.whiteColor;
    self.search.placeholderAttributedString = [[NSAttributedString alloc] initWithString:@"Search or Enter URL…" attributes:@{
        NSForegroundColorAttributeName:[NSColor colorWithWhite:1 alpha:.50], NSFontAttributeName:self.search.font }];
    self.search.delegate = self; self.search.accessibilityLabel = @"Search or Enter URL";
    [self.contentView addSubview:self.search];
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(20, 285, 18, 18)];
    icon.image = [NSImage imageWithSystemSymbolName:@"magnifyingglass" accessibilityDescription:@"Search"];
    icon.contentTintColor = NSColor.whiteColor; self.searchIcon = icon; [self.contentView addSubview:icon];
    NSBox *line = [[NSBox alloc] initWithFrame:NSMakeRect(12, 266, 616, 1)];
    line.boxType = NSBoxSeparator; self.separator = line; [self.contentView addSubview:line];
    self.rowsView = [[NSView alloc] initWithFrame:NSMakeRect(8, 8, 624, 250)];
    [self.contentView addSubview:self.rowsView];
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidResignKeyNotification object:self queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if (palette.visible) [palette dismiss];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:PTThemeDidChange object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if (palette.visible) [palette refresh];
    }];
    return self;
}
- (void)refresh {
    if (!self.browser) return;
    CGFloat rowHeight = PTNumber(@"palette", @"rowHeight");
    self.appearance = [NSAppearance appearanceNamed:[PTTheme()[@"appearance"] isEqual:@"light"] ? NSAppearanceNameAqua : NSAppearanceNameDarkAqua];
    self.search.font = [NSFont systemFontOfSize:PTNumber(@"palette", @"fontSize") + 3 weight:NSFontWeightSemibold];
    self.search.textColor = PTColor(@"palette", @"text");
    self.searchIcon.contentTintColor = PTColor(@"palette", @"text");
    self.search.placeholderAttributedString = [[NSAttributedString alloc] initWithString:@"Search or Enter URL…" attributes:@{NSForegroundColorAttributeName:PTColor(@"palette", @"muted"),NSFontAttributeName:self.search.font}];
    NSUInteger maxRows = MIN(6, MAX(1, (NSInteger)((self.browser.frame.size.height * .78 - 76) / rowHeight)));
    NSString *query = [self.search.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray *results = [NSMutableArray array];
    if (query.length) [results addObject:@{@"title":query, @"query":query}];
    for (NSDictionary *tab in self.tabs) {
        if (!query.length || [tab[@"title"] localizedCaseInsensitiveContainsString:query]) [results addObject:tab];
        if (results.count >= maxRows) break;
    }
    if (!results.count) [results addObject:@{@"title":@"Search the web or enter an address", @"query":@""}];
    self.results = results;
    self.selectedIndex = MIN(MAX(0, self.selectedIndex), (NSInteger)results.count - 1);
    CGFloat width = MIN(PTNumber(@"palette", @"width"), self.browser.frame.size.width - 56), height = 76 + results.count * rowHeight;
    NSRect parent = self.browser.frame;
    NSRect frame = NSMakeRect(NSMidX(parent) - width / 2, NSMaxY(parent) - MIN(110, parent.size.height * .13) - height, width, height);
    [self setFrame:frame display:YES];
    // Keep drawing coordinates in points when the result count resizes the panel.
    self.contentView.frame = NSMakeRect(0, 0, width, height);
    self.contentView.bounds = NSMakeRect(0, 0, width, height);
    self.search.frame = NSMakeRect(44, height - 55, width - 66, 30);
    self.searchIcon.frame = NSMakeRect(20, height - 52, 18, 18);
    self.separator.frame = NSMakeRect(12, height - 67, width - 24, 1);
    self.rowsView.frame = NSMakeRect(8, 8, width - 16, results.count * rowHeight);
    for (NSView *view in self.rowsView.subviews.copy) [view removeFromSuperview];
    [results enumerateObjectsUsingBlock:^(NSDictionary *row, NSUInteger index, BOOL *stop) {
        ZenPaletteRow *button = [[ZenPaletteRow alloc] initWithFrame:NSMakeRect(0, (results.count - index - 1) * rowHeight, width - 16, rowHeight - 4)];
        button.bordered = NO; button.selected = (NSInteger)index == self.selectedIndex; button.label = row[@"title"];
        button.hint = row[@"query"] ? @"Open" : @"Switch to Tab"; button.tag = index;
        button.target = self; button.action = @selector(choose:); button.accessibilityLabel = button.label; button.accessibilityValue = button.selected ? @"Selected" : @"";
        [self.rowsView addSubview:button];
    }];
    self.contentView.needsDisplay = YES;
}
- (void)controlTextDidChange:(NSNotification *)note { self.selectedIndex = 0; [self refresh]; }
- (BOOL)control:(NSControl *)control textView:(NSTextView *)view doCommandBySelector:(SEL)selector {
    if (selector == @selector(moveDown:)) { self.selectedIndex = MIN(self.selectedIndex + 1, (NSInteger)self.results.count - 1); [self refresh]; return YES; }
    if (selector == @selector(moveUp:)) { self.selectedIndex = MAX(self.selectedIndex - 1, 0); [self refresh]; return YES; }
    if (selector == @selector(insertNewline:)) { [self choose:nil]; return YES; }
    if (selector == @selector(cancelOperation:)) { [self dismiss]; return YES; }
    return NO;
}
- (void)choose:(NSButton *)button {
    NSInteger index = button ? button.tag : self.selectedIndex;
    if (index < 0 || index >= (NSInteger)self.results.count) return;
    NSDictionary *result = self.results[index]; NSWindow *browser = self.browser; BOOL createsTab = self.createsTab;
    [self dismiss];
    if (result[@"query"]) { if ([result[@"query"] length]) ZenNavigate(browser, result[@"query"], createsTab); }
    else ZenSelectTab(browser, result[@"tab"]);
}
- (void)dismiss {
    NSWindow *browser = self.browser;
    self.browser = nil; [browser removeChildWindow:self]; [self orderOut:nil];
    [browser makeKeyWindow];
}
@end

void ZenOpenPalette(NSWindow *window, BOOL newTab) {
    if (!window) return;
    if (!palette) palette = [ZenURLPalette new];
    if (palette.visible) [palette dismiss];
    palette.browser = window; palette.createsTab = newTab; palette.tabs = ZenNativeTabs(window);
    palette.search.stringValue = @""; palette.selectedIndex = 0; [palette refresh];
    [window addChildWindow:palette ordered:NSWindowAbove]; [palette makeKeyAndOrderFront:nil];
    [palette makeFirstResponder:palette.search];
}

BOOL ZenPaletteIsOpen(void) { return palette.visible; }
void ZenClosePalette(void) { if (palette.visible) [palette dismiss]; }

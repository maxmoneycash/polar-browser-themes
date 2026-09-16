#import <AppKit/AppKit.h>

extern NSString * const PTThemeDidChange;
NSDictionary *PTTheme(void);
NSColor *PTColor(NSString *section, NSString *key);
CGFloat PTNumber(NSString *section, NSString *key);
void PTThemeStart(void);
BOOL PTValidate(id value, NSDictionary *rule, NSString *path, NSString **error);
void PTLayoutFrame(NSView *root, BOOL enabled, void (^nativeLayout)(void));

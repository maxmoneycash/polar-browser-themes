#import "ThemeRuntime.h"
#import "ThemeData.h"
#import <math.h>

NSString * const PTThemeDidChange = @"PolarThemesDidChange";
static NSDictionary *activeTheme;
static NSData *lastData;
static BOOL started;

NSDictionary *PTTheme(void) {
    if (!activeTheme) activeTheme = [NSJSONSerialization JSONObjectWithData:[@(PTDefaultJSON) dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    return activeTheme;
}

NSColor *PTColor(NSString *section, NSString *key) {
    NSString *hex = PTTheme()[section][key];
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:[hex substringFromIndex:1]] scanHexInt:&rgb];
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255. green:((rgb >> 8) & 255) / 255. blue:(rgb & 255) / 255. alpha:1];
}

CGFloat PTNumber(NSString *section, NSString *key) { return [PTTheme()[section][key] doubleValue]; }

BOOL PTValidate(id value, NSDictionary *rule, NSString *path, NSString **error) {
    NSString *type = rule[@"type"];
    BOOL isNumber = [value isKindOfClass:NSNumber.class];
    BOOL isBoolean = isNumber && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
    BOOL valid = YES;
    if ([type isEqual:@"object"]) valid = [value isKindOfClass:NSDictionary.class];
    if ([type isEqual:@"string"]) valid = [value isKindOfClass:NSString.class];
    if ([type isEqual:@"boolean"]) valid = isBoolean;
    if ([type isEqual:@"number"] || [type isEqual:@"integer"]) {
        valid = isNumber && !isBoolean && isfinite([value doubleValue]);
        if (valid && [type isEqual:@"integer"]) valid = trunc([value doubleValue]) == [value doubleValue];
    }
    if (!valid) { if (error) *error = [path stringByAppendingFormat:@" must be %@", type]; return NO; }
    if ((rule[@"const"] && ![value isEqual:rule[@"const"]]) || (rule[@"enum"] && ![rule[@"enum"] containsObject:value])) {
        if (error) *error = [path stringByAppendingString:@" has an unsupported value"]; return NO;
    }
    if ([type isEqual:@"object"]) {
        for (NSString *key in rule[@"required"]) {
            if (!value[key]) { if (error) *error = [path stringByAppendingFormat:@".%@ is required", key]; return NO; }
        }
        for (NSString *key in value) {
            NSDictionary *child = rule[@"properties"][key];
            if (!child) { if (error) *error = [path stringByAppendingFormat:@".%@ is unknown", key]; return NO; }
            if (!PTValidate(value[key], child, [path stringByAppendingFormat:@".%@", key], error)) return NO;
        }
    }
    if ([type isEqual:@"string"]) {
        NSUInteger length = [value length];
        if ((rule[@"minLength"] && length < [rule[@"minLength"] unsignedIntegerValue]) ||
            (rule[@"maxLength"] && length > [rule[@"maxLength"] unsignedIntegerValue])) valid = NO;
        if (rule[@"pattern"]) {
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:rule[@"pattern"] options:0 error:NULL];
            NSTextCheckingResult *match = [regex firstMatchInString:value options:0 range:NSMakeRange(0, length)];
            valid = valid && match && NSEqualRanges(match.range, NSMakeRange(0, length));
        }
    }
    if ([type isEqual:@"number"] || [type isEqual:@"integer"]) {
        double n = [value doubleValue];
        if ((rule[@"minimum"] && n < [rule[@"minimum"] doubleValue]) || (rule[@"maximum"] && n > [rule[@"maximum"] doubleValue])) valid = NO;
    }
    if (!valid && error) *error = [path stringByAppendingString:@" is outside its permitted format or range"];
    return valid;
}

static NSString *configDirectory(void) {
    NSString *override = NSProcessInfo.processInfo.environment[@"POLAR_THEMES_HOME"];
    return override.length ? override.stringByExpandingTildeInPath : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Polar Themes"];
}

static void reload(void) {
    NSString *path = [configDirectory() stringByAppendingPathComponent:@"current.json"];
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
    if (!attributes || [attributes fileSize] > 32768) return;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || [data isEqual:lastData] || data.length > 32768) return;
    lastData = data;
    NSError *parseError = nil;
    id theme = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
    NSDictionary *schema = [NSJSONSerialization JSONObjectWithData:[@(PTSchemaJSON) dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    NSString *error = nil;
    if (!theme || !PTValidate(theme, schema, @"theme", &error)) {
        NSLog(@"[Polar Themes] Kept the last valid theme: %@", error ?: @"invalid JSON"); return;
    }
    activeTheme = theme;
    [NSNotificationCenter.defaultCenter postNotificationName:PTThemeDidChange object:nil];
    NSLog(@"[Polar Themes] Loaded %@", theme[@"id"]);
}

void PTThemeStart(void) {
    if (started) return;
    started = YES;
    PTTheme();
    reload();
    // One small local file, once a second. Common run-loop mode also updates an
    // open palette. Bad edits preserve the last valid appearance.
    NSTimer *timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *_) { reload(); }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
}

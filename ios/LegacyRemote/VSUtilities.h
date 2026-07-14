#import <UIKit/UIKit.h>

static inline NSString *VSString(id value, NSString *fallback) {
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value stringValue];
    return fallback ?: @"";
}

static inline NSArray *VSArray(id value) {
    return [value isKindOfClass:[NSArray class]] ? value : [NSArray array];
}

static inline NSDictionary *VSDictionary(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? value : [NSDictionary dictionary];
}

static inline UIImage *VSInterfaceIcon(NSString *kind) {
    static NSMutableDictionary *cache = nil; if (!cache) cache = [[NSMutableDictionary alloc] init];
    UIImage *cached = [cache objectForKey:kind]; if (cached) return cached;
    CGSize size = CGSizeMake(24, 24); UIGraphicsBeginImageContextWithOptions(size, NO, 0); CGContextRef c = UIGraphicsGetCurrentContext();
    UIColor *color = [UIColor colorWithRed:0.16 green:0.35 blue:0.52 alpha:1.0]; CGContextSetStrokeColorWithColor(c, color.CGColor); CGContextSetFillColorWithColor(c, color.CGColor); CGContextSetLineWidth(c, 2.0);
    if ([kind isEqual:@"folder"]) { UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(2, 7, 20, 14) cornerRadius:2]; [p stroke]; CGContextFillRect(c, CGRectMake(4, 4, 8, 4)); }
    else if ([kind isEqual:@"chat"]) { UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(2, 3, 20, 15) cornerRadius:4]; [p stroke]; UIBezierPath *tail = [UIBezierPath bezierPath]; [tail moveToPoint:CGPointMake(7, 18)]; [tail addLineToPoint:CGPointMake(5, 22)]; [tail addLineToPoint:CGPointMake(12, 18)]; [tail stroke]; }
    else if ([kind isEqual:@"editor"]) { CGContextMoveToPoint(c, 3, 9); CGContextAddLineToPoint(c, 3, 3); CGContextAddLineToPoint(c, 9, 3); CGContextMoveToPoint(c, 15, 3); CGContextAddLineToPoint(c, 21, 3); CGContextAddLineToPoint(c, 21, 9); CGContextMoveToPoint(c, 21, 15); CGContextAddLineToPoint(c, 21, 21); CGContextAddLineToPoint(c, 15, 21); CGContextMoveToPoint(c, 9, 21); CGContextAddLineToPoint(c, 3, 21); CGContextAddLineToPoint(c, 3, 15); CGContextStrokePath(c); }
    else { CGContextFillEllipseInRect(c, CGRectMake(6, 6, 12, 12)); }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); if (image) [cache setObject:image forKey:kind]; return image;
}

static inline UIImage *VSBeveledButtonImage(BOOL pressed) {
    static UIImage *normal = nil, *highlighted = nil; UIImage **slot = pressed ? &highlighted : &normal; if (*slot) return *slot;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(30, 30), NO, 0); CGContextRef c = UIGraphicsGetCurrentContext();
    UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5, 0.5, 29, 29) cornerRadius:7]; [shape addClip];
    UIColor *top = pressed ? [UIColor colorWithRed:0.48 green:0.59 blue:0.70 alpha:1] : [UIColor colorWithRed:0.98 green:0.99 blue:1 alpha:1];
    UIColor *bottom = pressed ? [UIColor colorWithRed:0.70 green:0.78 blue:0.86 alpha:1] : [UIColor colorWithRed:0.72 green:0.79 blue:0.86 alpha:1];
    CGContextSetFillColorWithColor(c, top.CGColor); CGContextFillRect(c, CGRectMake(0, 0, 30, 15)); CGContextSetFillColorWithColor(c, bottom.CGColor); CGContextFillRect(c, CGRectMake(0, 15, 30, 15));
    CGContextSetStrokeColorWithColor(c, [UIColor colorWithRed:0.35 green:0.44 blue:0.54 alpha:1].CGColor); CGContextSetLineWidth(c, 1); [shape stroke];
    UIImage *image = [UIGraphicsGetImageFromCurrentImageContext() resizableImageWithCapInsets:UIEdgeInsetsMake(7, 7, 7, 7)]; UIGraphicsEndImageContext(); *slot = [image retain]; return *slot;
}

#import "VirtualDisplayBridge.h"
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <objc/runtime.h>

static const NSUInteger InsoMacWidth = 1280;
static const NSUInteger InsoMacHeight = 720;

BOOL InsoMacVirtualDisplayLayoutIsUsable(InsoMacVirtualDisplayLayout layout, BOOL requiresSecondaryDisplay) {
    return layout.online && layout.active && !layout.asleep && !layout.builtIn && !layout.mirrored
        && (!requiresSecondaryDisplay || !layout.main)
        && layout.width == InsoMacWidth && layout.height == InsoMacHeight;
}

@protocol InsoMacDisplayInitializer
- (instancetype)initWithDescriptor:(id)descriptor;
@end

@protocol InsoMacModeInitializer
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(CGFloat)rate;
@end

static BOOL InsoMacFail(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"io.github.underconnor.insomac.virtual-display" code:1
                                       userInfo:@{NSLocalizedDescriptionKey: message}];
    return NO;
}

static BOOL InsoMacSignature(Class cls, NSString *name, const char *result, NSArray<NSString *> *arguments) {
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != arguments.count + 2 || strcmp(signature.methodReturnType, result)) return NO;
    for (NSUInteger index = 0; index < arguments.count; index++) {
        if (strcmp([signature getArgumentTypeAtIndex:index + 2], arguments[index].UTF8String)) return NO;
    }
    return YES;
}

static NSSet<NSNumber *> *InsoMacOnlineIDs(void) {
    CGDirectDisplayID ids[32];
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(32, ids, &count) != kCGErrorSuccess || count == 32) return nil;
    NSMutableSet *result = [NSMutableSet set];
    for (uint32_t index = 0; index < count; index++) [result addObject:@(ids[index])];
    return result;
}

@implementation InsoMacVirtualDisplayOwner {
    id _display;
    uint32_t _displayID;
    NSSet<NSNumber *> *_baselineIDs;
}

+ (NSString *)unavailabilityReason {
    Class descriptor = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class display = NSClassFromString(@"CGVirtualDisplay");
    Class settings = NSClassFromString(@"CGVirtualDisplaySettings");
    Class mode = NSClassFromString(@"CGVirtualDisplayMode");
    if (!descriptor || !display || !settings || !mode) return @"This macOS runtime has no virtual display API.";
    BOOL valid = InsoMacSignature(descriptor, @"init", @encode(id), @[])
        && InsoMacSignature(settings, @"init", @encode(id), @[])
        && InsoMacSignature(descriptor, @"setName:", @encode(void), @[@(@encode(id))])
        && InsoMacSignature(descriptor, @"setQueue:", @encode(void), @[@(@encode(id))])
        && InsoMacSignature(descriptor, @"setMaxPixelsWide:", @encode(void), @[@(@encode(unsigned int))])
        && InsoMacSignature(descriptor, @"setMaxPixelsHigh:", @encode(void), @[@(@encode(unsigned int))])
        && InsoMacSignature(descriptor, @"setSizeInMillimeters:", @encode(void), @[@(@encode(CGSize))])
        && InsoMacSignature(descriptor, @"setVendorID:", @encode(void), @[@(@encode(unsigned int))])
        && InsoMacSignature(descriptor, @"setProductID:", @encode(void), @[@(@encode(unsigned int))])
        && InsoMacSignature(descriptor, @"setSerialNum:", @encode(void), @[@(@encode(unsigned int))])
        && InsoMacSignature(settings, @"setModes:", @encode(void), @[@(@encode(id))])
        && InsoMacSignature(settings, @"setHiDPI:", @encode(void), @[@(@encode(unsigned int))])
        && InsoMacSignature(mode, @"initWithWidth:height:refreshRate:", @encode(id),
                       @[@(@encode(unsigned int)), @(@encode(unsigned int)), @(@encode(CGFloat))])
        && InsoMacSignature(display, @"initWithDescriptor:", @encode(id), @[@(@encode(id))])
        && InsoMacSignature(display, @"applySettings:", @encode(BOOL), @[@(@encode(id))])
        && InsoMacSignature(display, @"displayID", @encode(unsigned int), @[]);
    return valid ? nil : @"The private virtual display API has an unsupported signature.";
}

- (BOOL)hasResources { return _display != nil || _baselineIDs != nil; }
- (uint32_t)displayID { return _displayID; }

- (BOOL)startWithError:(NSError **)error {
    if (self.hasResources) return InsoMacFail(error, @"Release the previous virtual display before starting again.");
    NSString *reason = self.class.unavailabilityReason;
    if (reason) return InsoMacFail(error, reason);
    NSSet *baseline = InsoMacOnlineIDs();
    if (!baseline) return InsoMacFail(error, @"Could not read the current display list. Try again.");
    @try {
        id descriptor = [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
        id settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
        id mode = [(id<InsoMacModeInitializer>)[NSClassFromString(@"CGVirtualDisplayMode") alloc]
                   initWithWidth:(unsigned int)InsoMacWidth height:(unsigned int)InsoMacHeight refreshRate:60.0];
        if (!descriptor || !settings || !mode) return InsoMacFail(error, @"Virtual display setup was refused. Choose Keep Screen On instead.");
        void (*setObject)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
        void (*setUInt)(id, SEL, unsigned int) = (void (*)(id, SEL, unsigned int))objc_msgSend;
        setObject(descriptor, NSSelectorFromString(@"setName:"), @"InsoMac Experimental");
        setObject(descriptor, NSSelectorFromString(@"setQueue:"), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
        setUInt(descriptor, NSSelectorFromString(@"setMaxPixelsWide:"), (unsigned int)InsoMacWidth);
        setUInt(descriptor, NSSelectorFromString(@"setMaxPixelsHigh:"), (unsigned int)InsoMacHeight);
        ((void (*)(id, SEL, CGSize))objc_msgSend)(descriptor, NSSelectorFromString(@"setSizeInMillimeters:"), CGSizeMake(339, 191));
        setUInt(descriptor, NSSelectorFromString(@"setVendorID:"), 0x4D43);
        setUInt(descriptor, NSSelectorFromString(@"setProductID:"), 1);
        setUInt(descriptor, NSSelectorFromString(@"setSerialNum:"), arc4random_uniform(UINT32_MAX - 1) + 1);
        setObject(settings, NSSelectorFromString(@"setModes:"), @[mode]);
        setUInt(settings, NSSelectorFromString(@"setHiDPI:"), 0);
        _baselineIDs = baseline;
        _display = [(id<InsoMacDisplayInitializer>)[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
        if (!_display) return InsoMacFail(error, @"macOS refused the virtual display. Choose Keep Screen On instead.");
        _displayID = ((unsigned int (*)(id, SEL))objc_msgSend)(_display, NSSelectorFromString(@"displayID"));
        if (!_displayID || [baseline containsObject:@(_displayID)]) {
            _displayID = 0;
            return InsoMacFail(error, @"Virtual display ownership could not be verified. Turn off and try again.");
        }
        BOOL applied = ((BOOL (*)(id, SEL, id))objc_msgSend)(_display, NSSelectorFromString(@"applySettings:"), settings);
        if (!applied) return InsoMacFail(error, @"macOS refused the 1280 × 720 virtual mode. Choose Keep Screen On instead.");
        for (NSUInteger attempt = 0; attempt < 75; attempt++) {
            if ([self validateRequiringSecondaryDisplay:YES error:nil]) return YES;
            [NSThread sleepForTimeInterval:0.02];
        }
        return InsoMacFail(error, @"The virtual display did not become usable. Turn off and try again.");
    } @catch (NSException * __unused exception) {
        return InsoMacFail(error, @"The private virtual display API failed. Turn off, then choose Keep Screen On.");
    }
}

- (BOOL)validateWithError:(NSError **)error {
    return [self validateRequiringSecondaryDisplay:NO error:error];
}

- (BOOL)validateRequiringSecondaryDisplay:(BOOL)requiresSecondaryDisplay error:(NSError **)error {
    CGRect bounds = CGDisplayBounds(_displayID);
    InsoMacVirtualDisplayLayout layout = {
        .online = CGDisplayIsOnline(_displayID), .active = CGDisplayIsActive(_displayID),
        .asleep = CGDisplayIsAsleep(_displayID), .builtIn = CGDisplayIsBuiltin(_displayID),
        .main = CGDisplayIsMain(_displayID), .mirrored = CGDisplayMirrorsDisplay(_displayID) != kCGNullDirectDisplay,
        .width = bounds.size.width, .height = bounds.size.height
    };
    if (!_display || !_displayID || !InsoMacVirtualDisplayLayoutIsUsable(layout, requiresSecondaryDisplay)) {
        return InsoMacFail(error, @"The virtual display is unavailable or its layout changed. Turn off and try again.");
    }
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(_displayID);
    BOOL valid = mode && CGDisplayModeGetWidth(mode) == InsoMacWidth && CGDisplayModeGetHeight(mode) == InsoMacHeight
        && CGDisplayModeGetPixelWidth(mode) == InsoMacWidth && CGDisplayModeGetPixelHeight(mode) == InsoMacHeight;
    if (mode) CGDisplayModeRelease(mode);
    return valid ? YES : InsoMacFail(error, @"Virtual display resolution readback failed. Turn off and try again.");
}

- (BOOL)stopWithError:(NSError **)error {
    _display = nil;
    if (!_baselineIDs) return YES;
    for (NSUInteger attempt = 0; attempt < 100; attempt++) {
        NSSet *current = InsoMacOnlineIDs();
        BOOL absent = current && (_displayID ? ![current containsObject:@(_displayID)]
                                             : [current isSubsetOfSet:_baselineIDs]);
        if (absent) {
            _displayID = 0;
            _baselineIDs = nil;
            return YES;
        }
        [NSThread sleepForTimeInterval:0.02];
    }
    return InsoMacFail(error, @"macOS has not removed the virtual display yet. Choose Release Again, or quit InsoMac.");
}

@end

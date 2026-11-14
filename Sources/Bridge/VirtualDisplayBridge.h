#import <Foundation/Foundation.h>
#include <stdbool.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    bool online;
    bool active;
    bool asleep;
    bool builtIn;
    bool main;
    bool mirrored;
    double width;
    double height;
} InsoMacVirtualDisplayLayout;

// Initial creation must be secondary. Later OS/user promotion of the same owned
// display to main is allowed without reconfiguring any physical display.
FOUNDATION_EXPORT BOOL InsoMacVirtualDisplayLayoutIsUsable(InsoMacVirtualDisplayLayout layout,
                                                          BOOL requiresSecondaryDisplay);

// This wrapper uses private interfaces only after runtime signature checks.
@interface InsoMacVirtualDisplayOwner : NSObject
@property(class, readonly, nullable) NSString *unavailabilityReason;
@property(nonatomic, readonly) BOOL hasResources;
@property(nonatomic, readonly) uint32_t displayID;
- (BOOL)startWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)validateWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)stopWithError:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END

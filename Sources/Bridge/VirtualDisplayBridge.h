#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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

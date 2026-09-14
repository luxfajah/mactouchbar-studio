#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface CGVirtualDisplayDescriptor : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) uint32_t maxPixelsWide;
@property (nonatomic) uint32_t maxPixelsHigh;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, copy) void (^terminationHandler)(id display);
@end

@interface CGVirtualDisplaySettings : NSObject
@property (nonatomic) uint32_t pixelsWide;
@property (nonatomic) uint32_t pixelsHigh;
@property (nonatomic) CGFloat refreshRate;
- (instancetype)init;
@end

@interface CGVirtualDisplayMode : NSObject
@property (nonatomic) uint32_t width;
@property (nonatomic) uint32_t height;
@property (nonatomic) CGFloat refreshRate;
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height refreshRate:(CGFloat)refreshRate;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property (nonatomic, readonly) CGDirectDisplayID displayID;
@end

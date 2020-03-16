#import <Flutter/Flutter.h>
#import <Repm/Repm.h>

@interface ReplicachePlugin : NSObject<FlutterPlugin, RepmLogger> {
    FlutterMethodChannel* channel;
}

@end

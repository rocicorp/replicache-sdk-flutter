#import <Flutter/Flutter.h>
#import <Repm/Repm.h>

@interface ReplicantPlugin : NSObject<FlutterPlugin, RepmLogger> {
  FlutterMethodChannel* channel;
}

@end

#import "ReplicachePlugin.h"

#import <Repm/Repm.h>

const NSString* CHANNEL_NAME = @"replicache.dev";

@implementation ReplicachePlugin
  dispatch_queue_t generalQueue;
  dispatch_queue_t pullQueue;

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:CHANNEL_NAME
            binaryMessenger:[registrar messenger]];
  ReplicachePlugin* instance = [[ReplicachePlugin alloc] init];
  instance->channel = channel;
  [registrar addMethodCallDelegate:instance channel:channel];

  // Most Replicache operations happen serially, but not blocking UI thread.
  generalQueue = dispatch_queue_create("dev.roci.Replicache", NULL);

  // Pull uses a concurrent queue because we don't want it to block other Replicache operations.
  pullQueue = dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

  dispatch_async(generalQueue, ^(void){
    RepmInit([instance replicacheDir], @"", instance);
  });
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  dispatch_queue_t queue;
  if ([call.method isEqualToString:@"pull"]) {
    queue = pullQueue;
  } else {
    queue = generalQueue;
  }

  // The arguments passed from Flutter is a two-element array:
  // 0th element is the name of the database to call on
  // 1st element is the rpc argument (UTF8 encoded string containing JSON)
  NSArray* args = (NSArray*)call.arguments;

  dispatch_async(queue, ^(void){
    NSError* err = nil;
    NSData* res = RepmDispatch([args objectAtIndex:0], call.method, [[args objectAtIndex:1] data], &err);
    dispatch_async(dispatch_get_main_queue(), ^(void){
      if (err != nil) {
        result([FlutterError errorWithCode:@"UNAVAILABLE"
                                  message:[err localizedDescription]
                                  details:nil]);
      } else {
        result([[NSString alloc] initWithData:res
                                    encoding:NSUTF8StringEncoding]);
      }
    });
  });
};

-(NSString*)replicacheDir {
  NSFileManager* sharedFM = [NSFileManager defaultManager];
  NSArray* possibleURLs = [sharedFM URLsForDirectory:NSApplicationSupportDirectory
                                           inDomains:NSUserDomainMask];
  NSURL* appSupportDir = nil;
  NSURL* dataDir = nil;

  if ([possibleURLs count] < 1) {
    [self log:[NSString stringWithFormat:@"Could not locate application support directory: %@", dataDir]];
    return nil;
  }

  // Use the first directory (if multiple are returned)
  appSupportDir = [possibleURLs objectAtIndex:0];
  NSString* appBundleID = [[NSBundle mainBundle] bundleIdentifier];
  dataDir = [appSupportDir URLByAppendingPathComponent:appBundleID];
  dataDir = [dataDir URLByAppendingPathComponent:@"replicache"];

  NSError* err;
  [sharedFM createDirectoryAtPath:[dataDir path] withIntermediateDirectories:TRUE attributes:nil error:&err];
  if (err != nil) {
    [self log:[NSString stringWithFormat:@"Replicache: Could not create data directory: %@", dataDir]];
    return nil;
  }

  return [dataDir path];
}

- (BOOL)write:(NSData* _Nullable)data n:(long* _Nullable)len error:(NSError* _Nullable* _Nullable)error {
  [self log:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
  *len = [data length];
  return true;
}

-(void)log:(NSString*)message {
  dispatch_async(dispatch_get_main_queue(), ^(void){
    [self->channel invokeMethod:@"log" arguments:message];
  });
}

@end

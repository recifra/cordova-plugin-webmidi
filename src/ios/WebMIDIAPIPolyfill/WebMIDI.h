#import <Cordova/CDVPlugin.h>

@interface WebMIDI : CDVPlugin

- (void) onready:(CDVInvokedUrlCommand *)command;

- (void) send:(CDVInvokedUrlCommand *)command;

- (void) clear:(CDVInvokedUrlCommand *)command;

@end

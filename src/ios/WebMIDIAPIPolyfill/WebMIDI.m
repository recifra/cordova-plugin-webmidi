#include "WebMIDI.h"
#import "MIDIDriver.h"
#import <mach/mach_time.h>

@interface WebMIDI ()

    @property (nonatomic, strong) MIDIDriver *midiDriver;
    @property (nonatomic, copy) BOOL (^confirmSysExAvailability)(NSString *url);
    @property (nonatomic) BOOL sysexEnabled;

@end

@implementation WebMIDI
    /**
     * Initialize MIDI Driver at Plugin initialization
     */
    - (void)pluginInitialize
    {
        _midiDriver = [[MIDIDriver alloc] init];
        _confirmSysExAvailability = ^(NSString *url) { return YES; };
        NSLog(@"[WebMIDI.m]%@", @"[pluginInitialize] OK");
    }

    /*
    * Initialize ports and listen for events
    */
    - (void) onready:(CDVInvokedUrlCommand *)command
    {
        [self.commandDelegate runInBackground:^{
            __block uint64_t timestampOrigin = 0;
            __block NSString* callbackId = command.callbackId;

            mach_timebase_info_data_t base;
            mach_timebase_info(&base);

            NSDictionary* dict = command.arguments[0];
            
            NSDictionary *MIDIoptions = dict[@"options"];
            NSString *url = dict[@"url"];

            self.sysexEnabled = NO;
            id sysexOption = MIDIoptions[@"sysex"];
            if ([sysexOption isKindOfClass:[NSNumber class]] && [sysexOption boolValue] == YES) {
                if (self.confirmSysExAvailability) {
                    if (self.confirmSysExAvailability(url) == NO) {
                        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK
                            messageAsDictionary: @{ @"action": @"onNotReady" }];
                        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
                        return;
                    } else {
                        self.sysexEnabled = YES;
                    }
                } else {
                    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK
                        messageAsDictionary: @{ @"action": @"onNotReady" }];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
                    return;
                }
            }
            
            if (self.midiDriver.isAvailable == NO) {
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK
                    messageAsDictionary: @{ @"action": @"onNotReady" }];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
                return;
            }
            __weak WebMIDI* weakSelf = self;
            
            // Setup the callback for receiving MIDI message.
            self.midiDriver.onMessageReceived = ^(ItemCount index, NSData *receivedData, uint64_t timestamp) {
                NSMutableArray *array = [NSMutableArray arrayWithCapacity:[receivedData length]];
                BOOL sysexIncluded = NO;
                for (int i = 0; i < [receivedData length]; i++) {
                    unsigned char byte = ((unsigned char *)[receivedData bytes])[i];
                    [array addObject:[NSNumber numberWithUnsignedChar:byte]];

                    if (byte == 0xf0) {
                        sysexIncluded = YES;
                    }
                }
                
                if (weakSelf.sysexEnabled == NO && sysexIncluded == YES) {
                    // should throw InvalidAccessError exception here
                    return;
                }
                double deltaTime_ms = (double)(timestamp - timestampOrigin) * base.numer / base.denom / 1000000.0;

                NSDictionary* params = @{
                    @"action": @"receiveMIDIMessage",
                    @"index": [NSNumber numberWithUnsignedLong: index],
                    @"time": [NSNumber numberWithDouble: deltaTime_ms],
                    @"data": array,
                };
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsDictionary: params];
                [pluginResult setKeepCallbackAsBool:YES];
                [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
            };

            __weak MIDIDriver *midiDriver = self.midiDriver;
            self.midiDriver.onDestinationPortAdded = ^(ItemCount index) {
                NSDictionary *info = [midiDriver portinfoFromDestinationEndpointIndex:index];

                NSDictionary* params = @{
                    @"action": @"addDestination",
                    @"index": [NSNumber numberWithUnsignedLong: index],
                    @"data": info,
                };
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsDictionary: params];
                [pluginResult setKeepCallbackAsBool:YES];
                [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
            };

            self.midiDriver.onSourcePortAdded = ^(ItemCount index) {
                NSDictionary *info = [midiDriver portinfoFromSourceEndpointIndex:index];
                
                NSDictionary* params = @{
                    @"action": @"addSource",
                    @"index": [NSNumber numberWithUnsignedLong: index],
                    @"data": info,
                };
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsDictionary: params];
                [pluginResult setKeepCallbackAsBool:YES];
                [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
            };
            
            self.midiDriver.onDestinationPortRemoved = ^(ItemCount index) {
                NSDictionary* params = @{
                    @"action": @"removeDestination",
                    @"index": [NSNumber numberWithUnsignedLong: index],
                };
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsDictionary: params];
                [pluginResult setKeepCallbackAsBool:YES];
                [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
            };
            
            self.midiDriver.onSourcePortRemoved = ^(ItemCount index) {
                NSDictionary* params = @{
                    @"action": @"removeSource",
                    @"index": [NSNumber numberWithUnsignedLong: index],
                };
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsDictionary: params];
                [pluginResult setKeepCallbackAsBool:YES];
                [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
            };
            
            // Send all MIDI ports information when the setup request is received.
            ItemCount srcCount  = [self.midiDriver numberOfSources];
            ItemCount destCount = [self.midiDriver numberOfDestinations];

            NSMutableArray *srcs  = [NSMutableArray arrayWithCapacity:srcCount];
            NSMutableArray *dests = [NSMutableArray arrayWithCapacity:destCount];


            for (ItemCount srcIndex = 0; srcIndex < srcCount; srcIndex++) {
                NSDictionary *info = [self.midiDriver portinfoFromSourceEndpointIndex:srcIndex];
                if (info == nil) {
                    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK
                        messageAsDictionary: @{ @"action": @"onNotReady" }];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
                    return;
                }
                [srcs addObject:info];
            }

            for (ItemCount destIndex = 0; destIndex < destCount; destIndex++) {
                NSDictionary *info = [self.midiDriver portinfoFromDestinationEndpointIndex:destIndex];
                if (info == nil) {
                    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK
                        messageAsDictionary: @{ @"action": @"onNotReady" }];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
                    return;
                }
                [dests addObject:info];
            }
            timestampOrigin = mach_absolute_time();

            NSDictionary* params = @{
                @"action": @"onReady",
                @"sources": srcs,
                @"destinations": dests,
            };
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsDictionary: params];
            [pluginResult setKeepCallbackAsBool:YES];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
        }];
    }

    /**
     * Send data to output port
     */
    - (void) send:(CDVInvokedUrlCommand *)command
    {
        [self.commandDelegate runInBackground:^{
            NSDictionary* dict = command.arguments[0];
            NSArray *array = dict[@"data"];
            NSMutableData *data = [NSMutableData dataWithCapacity:[array count]];
            BOOL sysexIncluded = NO;
            for (NSNumber *number in array) {
                uint8_t byte = [number unsignedIntegerValue];
                [data appendBytes:&byte length:1];

                if (byte == 0xf0) {
                    sysexIncluded = YES;
                }
            }

            if (self.sysexEnabled == NO && sysexIncluded == YES) {
                return;
            }
            
            ItemCount outputIndex = [dict[@"outputPortIndex"] unsignedLongValue];
            float deltatime = [dict[@"deltaTime"] floatValue];
            [self.midiDriver sendMessage:data toDestinationIndex:outputIndex deltatime:deltatime];
        }];
    }

    /**
     * Clear destination output port
     */
    - (void) clear:(CDVInvokedUrlCommand *)command
    {
        [self.commandDelegate runInBackground:^{
            NSDictionary* options = command.arguments[0];
            ItemCount outputIndex = [options[@"outputPortIndex"] unsignedLongValue];
            [self.midiDriver clearWithDestinationIndex:outputIndex];
        }];
    }

@end

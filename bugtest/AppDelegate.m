
//
//  AppDelegate.m

#import "AppDelegate.h"
#include <SDMMobileDevice/SDMMobileDevice.h>
#import "Core.h"
#import "SDMMobileDevice/SDMMD_Connection_Internal.h"


@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    SDMMobileDevice;
    devices = SDMMD_AMDCreateDeviceList();
    iterator = 0;
    refreshTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
}

-(void)refresh:(NSTimer*)timer {
    
    NSLog(@"Count = %i",iterator++);

    if ((int)CFArrayGetCount(devices) == 0) {
        NSLog(@"No device found");
        return;
    }
    
    sdmmd_return_t result;
    SDMMD_AMDeviceRef device = (SDMMD_AMDeviceRef)CFArrayGetValueAtIndex(devices, 0);
    if (SDMMD_AMDeviceIsValid(device)) {
        result = SDMMD_AMDeviceConnect(device);
        if (SDM_MD_CallSuccessful(result)) {
            result = SDMMD_AMDeviceStartSession(device);
            if (SDM_MD_CallSuccessful(result)) SDMMD_AMDeviceStopSession(device);
            SDMMD_AMDeviceDisconnect(device);
            
            CFMutableDictionaryRef request_ioreg = SDMMD__CreateRequestDict(CFSTR("Request"));
            CFDictionarySetValue(request_ioreg, CFSTR("Request"), CFSTR("IORegistry"));
            
            CFTypeRef deviceUDID = SDMMD_AMDeviceCopyUDID(device);
            if (!deviceUDID) {
                deviceUDID = SDMMD_AMDeviceCopyValue(device, NULL, CFSTR(kUniqueDeviceID));
            }

            NSDictionary *myDictionary = SendDeviceCommand((char*)[(NSString*)CFBridgingRelease(deviceUDID) UTF8String], request_ioreg);
        } else NSLog(@"Connect failed");
    } else NSLog(@"No valid device");
    
}


SDMMD_AMConnectionRef AttachToDeviceAndService(SDMMD_AMDeviceRef device, char *service) {
    SDMMD_AMConnectionRef serviceCon = NULL;
    if (!device) {
        printf("Could not find device with that UDID\n");
        return NULL;
    }
    
    sdmmd_return_t result = SDMMD_AMDeviceConnect(device);
    if (!SDM_MD_CallSuccessful(result)) {
        return NULL;
    }
    
    result = SDMMD_AMDeviceStartSession(device);
    if (!SDM_MD_CallSuccessful(result)) {
        SDMMD_AMDeviceDisconnect(device);
        return NULL;
    }
    
    CFStringRef serviceString = CFStringCreateWithCString(kCFAllocatorDefault, service, kCFStringEncodingUTF8);
    result = SDMMD_AMDeviceStartService(device, serviceString, NULL, &serviceCon);
    if (!SDM_MD_CallSuccessful(result)) {
        SDMMD_AMDeviceStopSession(device);
        SDMMD_AMDeviceDisconnect(device);
        CFSafeRelease(serviceString);
        return NULL;
    }
    
    CFTypeRef deviceName = SDMMD_AMDeviceCopyValue(device, NULL, CFSTR(kDeviceName));
    char *name = CreateCStringFromCFStringRef(deviceName);
    if (!name) {
        int unnamed_str_len = strlen("unnamed device");
        name = calloc(1, sizeof(char[unnamed_str_len]));
        memcpy(name, "unnamed device", sizeof(char[unnamed_str_len]));
    }
    //LOGGING                    printf("Connected to %s on \"%s\" ...\n",name,service);
    CFSafeRelease(deviceName);
    Safe(free,name);
    
    SDMMD_AMDeviceStopSession(device);
    SDMMD_AMDeviceDisconnect(device);
    
    return serviceCon;
}


SDMMD_AMDeviceRef FindDeviceFromUDID(char *udid) {
    CFArrayRef devices = SDMMD_AMDCreateDeviceList();
    CFIndex numberOfDevices = CFArrayGetCount(devices);
    SDMMD_AMDeviceRef device = NULL;
    if (numberOfDevices) {
        // return type (uint32_t) corresponds with known return codes (SDMMD_Error.h)
        bool foundDevice = false;
        char *deviceId;
        uint32_t index;
        // Iterating over connected devices
        for (index = 0; index < numberOfDevices; index++) {
            SDMMD_AMDeviceRef device = (SDMMD_AMDeviceRef)CFArrayGetValueAtIndex(devices, index);
            CFTypeRef deviceUDID = SDMMD_AMDeviceCopyUDID(device);
            if (deviceUDID) {
                deviceId = (char*)CreateCStringFromCFStringRef(deviceUDID);
                CFSafeRelease(deviceUDID);
                if (strncmp(udid, deviceId, strlen(deviceId)) == 0x0) {
                    foundDevice = true;
                }
                free(deviceId);
                if (foundDevice) {
                    break;
                }
            }
        }
        if (foundDevice) {
            device = SDMMD_AMDeviceCreateCopy((SDMMD_AMDeviceRef)CFArrayGetValueAtIndex(devices, index));
        }
    } else {
        printf("No devices connected.\n");
    }
    CFSafeRelease(devices);
    return device;
}


NSDictionary* SendDeviceCommand(char *udid, CFDictionaryRef request) {
    SDMMD_AMDeviceRef device = FindDeviceFromUDID(udid);
    if (!device) {
        return nil;
    }
    
    if (!request) {
        CFSafeRelease(device);
        return nil;
    }
    
    SDMMD_AMConnectionRef powerDiag = AttachToDeviceAndService(device, AMSVC_DIAG_RELAY);
    CFSafeRelease(device);
    SocketConnection socket = SDMMD_TranslateConnectionToSocket(powerDiag);
    sdmmd_return_t result = SDMMD_ServiceSendMessage(socket, request, kCFPropertyListXMLFormat_v1_0);
    
    if (!SDM_MD_CallSuccessful(result)) {
        //ServiceSendMEssage not completed
        return nil;
    }
    
    printf("Sent command to device, this could take up to 5 seconds.\n");
    CFDictionaryRef response;
    result = SDMMD_ServiceReceiveMessage(socket, PtrCast(&response, CFPropertyListRef*));
    NSLog(@"Result - 0x%02x",(unsigned int)result);
    
    if (!SDM_MD_CallSuccessful(result)) {
        return nil;
    }
    
    if (!response) return nil;
    
    NSDictionary *responseDict = (__bridge NSDictionary*)response;
    CFRelease(response);
    return responseDict;
}


@end

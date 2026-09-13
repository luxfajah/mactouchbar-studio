#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <CommonCrypto/CommonDigest.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>
#import <unistd.h>
#import <math.h>

#define MIC_UDP_PORT 9879
#define AUDIO_BUFFER_COUNT 4
#define AUDIO_BUFFER_SIZE 2048

// MARK: - DeepFilterNet3 Audio DSP Process Manager
static NSTask *gAudioDSPTask = nil;

static void StartAudioDSPEngine(void) {
    if (gAudioDSPTask && [gAudioDSPTask isRunning]) return;
    
    NSString *pythonPath = @"/Volumes/Work/APP TESTE/mac-companion/venv/bin/python";
    NSString *scriptPath = @"/Volumes/Work/APP TESTE/mac-companion/mac_audio_dsp.py";
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:pythonPath] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {
        NSLog(@"⚠️ [MacTouchBar] Audio DSP script or python venv not found at %@", scriptPath);
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            gAudioDSPTask = [[NSTask alloc] init];
            gAudioDSPTask.launchPath = pythonPath;
            gAudioDSPTask.arguments = @[scriptPath];
            [gAudioDSPTask launch];
            NSLog(@"🎙️ [MacTouchBar] DeepFilterNet3 Audio DSP Engine started (PID: %d)", gAudioDSPTask.processIdentifier);
        } @catch (NSException *e) {
            NSLog(@"❌ [MacTouchBar] Failed to start DSP Engine: %@", e);
        }
    });
}

static void StopAudioDSPEngine(void) {
    if (gAudioDSPTask && [gAudioDSPTask isRunning]) {
        [gAudioDSPTask terminate];
        gAudioDSPTask = nil;
        NSLog(@"🛑 [MacTouchBar] DeepFilterNet3 Audio DSP Engine stopped");
    }
}

// MARK: - CoreAudio Virtual Audio Device Helpers (TouchBar Microphone & BlackHole 2ch)
static AudioDeviceID FindAudioDeviceNamed(NSString *targetName) {
    AudioObjectPropertyAddress propertyAddress = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 dataSize = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &dataSize);
    if (status != noErr || dataSize == 0) return kAudioObjectUnknown;
    
    UInt32 deviceCount = dataSize / sizeof(AudioDeviceID);
    AudioDeviceID *devices = (AudioDeviceID *)malloc(dataSize);
    status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &dataSize, devices);
    if (status != noErr) {
        free(devices);
        return kAudioObjectUnknown;
    }
    
    AudioDeviceID foundDevice = kAudioObjectUnknown;
    for (UInt32 i = 0; i < deviceCount; i++) {
        AudioDeviceID devID = devices[i];
        
        CFStringRef devName = NULL;
        UInt32 nameSize = sizeof(devName);
        AudioObjectPropertyAddress nameAddress = {
            kAudioObjectPropertyName,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        
        if (AudioObjectGetPropertyData(devID, &nameAddress, 0, NULL, &nameSize, &devName) == noErr && devName != NULL) {
            NSString *nameStr = (__bridge_transfer NSString *)devName;
            if ([nameStr localizedCaseInsensitiveContainsString:targetName]) {
                foundDevice = devID;
                break;
            }
        }
    }
    free(devices);
    return foundDevice;
}

static NSString *GetAudioDeviceUID(AudioDeviceID devID) {
    if (devID == kAudioObjectUnknown) return nil;
    CFStringRef devUID = NULL;
    UInt32 uidSize = sizeof(devUID);
    AudioObjectPropertyAddress uidAddress = {
        kAudioDevicePropertyDeviceUID,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    if (AudioObjectGetPropertyData(devID, &uidAddress, 0, NULL, &uidSize, &devUID) == noErr && devUID != NULL) {
        return (__bridge_transfer NSString *)devUID;
    }
    return nil;
}

static NSString *GetVirtualAudioDeviceUID(NSString **outDeviceName) {
    NSArray *targets = @[@"TouchBar Microphone", @"BlackHole 2ch", @"BlackHole", @"TouchBar"];
    for (NSString *target in targets) {
        AudioDeviceID devID = FindAudioDeviceNamed(target);
        if (devID != kAudioObjectUnknown) {
            NSString *uid = GetAudioDeviceUID(devID);
            if (uid && uid.length > 0) {
                if (outDeviceName) {
                    CFStringRef devName = NULL;
                    UInt32 nameSize = sizeof(devName);
                    AudioObjectPropertyAddress nameAddress = {
                        kAudioObjectPropertyName,
                        kAudioObjectPropertyScopeGlobal,
                        kAudioObjectPropertyElementMain
                    };
                    if (AudioObjectGetPropertyData(devID, &nameAddress, 0, NULL, &nameSize, &devName) == noErr && devName != NULL) {
                        *outDeviceName = (__bridge_transfer NSString *)devName;
                    } else {
                        *outDeviceName = target;
                    }
                }
                return uid;
            }
        }
    }
    return nil;
}

static BOOL SetDefaultAudioInputDevice(AudioDeviceID devID) {
    if (devID == kAudioObjectUnknown) return NO;
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    OSStatus status = AudioObjectSetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, sizeof(AudioDeviceID), &devID);
    return (status == noErr);
}

// MARK: - Wireless Microphone Engine (Android -> Mac CoreAudio AudioUnit HAL Output)
#define RING_BUFFER_SIZE 65536 // 32768 samples = ~743ms @ 44.1kHz

@interface MacMicEngine : NSObject {
@public
    AudioUnit _audioUnit;
    int _udpSocket;
    BOOL _isRunning;
    float _volume;
    
    int16_t _ringBuffer[RING_BUFFER_SIZE / sizeof(int16_t)];
    uint32_t _ringHead;
    uint32_t _ringTail;
    NSLock *_bufferLock;
    
    NSTimeInterval _lastPacketTime;
    uint64_t _totalPacketsReceived;
}
+ (instancetype)shared;
- (void)start;
- (void)stop;
- (BOOL)isRunning;
- (void)setVolume:(float)vol;
- (void)handleAudioPacket:(const void *)data length:(size_t)len;
@end

static OSStatus MacMicRenderCallback(void *inRefCon,
                                     AudioUnitRenderActionFlags *ioActionFlags,
                                     const AudioTimeStamp *inTimeStamp,
                                     UInt32 inBusNumber,
                                     UInt32 inNumberFrames,
                                     AudioBufferList *ioData) {
    MacMicEngine *engine = (__bridge MacMicEngine *)inRefCon;
    if (!engine || !ioData) return noErr;

    float vol = engine->_volume;
    float *outL = (float *)ioData->mBuffers[0].mData;
    float *outR = (ioData->mNumberBuffers > 1) ? (float *)ioData->mBuffers[1].mData : NULL;
    BOOL isInterleaved = (ioData->mNumberBuffers == 1 && ioData->mBuffers[0].mNumberChannels == 2);

    [engine->_bufferLock lock];
    uint32_t head = engine->_ringHead;
    uint32_t tail = engine->_ringTail;
    const uint32_t cap = (uint32_t)(sizeof(engine->_ringBuffer) / sizeof(int16_t));
    uint32_t available = (head >= tail) ? (head - tail) : (cap - tail + head);

    for (UInt32 f = 0; f < inNumberFrames; f++) {
        float sampleVal = 0.0f;
        if (available > 0) {
            int16_t raw = engine->_ringBuffer[tail];
            sampleVal = ((float)raw / 32768.0f) * vol;
            tail = (tail + 1) % cap;
            available--;
        }

        if (isInterleaved) {
            outL[f * 2]     = sampleVal;
            outL[f * 2 + 1] = sampleVal;
        } else {
            outL[f] = sampleVal;
            if (outR) outR[f] = sampleVal;
        }
    }
    engine->_ringTail = tail;
    [engine->_bufferLock unlock];

    return noErr;
}

@implementation MacMicEngine

+ (instancetype)shared {
    static MacMicEngine *s_engine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_engine = [[MacMicEngine alloc] init];
    });
    return s_engine;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _udpSocket = -1;
        _isRunning = NO;
        _volume = 1.0f;
        _bufferLock = [[NSLock alloc] init];
        _audioUnit = NULL;
        _ringHead = 0;
        _ringTail = 0;
        _lastPacketTime = 0;
        _totalPacketsReceived = 0;
        memset(_ringBuffer, 0, sizeof(_ringBuffer));
    }
    return self;
}

- (BOOL)setupAudioUnit {
    if (_audioUnit != NULL) return YES;

    AudioDeviceID devID = FindAudioDeviceNamed(@"TouchBar Microphone");
    if (devID == kAudioObjectUnknown) {
        devID = FindAudioDeviceNamed(@"BlackHole 2ch");
    }
    if (devID == kAudioObjectUnknown) {
        devID = FindAudioDeviceNamed(@"BlackHole");
    }

    AudioComponentDescription desc = {
        kAudioUnitType_Output,
        kAudioUnitSubType_HALOutput,
        kAudioUnitManufacturer_Apple,
        0,
        0
    };
    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    if (!comp) {
        NSLog(@"[MacMicEngine] Failed to find HAL Output AudioComponent");
        return NO;
    }

    OSStatus status = AudioComponentInstanceNew(comp, &_audioUnit);
    if (status != noErr || !_audioUnit) {
        NSLog(@"[MacMicEngine] AudioComponentInstanceNew failed: %d", (int)status);
        _audioUnit = NULL;
        return NO;
    }

    UInt32 enableIO = 1;
    status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enableIO, sizeof(enableIO));
    if (status != noErr) {
        NSLog(@"[MacMicEngine] EnableIO failed: %d", (int)status);
    }

    if (devID != kAudioObjectUnknown) {
        status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &devID, sizeof(devID));
        NSLog(@"🎙️ [MacMicEngine] AudioUnit assigned to Virtual Device ID %u (TouchBar/BlackHole)", (unsigned int)devID);
    } else {
        NSLog(@"ℹ️ [MacMicEngine] Virtual device not found, using default output");
    }

    AudioStreamBasicDescription format;
    memset(&format, 0, sizeof(format));
    format.mSampleRate = 48000.0;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 32;
    format.mBytesPerFrame = 8;
    format.mBytesPerPacket = 8;
    format.mFramesPerPacket = 1;

    status = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(format));
    if (status != noErr) {
        NSLog(@"[MacMicEngine] Set StreamFormat failed: %d", (int)status);
    }

    AURenderCallbackStruct cb;
    cb.inputProc = MacMicRenderCallback;
    cb.inputProcRefCon = (__bridge void *)self;
    status = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb, sizeof(cb));
    if (status != noErr) {
        NSLog(@"[MacMicEngine] SetRenderCallback failed: %d", (int)status);
    }

    status = AudioUnitInitialize(_audioUnit);
    if (status != noErr) {
        NSLog(@"[MacMicEngine] AudioUnitInitialize failed: %d", (int)status);
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    status = AudioOutputUnitStart(_audioUnit);
    if (status != noErr) {
        NSLog(@"[MacMicEngine] AudioOutputUnitStart failed: %d", (int)status);
        AudioUnitUninitialize(_audioUnit);
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    NSLog(@"🎙️ [MacMicEngine] CoreAudio HAL AudioUnit running smoothly!");
    return YES;
}

- (void)setVolume:(float)vol {
    _volume = MAX(0.0f, MIN(3.0f, vol));
}

- (void)start {
    if (_isRunning) return;
    _isRunning = YES;

    [self setupAudioUnit];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        self->_udpSocket = socket(AF_INET, SOCK_DGRAM, 0);
        if (self->_udpSocket < 0) {
            NSLog(@"[MacMicEngine] Failed to create UDP socket: %s", strerror(errno));
            self->_isRunning = NO;
            return;
        }

        int opt = 1;
        setsockopt(self->_udpSocket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
        int rcvbuf = 65536;
        setsockopt(self->_udpSocket, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof(rcvbuf));

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_port = htons(MIC_UDP_PORT);

        if (bind(self->_udpSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            NSLog(@"[MacMicEngine] Failed to bind UDP port %d: %s", MIC_UDP_PORT, strerror(errno));
            close(self->_udpSocket);
            self->_udpSocket = -1;
            self->_isRunning = NO;
            return;
        }

        NSLog(@"🎙️ [MacMicEngine] Wireless microphone listener active on UDP port %d (44.1kHz 16-bit Mono)", MIC_UDP_PORT);

        uint8_t packetBuffer[2048];
        while (self->_isRunning && self->_udpSocket >= 0) {
            struct sockaddr_in senderAddr;
            socklen_t senderLen = sizeof(senderAddr);
            ssize_t received = recvfrom(self->_udpSocket, packetBuffer, sizeof(packetBuffer), 0, (struct sockaddr *)&senderAddr, &senderLen);
            if (received > 0) {
                [self handleAudioPacket:packetBuffer length:(size_t)received];
            } else if (received < 0 && (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)) {
                break;
            }
        }

        if (self->_udpSocket >= 0) {
            close(self->_udpSocket);
            self->_udpSocket = -1;
        }
    });
}

- (void)handleAudioPacket:(const void *)data length:(size_t)len {
    if (!_isRunning || len == 0) return;

    _lastPacketTime = [[NSDate date] timeIntervalSince1970];
    _totalPacketsReceived++;

    const int16_t *samples = (const int16_t *)data;
    size_t sampleCount = len / sizeof(int16_t);

    [_bufferLock lock];
    const uint32_t cap = (uint32_t)(sizeof(_ringBuffer) / sizeof(int16_t));
    uint32_t head = _ringHead;

    for (size_t i = 0; i < sampleCount; i++) {
        _ringBuffer[head] = samples[i];
        head = (head + 1) % cap;
    }
    _ringHead = head;
    [_bufferLock unlock];

    if (_totalPacketsReceived % 200 == 1) {
        NSLog(@"🎙️ [MacMicEngine] Streaming audio active: %llu packets processed (%zu bytes)", _totalPacketsReceived, len);
    }
}

- (void)stop {
    _isRunning = NO;
    if (_udpSocket >= 0) {
        close(_udpSocket);
        _udpSocket = -1;
    }
    if (_audioUnit != NULL) {
        AudioOutputUnitStop(_audioUnit);
        AudioUnitUninitialize(_audioUnit);
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
    }
    [_bufferLock lock];
    _ringHead = 0;
    _ringTail = 0;
    [_bufferLock unlock];
    NSLog(@"[MacMicEngine] Stopped audio engine and UDP listener");
}

- (BOOL)isRunning {
    return _isRunning;
}

@end

// MARK: - Virtual Microphone Manager (TouchBarMic & BlackHole Driver Installation & CoreAudio Setup)
@interface VirtualMicManager : NSObject
+ (BOOL)isVirtualMicInstalled;
+ (NSString *)installedVirtualMicName;
+ (BOOL)installVirtualAudioDriverWithError:(NSString **)outError;
+ (BOOL)setDefaultInputToVirtualMic;
@end

@implementation VirtualMicManager

+ (BOOL)isVirtualMicInstalled {
    return (GetVirtualAudioDeviceUID(NULL) != nil);
}

+ (NSString *)installedVirtualMicName {
    NSString *name = nil;
    GetVirtualAudioDeviceUID(&name);
    return name;
}

+ (BOOL)setDefaultInputToVirtualMic {
    AudioDeviceID devID = FindAudioDeviceNamed(@"TouchBar Microphone");
    if (devID == kAudioObjectUnknown) {
        devID = FindAudioDeviceNamed(@"BlackHole 2ch");
    }
    if (devID == kAudioObjectUnknown) {
        devID = FindAudioDeviceNamed(@"BlackHole");
    }
    if (devID != kAudioObjectUnknown) {
        BOOL ok = SetDefaultAudioInputDevice(devID);
        if (ok) {
            NSLog(@"🎙️ [VirtualMicManager] Successfully set default system audio input to device ID %u", (unsigned int)devID);
        }
        return ok;
    }
    return NO;
}

+ (BOOL)installVirtualAudioDriverWithError:(NSString **)outError {
    NSString *resDir = [[NSBundle mainBundle] resourcePath];
    NSString *touchBarDriver = [resDir stringByAppendingPathComponent:@"TouchBarMic.driver"];
    NSString *blackHoleDriver = [resDir stringByAppendingPathComponent:@"BlackHole2ch.driver"];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:touchBarDriver]) {
        touchBarDriver = @"/Volumes/Work/APP TESTE/mac-app/Resources/TouchBarMic.driver";
        blackHoleDriver = @"/Volumes/Work/APP TESTE/mac-app/Resources/BlackHole2ch.driver";
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:touchBarDriver] && ![[NSFileManager defaultManager] fileExistsAtPath:blackHoleDriver]) {
        if (outError) *outError = @"Arquivos do driver de áudio não encontrados no pacote do aplicativo.";
        return NO;
    }
    
    NSMutableArray *cmds = [NSMutableArray array];
    [cmds addObject:@"mkdir -p /Library/Audio/Plug-Ins/HAL"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:touchBarDriver]) {
        [cmds addObject:[NSString stringWithFormat:@"rm -rf /Library/Audio/Plug-Ins/HAL/TouchBarMic.driver && cp -R '%@' /Library/Audio/Plug-Ins/HAL/", touchBarDriver]];
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:blackHoleDriver]) {
        [cmds addObject:[NSString stringWithFormat:@"rm -rf /Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver && cp -R '%@' /Library/Audio/Plug-Ins/HAL/", blackHoleDriver]];
    }
    [cmds addObject:@"killall coreaudiod 2>/dev/null || true"];
    
    NSString *fullShellCmd = [cmds componentsJoinedByString:@" && "];
    // Use single-quote wrapping for do shell script or escaped inner string
    NSString *scriptSource = [NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges", [fullShellCmd stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    
    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:scriptSource];
    NSDictionary *errDict = nil;
    NSAppleEventDescriptor *result = [appleScript executeAndReturnError:&errDict];
    
    if (errDict && !result) {
        if (outError) *outError = errDict[NSAppleScriptErrorMessage] ?: @"Autorização de administrador cancelada.";
        return NO;
    }
    
    [NSThread sleepForTimeInterval:1.5];
    
    // Set virtual mic as default input
    [self setDefaultInputToVirtualMic];
    
    // Restart audio engine to bind to newly registered virtual device
    [[MacMicEngine shared] stop];
    [[MacMicEngine shared] start];
    
    return YES;
}

@end

static inline double sanitizeDouble(double val, double fallback) {
    if (isnan(val) || isinf(val) || val < 0.0) {
        return fallback;
    }
    return val;
}

// MARK: - MediaRemote Private Framework (Universal macOS NowPlaying: Chrome, Safari, YouTube, Spotify, Music)
typedef void (^MRMediaRemoteGetNowPlayingInfoCompletion)(CFDictionaryRef information);
void MRMediaRemoteGetNowPlayingInfo(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingInfoCompletion completion);
Boolean MRMediaRemoteSendCommand(unsigned int command, id options);
void MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_queue_t queue);

// MARK: - App Scanner & Icon Extractor
static NSString *getIconBase64ForApp(NSString *appNameOrPath) {
    NSString *path = appNameOrPath;
    if (![path hasPrefix:@"/"]) {
        path = [[NSWorkspace sharedWorkspace] fullPathForApplication:appNameOrPath];
    }
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        // Search in common directories
        NSArray *dirs = @[@"/Applications", @"/System/Applications", @"/System/Applications/Utilities", @"/System/Library/CoreServices"];
        for (NSString *d in dirs) {
            NSString *candidate = [d stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.app", appNameOrPath]];
            if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
                path = candidate;
                break;
            }
        }
    }
    
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return @"";
    }
    
    NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:path];
    if (!icon) return @"";
    
    NSSize size = NSMakeSize(128, 128);
    NSImage *resizedImage = [[NSImage alloc] initWithSize:size];
    [resizedImage lockFocus];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    [icon drawInRect:NSMakeRect(0, 0, size.width, size.height)
            fromRect:NSZeroRect
           operation:NSCompositingOperationCopy
            fraction:1.0];
    
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0, 0, size.width, size.height)];
    [resizedImage unlockFocus];
    
    NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [pngData base64EncodedStringWithOptions:0] ?: @"";
}

static NSArray<NSDictionary *> *getInstalledAppsList(void) {
    NSMutableArray *apps = [NSMutableArray array];
    NSArray *dirs = @[@"/Applications", @"/System/Applications", @"/System/Applications/Utilities", @"/System/Library/CoreServices"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableSet *seen = [NSMutableSet set];
    
    for (NSString *dir in dirs) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *file in contents) {
            if ([file hasSuffix:@".app"]) {
                NSString *name = [file stringByDeletingPathExtension];
                if (![seen containsObject:name.lowercaseString]) {
                    [seen addObject:name.lowercaseString];
                    NSString *fullPath = [dir stringByAppendingPathComponent:file];
                    [apps addObject:@{@"name": name, @"path": fullPath}];
                }
            }
        }
    }
    
    [apps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return apps;
}

// MARK: - Deck Item Model
@interface DeckButtonConfig : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSString *id;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, copy) NSString *iconBase64;
@property (nonatomic, copy) NSString *actionType; // "launch_app", "hotkey", "system", "terminal_cmd", "sound"
@property (nonatomic, copy) NSString *payload;
@property (nonatomic, copy) NSString *colorHex;

- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
@end

@implementation DeckButtonConfig
+ (BOOL)supportsSecureCoding { return YES; }

- (BOOL)isAppCurrentlyRunning {
    if (![self.actionType isEqualToString:@"launch_app"] && ![self.actionType isEqualToString:@"app"]) {
        return NO;
    }
    NSString *target = self.payload ?: @"";
    NSArray<NSRunningApplication *> *runningApps = [[NSWorkspace sharedWorkspace] runningApplications];
    NSString *lowerTarget = target.lowercaseString;
    NSString *targetLastComponent = target.lastPathComponent.stringByDeletingPathExtension.lowercaseString;
    NSString *lowerLabel = self.label.lowercaseString ?: @"";
    NSString *lowerId = self.id.lowercaseString ?: @"";
    
    for (NSRunningApplication *app in runningApps) {
        if (app.bundleURL && [app.bundleURL.path.lowercaseString isEqualToString:lowerTarget]) {
            return YES;
        }
        if (app.bundleIdentifier && [app.bundleIdentifier.lowercaseString isEqualToString:lowerTarget]) {
            return YES;
        }
        NSString *appName = app.localizedName.lowercaseString ?: @"";
        if (appName.length > 0) {
            if ([appName isEqualToString:targetLastComponent] || [appName isEqualToString:lowerLabel] || [appName isEqualToString:lowerId]) {
                return YES;
            }
            if (targetLastComponent.length > 2 && [appName containsString:targetLastComponent]) return YES;
            if (lowerLabel.length > 2 && [appName containsString:lowerLabel]) return YES;
            
            // Common app aliases
            if ([lowerId isEqualToString:@"chrome"] && [appName containsString:@"chrome"]) return YES;
            if ([lowerId isEqualToString:@"music"] && ([appName containsString:@"music"] || [appName containsString:@"música"])) return YES;
            if ([lowerId isEqualToString:@"discord"] && [appName containsString:@"discord"]) return YES;
            if ([lowerId isEqualToString:@"photoshop"] && [appName containsString:@"photoshop"]) return YES;
            if ([lowerId isEqualToString:@"illustrator"] && [appName containsString:@"illustrator"]) return YES;
            if ([lowerId isEqualToString:@"indesign"] && [appName containsString:@"indesign"]) return YES;
            if ([lowerId isEqualToString:@"figma"] && [appName containsString:@"figma"]) return YES;
            if ([lowerId isEqualToString:@"affinity"] && [appName containsString:@"affinity"]) return YES;
            if ([lowerId isEqualToString:@"antigravity"] && [appName containsString:@"antigravity"]) return YES;
            if ([lowerId isEqualToString:@"whatsapp"] && [appName containsString:@"whatsapp"]) return YES;
            if ([lowerId isEqualToString:@"finder"] && [appName containsString:@"finder"]) return YES;
            if ([lowerId isEqualToString:@"settings"] && ([appName containsString:@"settings"] || [appName containsString:@"ajustes"])) return YES;
        }
    }
    return NO;
}

- (NSDictionary *)toDictionary {
    return @{
        @"id": self.id ?: @"",
        @"label": self.label ?: @"",
        @"icon": self.icon ?: @"",
        @"iconBase64": self.iconBase64 ?: @"",
        @"actionType": self.actionType ?: @"launch_app",
        @"payload": self.payload ?: @"",
        @"colorHex": self.colorHex ?: @"#1F1F24",
        @"isRunning": @([self isAppCurrentlyRunning])
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    DeckButtonConfig *item = [[DeckButtonConfig alloc] init];
    item.id = dict[@"id"] ?: [[NSUUID UUID] UUIDString];
    item.label = dict[@"label"] ?: @"App";
    item.icon = dict[@"icon"] ?: @"💻";
    item.iconBase64 = dict[@"iconBase64"] ?: @"";
    item.actionType = dict[@"actionType"] ?: @"launch_app";
    item.payload = dict[@"payload"] ?: @"";
    item.colorHex = dict[@"colorHex"] ?: @"#1F1F24";
    return item;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.id forKey:@"id"];
    [coder encodeObject:self.label forKey:@"label"];
    [coder encodeObject:self.icon forKey:@"icon"];
    [coder encodeObject:self.iconBase64 forKey:@"iconBase64"];
    [coder encodeObject:self.actionType forKey:@"actionType"];
    [coder encodeObject:self.payload forKey:@"payload"];
    [coder encodeObject:self.colorHex forKey:@"colorHex"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _id = [coder decodeObjectOfClass:[NSString class] forKey:@"id"];
        _label = [coder decodeObjectOfClass:[NSString class] forKey:@"label"];
        _icon = [coder decodeObjectOfClass:[NSString class] forKey:@"icon"];
        _iconBase64 = [coder decodeObjectOfClass:[NSString class] forKey:@"iconBase64"];
        _actionType = [coder decodeObjectOfClass:[NSString class] forKey:@"actionType"];
        _payload = [coder decodeObjectOfClass:[NSString class] forKey:@"payload"];
        _colorHex = [coder decodeObjectOfClass:[NSString class] forKey:@"colorHex"];
    }
    return self;
}
@end

// MARK: - Deck Manager
@interface DeckManager : NSObject
+ (instancetype)shared;
@property (nonatomic, strong) NSMutableArray<DeckButtonConfig *> *buttons;
- (void)loadConfigs;
- (void)saveConfigs;
- (void)applyUserAppsLayout;
- (void)applyPreset:(NSString *)presetName;
- (NSArray<NSDictionary *> *)toDictionaryArray;
@end

@implementation DeckManager
+ (instancetype)shared {
    static DeckManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[DeckManager alloc] init];
        [instance loadConfigs];
    });
    return instance;
}

- (void)loadConfigs {
    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:@"MacDeckButtons2x6_UserLayout_V4"];
    if (data) {
        NSError *error = nil;
        NSSet *classes = [NSSet setWithObjects:[NSArray class], [DeckButtonConfig class], nil];
        NSArray *saved = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:&error];
        if (saved && saved.count == 12) {
            self.buttons = [saved mutableCopy];
            for (DeckButtonConfig *cfg in self.buttons) {
                if (cfg.iconBase64.length == 0 && [cfg.actionType isEqualToString:@"launch_app"]) {
                    cfg.iconBase64 = getIconBase64ForApp(cfg.payload);
                }
            }
            return;
        }
    }
    [self applyUserAppsLayout];
}

- (void)applyUserAppsLayout {
    self.buttons = [NSMutableArray array];
    
    // Exact user requested 2x6 layout:
    // Row 1: Chrome, Música, Discord, Photoshop, Illustrator, InDesign
    // Row 2: Figma, Affinity, Antigravity, WhatsApp, Finder, Configurações
    NSArray *userLayout = @[
        // Row 1
        @{@"label": @"Chrome", @"path": @"/Applications/Google Chrome.app", @"icon": @"🌐", @"color": @"#1F1F24"},
        @{@"label": @"Música", @"path": @"/System/Applications/Music.app", @"icon": @"🎵", @"color": @"#1F1F24"},
        @{@"label": @"Discord", @"path": @"/Applications/Discord.app", @"icon": @"🎮", @"color": @"#1F1F24"},
        @{@"label": @"Photoshop", @"path": @"/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app", @"icon": @"🖼️", @"color": @"#1F1F24"},
        @{@"label": @"Illustrator", @"path": @"/Applications/Adobe Illustrator 2026/Adobe Illustrator.app", @"icon": @"✒️", @"color": @"#1F1F24"},
        @{@"label": @"InDesign", @"path": @"/Applications/Adobe InDesign 2026/Adobe InDesign 2026.app", @"icon": @"📑", @"color": @"#1F1F24"},
        
        // Row 2
        @{@"label": @"Figma", @"path": @"/Applications/Figma.app", @"icon": @"🎨", @"color": @"#1F1F24"},
        @{@"label": @"Affinity", @"path": @"/Applications/Affinity.app", @"icon": @"💎", @"color": @"#1F1F24"},
        @{@"label": @"Antigravity", @"path": @"/Applications/Antigravity.app", @"icon": @"🚀", @"color": @"#1F1F24"},
        @{@"label": @"WhatsApp", @"path": @"/Applications/WhatsApp.app", @"icon": @"💬", @"color": @"#1F1F24"},
        @{@"label": @"Finder", @"path": @"/System/Library/CoreServices/Finder.app", @"icon": @"📁", @"color": @"#1F1F24"},
        @{@"label": @"Ajustes", @"path": @"/System/Applications/System Settings.app", @"icon": @"⚙️", @"color": @"#1F1F24"}
    ];
    
    for (NSDictionary *dict in userLayout) {
        DeckButtonConfig *cfg = [[DeckButtonConfig alloc] init];
        cfg.id = [[NSUUID UUID] UUIDString];
        cfg.label = dict[@"label"];
        cfg.actionType = @"launch_app";
        cfg.payload = dict[@"path"];
        cfg.icon = dict[@"icon"];
        cfg.colorHex = dict[@"color"];
        cfg.iconBase64 = getIconBase64ForApp(dict[@"path"]);
        [self.buttons addObject:cfg];
    }
    
    [self saveConfigs];
}

- (void)applyPreset:(NSString *)presetName {
    if ([presetName isEqualToString:@"user_apps"]) {
        [self applyUserAppsLayout];
        return;
    }
    
    self.buttons = [NSMutableArray array];
    NSArray *items = nil;
    if ([presetName isEqualToString:@"developer"]) {
        items = @[
            @{@"label": @"VS Code", @"type": @"launch_app", @"payload": @"Visual Studio Code", @"icon": @"💻", @"color": @"#007ACC"},
            @{@"label": @"Terminal", @"type": @"launch_app", @"payload": @"Terminal", @"icon": @"⚡️", @"color": @"#1F1F24"},
            @{@"label": @"Salvar", @"type": @"hotkey", @"payload": @"cmd+s", @"icon": @"💾", @"color": @"#1F1F24"},
            @{@"label": @"Buscar", @"type": @"hotkey", @"payload": @"cmd+p", @"icon": @"🔍", @"color": @"#1F1F24"},
            @{@"label": @"Term. Interno", @"type": @"hotkey", @"payload": @"ctrl+`", @"icon": @"📟", @"color": @"#1F1F24"},
            @{@"label": @"Formatar", @"type": @"hotkey", @"payload": @"shift+option+f", @"icon": @"🪄", @"color": @"#1F1F24"},
            
            @{@"label": @"Git Status", @"type": @"terminal_cmd", @"payload": @"git status\n", @"icon": @"🌿", @"color": @"#28A745"},
            @{@"label": @"Git Pull", @"type": @"terminal_cmd", @"payload": @"git pull\n", @"icon": @"⬇️", @"color": @"#28A745"},
            @{@"label": @"npm dev", @"type": @"terminal_cmd", @"payload": @"npm run dev\n", @"icon": @"🚀", @"color": @"#CB3837"},
            @{@"label": @"Limpar", @"type": @"terminal_cmd", @"payload": @"clear\n", @"icon": @"🧹", @"color": @"#1F1F24"},
            @{@"label": @"Print Área", @"type": @"system", @"payload": @"screenshot_interactive", @"icon": @"📸", @"color": @"#1F1F24"},
            @{@"label": @"Bloquear", @"type": @"system", @"payload": @"lock_screen", @"icon": @"🔒", @"color": @"#5856D6"}
        ];
    } else {
        [self applyUserAppsLayout];
        return;
    }
    
    for (NSDictionary *dict in items) {
        DeckButtonConfig *cfg = [[DeckButtonConfig alloc] init];
        cfg.id = [[NSUUID UUID] UUIDString];
        cfg.label = dict[@"label"];
        cfg.actionType = dict[@"type"];
        cfg.payload = dict[@"payload"];
        cfg.icon = dict[@"icon"];
        cfg.colorHex = dict[@"color"];
        if ([cfg.actionType isEqualToString:@"launch_app"]) {
            cfg.iconBase64 = getIconBase64ForApp(cfg.payload);
        }
        [self.buttons addObject:cfg];
    }
    [self saveConfigs];
}

- (void)saveConfigs {
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.buttons requiringSecureCoding:YES error:&error];
    if (data) {
        [[NSUserDefaults standardUserDefaults] setObject:data forKey:@"MacDeckButtons2x6_UserLayout_V4"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (NSArray<NSDictionary *> *)toDictionaryArray {
    NSMutableArray *arr = [NSMutableArray array];
    for (DeckButtonConfig *btn in self.buttons) {
        [arr addObject:[btn toDictionary]];
    }
    return arr;
}
@end

// MARK: - Safe Full Socket Sender
static BOOL writeFull(int sock, const void *buffer, size_t length) {
    if (sock < 0 || buffer == NULL || length == 0) return NO;
    const uint8_t *ptr = (const uint8_t *)buffer;
    size_t remaining = length;
    while (remaining > 0) {
        ssize_t written = write(sock, ptr, remaining);
        if (written <= 0) {
            if (written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) {
                usleep(500);
                continue;
            }
            return NO;
        }
        ptr += written;
        remaining -= (size_t)written;
    }
    return YES;
}

// MARK: - Mac Native Telemetry & Wallpaper
static NSString *getWallpaperBase64(void) {
    @autoreleasepool {
        static NSString *s_cachedBase64 = nil;
        static NSString *s_cachedPath = nil;
        static NSDate *s_cachedMtime = nil;
        static NSTimeInterval s_lastCheckTime = 0;
        
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (s_cachedBase64.length > 50 && (now - s_lastCheckTime) < 2.0) {
            return s_cachedBase64;
        }
        s_lastCheckTime = now;
        
        NSString *rawPath = nil;
        
        // 1. Spawning /usr/bin/osascript via NSTask (bypasses Cocoa NSAppleScript sandbox TCC issues)
        @try {
            NSTask *osaTask = [[NSTask alloc] init];
            osaTask.launchPath = @"/usr/bin/osascript";
            osaTask.arguments = @[@"-e", @"tell application \"System Events\" to tell current desktop to get picture"];
            NSPipe *osaPipe = [NSPipe pipe];
            osaTask.standardOutput = osaPipe;
            osaTask.standardError = [NSPipe pipe];
            [osaTask launch];
            [osaTask waitUntilExit];
            
            NSData *osaData = [[osaPipe fileHandleForReading] readDataToEndOfFile];
            NSString *osaStr = [[[NSString alloc] initWithData:osaData encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (osaStr.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:osaStr]) {
                rawPath = osaStr;
            }
        } @catch (NSException *e) {}
        
        // 2. Fallback: Search all Unsplash container subdirectories for the newest wallpaper image
        if (!rawPath) {
            NSString *unsplashBaseDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Containers/com.unsplash.Wallpapers/Data/Documents"];
            NSFileManager *fm = [NSFileManager defaultManager];
            NSArray *subdirs = [fm contentsOfDirectoryAtPath:unsplashBaseDir error:nil];
            NSDate *newestDate = [NSDate distantPast];
            for (NSString *sub in subdirs) {
                NSString *fullSub = [unsplashBaseDir stringByAppendingPathComponent:sub];
                BOOL isDir = NO;
                if ([fm fileExistsAtPath:fullSub isDirectory:&isDir] && isDir) {
                    NSArray *files = [fm contentsOfDirectoryAtPath:fullSub error:nil];
                    for (NSString *file in files) {
                        if ([file hasSuffix:@".jpeg"] || [file hasSuffix:@".jpg"] || [file hasSuffix:@".png"]) {
                            NSString *candidate = [fullSub stringByAppendingPathComponent:file];
                            NSDictionary *attr = [fm attributesOfItemAtPath:candidate error:nil];
                            NSDate *mdate = attr[NSFileModificationDate];
                            if (mdate && [mdate compare:newestDate] == NSOrderedDescending) {
                                newestDate = mdate;
                                rawPath = candidate;
                            }
                        }
                    }
                }
            }
        }
        
        // 3. Fallback: System Default Wallpapers
        if (!rawPath) {
            NSArray *sysCandidates = @[
                @"/System/Library/Desktop Pictures/Ventura Graphic.heic",
                @"/System/Library/Desktop Pictures/Sonoma Graphic.heic",
                @"/System/Library/Desktop Pictures/Sequoia Graphic.heic",
                @"/System/Library/Desktop Pictures/Solid Colors/Stone.png"
            ];
            for (NSString *cand in sysCandidates) {
                if ([[NSFileManager defaultManager] fileExistsAtPath:cand]) {
                    rawPath = cand;
                    break;
                }
            }
        }
        
        if (!rawPath || rawPath.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:rawPath]) {
            return s_cachedBase64 ?: @"";
        }
        
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:rawPath error:nil];
        NSDate *mtime = attrs ? attrs[NSFileModificationDate] : nil;
        
        if (s_cachedBase64.length > 50 && [rawPath isEqualToString:s_cachedPath] && [mtime isEqualToDate:s_cachedMtime]) {
            return s_cachedBase64;
        }
        
        NSString *tmpOut = @"/tmp/mac_touchbar_wallpaper.jpg";
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/sips";
        // Ultra HD 2.5K Resolution (2560px max width/height) with 92% high fidelity JPEG compression
        task.arguments = @[@"-s", @"format", @"jpeg", @"-s", @"formatOptions", @"92", @"-Z", @"2560", rawPath, @"--out", tmpOut];
        [task launch];
        [task waitUntilExit];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:tmpOut]) {
            NSData *d = [NSData dataWithContentsOfFile:tmpOut];
            if (d.length > 50) {
                s_cachedBase64 = [d base64EncodedStringWithOptions:0];
                s_cachedPath = [rawPath copy];
                s_cachedMtime = mtime;
                NSLog(@"[MacTouchBar] Ultra HD Wallpaper extracted successfully (%lu bytes, %lu chars, source: %@)", (unsigned long)d.length, (unsigned long)s_cachedBase64.length, rawPath.lastPathComponent);
                return s_cachedBase64;
            }
        }
        return s_cachedBase64 ?: @"";
    }
}

static NSDictionary *getBatteryInfoDict(void) {
    @autoreleasepool {
        int percent = 100;
        BOOL isCharging = NO;
        CFTypeRef powerInfo = IOPSCopyPowerSourcesInfo();
        if (powerInfo) {
            CFArrayRef powerList = IOPSCopyPowerSourcesList(powerInfo);
            if (powerList) {
                CFIndex count = CFArrayGetCount(powerList);
                for (CFIndex i = 0; i < count; i++) {
                    CFTypeRef source = CFArrayGetValueAtIndex(powerList, i);
                    CFDictionaryRef desc = IOPSGetPowerSourceDescription(powerInfo, source);
                    if (desc) {
                        NSDictionary *dict = (__bridge NSDictionary *)desc;
                        NSNumber *cur = dict[@kIOPSCurrentCapacityKey];
                        NSNumber *max = dict[@kIOPSMaxCapacityKey];
                        NSNumber *charging = dict[@kIOPSIsChargingKey];
                        if (cur && max && max.intValue > 0) {
                            percent = (int)((cur.doubleValue / max.doubleValue) * 100.0);
                        }
                        if (charging) {
                            isCharging = charging.boolValue;
                        }
                    }
                }
                CFRelease(powerList);
            }
            CFRelease(powerInfo);
        }
        
        return @{
            @"percent": @(percent),
            @"is_charging": @(isCharging),
            @"state": isCharging ? @"Carregando" : @"Bateria"
        };
    }
}

static NSDictionary *getAirPodsInfoDict(void) {
    static NSDictionary *cachedAirPods = nil;
    static NSTimeInterval lastCheck = 0;
    static BOOL isChecking = NO;
    
    if (cachedAirPods == nil) {
        cachedAirPods = @{
            @"connected": @(NO),
            @"name": @"AirPods",
            @"left": @(100),
            @"right": @(100),
            @"case": @(90)
        };
    }
    
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if ((now - lastCheck > 15.0) && !isChecking) {
        isChecking = YES;
        lastCheck = now;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            @autoreleasepool {
                @try {
                    NSTask *task = [[NSTask alloc] init];
                    task.launchPath = @"/usr/sbin/system_profiler";
                    task.arguments = @[@"SPBluetoothDataType", @"-json"];
                    NSPipe *pipe = [NSPipe pipe];
                    task.standardOutput = pipe;
                    task.standardError = [NSPipe pipe];
                    [task launch];
                    [task waitUntilExit];
                    
                    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
                    if (data.length > 0) {
                        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                        NSArray *btData = json[@"SPBluetoothDataType"];
                        if (btData.count > 0) {
                            NSArray *connected = btData[0][@"device_connected"];
                            for (NSDictionary *entry in connected) {
                                for (NSString *devName in entry) {
                                    NSDictionary *info = entry[devName];
                                    if ([devName.lowercaseString containsString:@"airpod"] || [info[@"device_minorType"] isEqualToString:@"Headset"] || info[@"device_batteryLevelLeft"]) {
                                        int left = [info[@"device_batteryLevelLeft"] intValue] ?: [info[@"device_batteryLevelMain"] intValue] ?: 100;
                                        int right = [info[@"device_batteryLevelRight"] intValue] ?: [info[@"device_batteryLevelMain"] intValue] ?: 100;
                                        int casePct = [info[@"device_batteryLevelCase"] intValue] ?: 90;
                                        cachedAirPods = @{
                                            @"connected": @(YES),
                                            @"name": devName,
                                            @"left": @(left),
                                            @"right": @(right),
                                            @"case": @(casePct)
                                        };
                                        isChecking = NO;
                                        return;
                                    }
                                }
                            }
                        }
                    }
                } @catch (NSException *e) {}
                cachedAirPods = @{
                    @"connected": @(NO),
                    @"name": @"AirPods",
                    @"left": @(100),
                    @"right": @(100),
                    @"case": @(90)
                };
                isChecking = NO;
            }
        });
    }
    return cachedAirPods;
}

static NSDictionary *getMacMediaInfoFull(void) {
    @autoreleasepool {
        static NSString *cachedArtKey = @"";
        static NSString *cachedArtB64 = @"";
        static NSDictionary *cachedMedia = nil;
        static NSTimeInterval lastActiveMediaTime = 0;
        
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        
        // 1. Universal macOS MediaRemote Query (Google Chrome, YouTube, Safari, Spotify, Music, etc.)
        __block NSDictionary *mrResult = nil;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        
        @try {
            MRMediaRemoteGetNowPlayingInfo(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^(CFDictionaryRef information) {
                if (information) {
                    NSDictionary *d = (__bridge NSDictionary *)information;
                    NSString *title = d[@"kMRMediaRemoteNowPlayingInfoTitle"] ?: @"";
                    NSString *artist = d[@"kMRMediaRemoteNowPlayingInfoArtist"] ?: @"";
                    NSString *album = d[@"kMRMediaRemoteNowPlayingInfoAlbum"] ?: @"";
                    double duration = sanitizeDouble([d[@"kMRMediaRemoteNowPlayingInfoDuration"] doubleValue], 0.0);
                    double position = sanitizeDouble([d[@"kMRMediaRemoteNowPlayingInfoElapsedTime"] doubleValue], 0.0);
                    double rate = sanitizeDouble([d[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] doubleValue], 0.0);
                    NSString *state = (rate > 0.0) ? @"playing" : @"paused";
                    
                    NSData *artData = d[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                    NSString *artB64 = @"";
                    if (artData.length > 50) {
                        NSString *artKey = [NSString stringWithFormat:@"%@_%lu", title, (unsigned long)artData.length];
                        if ([artKey isEqualToString:cachedArtKey] && cachedArtB64.length > 0) {
                            artB64 = cachedArtB64;
                        } else {
                            if (artData.length > 350000) {
                                NSImage *img = [[NSImage alloc] initWithData:artData];
                                if (img) {
                                    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:img.TIFFRepresentation];
                                    NSDictionary *props = @{NSImageCompressionFactor: @(0.65)};
                                    NSData *jpgData = [rep representationUsingType:NSBitmapImageFileTypeJPEG properties:props];
                                    if (jpgData.length > 0) {
                                        artB64 = [jpgData base64EncodedStringWithOptions:0] ?: @"";
                                        cachedArtB64 = artB64;
                                        cachedArtKey = artKey;
                                    }
                                }
                            }
                            if (artB64.length == 0) {
                                artB64 = [artData base64EncodedStringWithOptions:0] ?: @"";
                                cachedArtB64 = artB64;
                                cachedArtKey = artKey;
                            }
                        }
                    }
                    
                    if (title.length > 0) {
                        mrResult = @{
                            @"player": @"MediaRemote",
                            @"state": state,
                            @"title": title,
                            @"artist": artist.length > 0 ? artist : @"Reprodução do Mac",
                            @"album": album,
                            @"duration": @(duration),
                            @"position": @(position),
                            @"artwork": artB64 ?: @""
                        };
                    }
                }
                dispatch_semaphore_signal(sem);
            });
            
            dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)));
        } @catch (NSException *e) {}
        
        if (mrResult && [mrResult[@"title"] length] > 0 && [mrResult[@"artwork"] length] > 0) {
            cachedMedia = mrResult;
            lastActiveMediaTime = now;
            return mrResult;
        }
        
        // 2. Fallback to AppleScript for Apple Music & Spotify if MediaRemote dictionary was empty or missing artwork
        BOOL isMusic = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.Music"].count > 0;
        BOOL isSpotify = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.spotify.client"].count > 0;
        
        if (isMusic || isSpotify) {
            NSString *script = nil;
            if (isMusic) {
                script = @"tell application \"Music\"\n"
                         @"try\n"
                         @"set pState to player state as string\n"
                         @"if pState is not \"stopped\" then\n"
                         @"set tName to name of current track\n"
                         @"set tArtist to artist of current track\n"
                         @"set tAlbum to album of current track\n"
                         @"set tPos to player position\n"
                         @"set tDur to duration of current track\n"
                         @"set hasArt to \"false\"\n"
                         @"try\n"
                         @"if (count of artworks of current track) > 0 then\n"
                         @"set art to artwork 1 of current track\n"
                         @"set rawData to raw data of art\n"
                         @"set outPath to ((POSIX file \"/tmp/apple_music_art.raw\") as string)\n"
                         @"set fRef to (open for access file outPath with write permission)\n"
                         @"set eof fRef to 0\n"
                         @"write rawData to fRef\n"
                         @"close access fRef\n"
                         @"set hasArt to \"true\"\n"
                         @"end if\n"
                         @"on error\n"
                         @"try\n"
                         @"close access file ((POSIX file \"/tmp/apple_music_art.raw\") as string)\n"
                         @"end try\n"
                         @"end try\n"
                         @"return \"Music|||\" & pState & \"|||\" & tName & \"|||\" & tArtist & \"|||\" & tAlbum & \"|||\" & (tDur as string) & \"|||\" & (tPos as string) & \"|||\" & hasArt\n"
                         @"else\n"
                         @"return \"Music|||stopped|||||||||0|||0|||false\"\n"
                         @"end if\n"
                         @"on error\n"
                         @"return \"Music|||stopped|||||||||0|||0|||false\"\n"
                         @"end try\n"
                         @"end tell";
            } else if (isSpotify) {
                script = @"tell application \"Spotify\"\n"
                         @"try\n"
                         @"set pState to player state as string\n"
                         @"if pState is not \"stopped\" then\n"
                         @"set tName to name of current track\n"
                         @"set tArtist to artist of current track\n"
                         @"set tAlbum to album of current track\n"
                         @"set tPos to player position\n"
                         @"set tDur to (duration of current track) / 1000\n"
                         @"set artUrl to \"\"\n"
                         @"try\n"
                         @"set artUrl to artwork url of current track\n"
                         @"end try\n"
                         @"return \"Spotify|||\" & pState & \"|||\" & tName & \"|||\" & tArtist & \"|||\" & tAlbum & \"|||\" & (tDur as string) & \"|||\" & (tPos as string) & \"|||\" & artUrl\n"
                         @"else\n"
                         @"return \"Spotify|||stopped|||||||||0|||0|||\"\n"
                         @"end if\n"
                         @"on error\n"
                         @"return \"Spotify|||stopped|||||||||0|||0|||\"\n"
                         @"end try\n"
                         @"end tell";
            }
            
            NSString *res = @"";
            @try {
                NSTask *task = [[NSTask alloc] init];
                task.launchPath = @"/usr/bin/osascript";
                task.arguments = @[@"-e", script];
                NSPipe *pipe = [NSPipe pipe];
                task.standardOutput = pipe;
                task.standardError = [NSPipe pipe];
                [task launch];
                [task waitUntilExit];
                
                NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
                res = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
            } @catch (NSException *e) {}
            
            NSArray *parts = [res componentsSeparatedByString:@"|||"];
            NSString *player = parts.count > 0 ? parts[0] : @"None";
            NSString *state = parts.count > 1 ? parts[1] : @"stopped";
            NSString *title = parts.count > 2 ? parts[2] : @"";
            NSString *artist = parts.count > 3 ? parts[3] : @"";
            NSString *album = parts.count > 4 ? parts[4] : @"";
            
            NSString *durStr = parts.count > 5 ? [parts[5] stringByReplacingOccurrencesOfString:@"," withString:@"."] : @"0";
            NSString *posStr = parts.count > 6 ? [parts[6] stringByReplacingOccurrencesOfString:@"," withString:@"."] : @"0";
            double duration = sanitizeDouble([durStr doubleValue], 0.0);
            double position = sanitizeDouble([posStr doubleValue], 0.0);
            NSString *hasArtOrUrl = parts.count > 7 ? parts[7] : @"";
            
            NSString *artB64 = @"";
            if ([player isEqualToString:@"Music"]) {
                if ([hasArtOrUrl isEqualToString:@"true"] && [[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/apple_music_art.raw"]) {
                    NSString *artKey = [NSString stringWithFormat:@"%@_%@", artist, title];
                    if (![artKey isEqualToString:cachedArtKey] || cachedArtB64.length == 0) {
                        NSString *artJpg = @"/tmp/apple_music_art.jpg";
                        @try {
                            NSTask *sipsTask = [[NSTask alloc] init];
                            sipsTask.launchPath = @"/usr/bin/sips";
                            sipsTask.arguments = @[@"-s", @"format", @"jpeg", @"-s", @"formatOptions", @"65", @"-Z", @"480", @"/tmp/apple_music_art.raw", @"--out", artJpg];
                            [sipsTask launch];
                            [sipsTask waitUntilExit];
                        } @catch (NSException *e) {}
                        
                        NSData *raw = [NSData dataWithContentsOfFile:artJpg];
                        if (!raw || raw.length == 0) {
                            raw = [NSData dataWithContentsOfFile:@"/tmp/apple_music_art.raw"];
                        }
                        if (raw.length > 50) {
                            cachedArtB64 = [raw base64EncodedStringWithOptions:0] ?: @"";
                            cachedArtKey = artKey;
                        }
                    }
                    artB64 = cachedArtB64;
                }
            } else if ([player isEqualToString:@"Spotify"]) {
                artB64 = hasArtOrUrl;
            }
            
            if (title.length > 0) {
                cachedMedia = @{
                    @"player": player,
                    @"state": state,
                    @"title": title,
                    @"artist": artist,
                    @"album": album,
                    @"duration": @(duration),
                    @"position": @(position),
                    @"artwork": artB64 ?: @""
                };
                lastActiveMediaTime = now;
                return cachedMedia;
            }
        }
        
        if (mrResult && [mrResult[@"title"] length] > 0) {
            cachedMedia = mrResult;
            lastActiveMediaTime = now;
            return mrResult;
        }
        
        // Retain last known track for 30s when paused
        if (cachedMedia[@"title"] && (now - lastActiveMediaTime < 30.0)) {
            NSMutableDictionary *m = [cachedMedia mutableCopy];
            m[@"state"] = @"paused";
            return m;
        }
        
        return @{
            @"player": @"None",
            @"state": @"stopped",
            @"title": @"",
            @"artist": @"",
            @"album": @"",
            @"duration": @(0),
            @"position": @(0),
            @"artwork": @""
        };
    }
}

// MARK: - Server & WebSocket
@interface TouchBarServer : NSObject <NSNetServiceDelegate>
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, strong) NSNetService *netService;
@property (nonatomic, strong) dispatch_source_t broadcastTimer;
@property (nonatomic, copy) NSString *lastWallpaperB64;
@property (nonatomic, copy) void (^onStatusChange)(NSString *frontApp, NSString *clientIp, int clientCount);
- (instancetype)initWithPort:(uint16_t)port;
- (void)start;
- (void)stop;
- (void)broadcastStatus:(NSString *)frontApp;
- (void)broadcastDeckConfig;
- (void)broadcastWallpaperIfChanged;
- (void)broadcastToast:(NSString *)msg;
- (void)handleIllustratorCommand:(NSString *)cmd;
@end

static TouchBarServer *g_server = nil;
static NSMutableArray<NSNumber *> *g_clientSockets = nil;
static int g_serverSocket = -1;

@implementation TouchBarServer

- (instancetype)initWithPort:(uint16_t)port {
    self = [super init];
    if (self) {
        _port = port;
        _lastWallpaperB64 = @"";
        g_clientSockets = [NSMutableArray array];
    }
    return self;
}

- (void)start {
    [self setupBonjour];
    [self setupMediaRemoteNotifications];
    [self startSocketServer];
    [self startPeriodicBroadcast];
    [[MacMicEngine shared] start];
    StartAudioDSPEngine();
}

- (void)setupMediaRemoteNotifications {
    MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_get_main_queue());
    extern CFStringRef kMRMediaRemoteNowPlayingInfoDidChangeNotification;
    __weak typeof(self) weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:(__bridge NSString *)kMRMediaRemoteNowPlayingInfoDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf broadcastStatus:nil];
        }
    }];
}

- (void)setupBonjour {
    NSString *name = [NSString stringWithFormat:@"Mac TouchBar (%@)", [[NSHost currentHost] localizedName] ?: @"Mac"];
    self.netService = [[NSNetService alloc] initWithDomain:@"local." type:@"_macdeck._tcp." name:name port:self.port];
    [self.netService setDelegate:self];
    [self.netService publish];
}

- (void)startPeriodicBroadcast {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
    self.broadcastTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(self.broadcastTimer, dispatch_time(DISPATCH_TIME_NOW, 0), 1.0 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
    
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.broadcastTimer, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        @synchronized (g_clientSockets) {
            if (g_clientSockets.count == 0) return;
        }
        [strongSelf broadcastStatus:nil];
        [strongSelf broadcastWallpaperIfChanged];
    });
    dispatch_resume(self.broadcastTimer);
}

- (void)startSocketServer {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        g_serverSocket = socket(AF_INET, SOCK_STREAM, 0);
        if (g_serverSocket < 0) return;
        
        int opt = 1;
        setsockopt(g_serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
        
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_port = htons(self.port);
        
        if (bind(g_serverSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            close(g_serverSocket);
            return;
        }
        
        if (listen(g_serverSocket, 10) < 0) {
            close(g_serverSocket);
            return;
        }
        
        while (g_serverSocket >= 0) {
            struct sockaddr_in clientAddr;
            socklen_t clientLen = sizeof(clientAddr);
            int clientSock = accept(g_serverSocket, (struct sockaddr *)&clientAddr, &clientLen);
            if (clientSock < 0) break;
            
            int nosig = 1;
            setsockopt(clientSock, SOL_SOCKET, SO_NOSIGPIPE, &nosig, sizeof(nosig));
            
            char clientIp[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &(clientAddr.sin_addr), clientIp, INET_ADDRSTRLEN);
            NSString *ipStr = [NSString stringWithUTF8String:clientIp];
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self handleClient:clientSock ip:ipStr];
            });
        }
    });
}

- (void)handleClient:(int)sock ip:(NSString *)clientIp {
    char buffer[4096];
    ssize_t bytesRead = read(sock, buffer, sizeof(buffer) - 1);
    if (bytesRead <= 0) {
        close(sock);
        return;
    }
    buffer[bytesRead] = '\0';
    NSString *request = [NSString stringWithUTF8String:buffer];
    
    if ([request containsString:@"Upgrade: websocket"] || [request containsString:@"upgrade: websocket"]) {
        NSString *secKey = nil;
        NSArray *lines = [request componentsSeparatedByString:@"\r\n"];
        for (NSString *line in lines) {
            if ([line.lowercaseString hasPrefix:@"sec-websocket-key:"]) {
                secKey = [[line substringFromIndex:18] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                break;
            }
        }
        
        if (secKey) {
            NSString *magic = [secKey stringByAppendingString:@"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"];
            NSData *magicData = [magic dataUsingEncoding:NSUTF8StringEncoding];
            unsigned char digest[CC_SHA1_DIGEST_LENGTH];
            CC_SHA1(magicData.bytes, (CC_LONG)magicData.length, digest);
            NSData *shaData = [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
            NSString *acceptKey = [shaData base64EncodedStringWithOptions:0];
            
            NSString *response = [NSString stringWithFormat:
                @"HTTP/1.1 101 Switching Protocols\r\n"
                @"Upgrade: websocket\r\n"
                @"Connection: Upgrade\r\n"
                @"Sec-WebSocket-Accept: %@\r\n\r\n", acceptKey];
            
            writeFull(sock, response.UTF8String, response.length);
            
            @synchronized (g_clientSockets) {
                [g_clientSockets addObject:@(sock)];
            }
            
            if (self.onStatusChange) {
                NSString *front = [[NSWorkspace sharedWorkspace] frontmostApplication].localizedName ?: @"Finder";
                self.onStatusChange(front, clientIp, (int)g_clientSockets.count);
            }
            
            [self sendInitialStateToSocket:sock];
            [self readWebSocketLoop:sock clientIp:clientIp];
        }
    } else {
        close(sock);
    }
}

- (void)readWebSocketLoop:(int)sock clientIp:(NSString *)clientIp {
    unsigned char header[2];
    while (true) {
        ssize_t hRead = 0;
        while (hRead < 2) {
            ssize_t n = read(sock, header + hRead, (size_t)(2 - hRead));
            if (n <= 0) break;
            hRead += n;
        }
        if (hRead < 2) break;
        
        int opcode = header[0] & 0x0F;
        if (opcode == 0x8) break; // Close
        
        BOOL isMasked = (header[1] & 0x80) != 0;
        uint64_t payloadLen = header[1] & 0x7F;
        
        if (payloadLen == 126) {
            unsigned char ext[2];
            ssize_t er = 0;
            while (er < 2) {
                ssize_t n = read(sock, ext + er, (size_t)(2 - er));
                if (n <= 0) break;
                er += n;
            }
            if (er < 2) break;
            payloadLen = (ext[0] << 8) | ext[1];
        } else if (payloadLen == 127) {
            unsigned char ext[8];
            ssize_t er = 0;
            while (er < 8) {
                ssize_t n = read(sock, ext + er, (size_t)(8 - er));
                if (n <= 0) break;
                er += n;
            }
            if (er < 8) break;
            payloadLen = 0;
            for (int i = 0; i < 8; i++) payloadLen = (payloadLen << 8) | ext[i];
        }
        
        unsigned char mask[4] = {0};
        if (isMasked) {
            ssize_t mr = 0;
            while (mr < 4) {
                ssize_t r = read(sock, mask + mr, (size_t)(4 - mr));
                if (r <= 0) break;
                mr += r;
            }
            if (mr < 4) break;
        }
        
        NSMutableData *payloadData = [NSMutableData dataWithLength:(NSUInteger)payloadLen];
        unsigned char *bytes = (unsigned char *)payloadData.mutableBytes;
        ssize_t totalRead = 0;
        while (totalRead < (ssize_t)payloadLen) {
            ssize_t r = read(sock, bytes + totalRead, (size_t)(payloadLen - totalRead));
            if (r <= 0) break;
            totalRead += r;
        }
        
        if (totalRead < (ssize_t)payloadLen) break;
        
        if (isMasked) {
            for (uint64_t i = 0; i < payloadLen; i++) {
                bytes[i] ^= mask[i % 4];
            }
        }
        
        if (opcode == 0x9) {
            // Send Pong Frame 0x8A
            NSMutableData *pong = [NSMutableData data];
            uint8_t p1 = 0x8A;
            [pong appendBytes:&p1 length:1];
            uint8_t p2 = (uint8_t)(payloadLen <= 125 ? payloadLen : 0);
            [pong appendBytes:&p2 length:1];
            if (payloadLen > 0 && payloadLen <= 125) {
                [pong appendData:payloadData];
            }
            @synchronized (self) {
                writeFull(sock, pong.bytes, pong.length);
            }
        } else if (opcode == 0x1) {
            NSString *msg = [[NSString alloc] initWithData:payloadData encoding:NSUTF8StringEncoding];
            if (msg) {
                [self handleClientMessage:msg];
            }
        }
    }
    
    @synchronized (g_clientSockets) {
        [g_clientSockets removeObject:@(sock)];
    }
    close(sock);
    
    if (self.onStatusChange) {
        NSString *front = [[NSWorkspace sharedWorkspace] frontmostApplication].localizedName ?: @"Finder";
        self.onStatusChange(front, @"", (int)g_clientSockets.count);
    }
}

- (void)handleClientMessage:(NSString *)jsonText {
    NSData *data = [jsonText dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![dict isKindOfClass:[NSDictionary class]]) return;
    
    NSString *action = dict[@"action"];
    NSDictionary *params = dict[@"params"] ?: @{};
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self executeAction:action params:params];
    });
}

- (BOOL)isAppRunning:(NSString *)bundleId {
    NSArray *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleId];
    return apps.count > 0;
}

- (BOOL)isIllustratorRunning {
    for (NSRunningApplication *a in [[NSWorkspace sharedWorkspace] runningApplications]) {
        if ([a.bundleIdentifier.lowercaseString containsString:@"illustrator"] ||
            [a.localizedName.lowercaseString containsString:@"illustrator"]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)activateIllustrator {
    NSArray<NSRunningApplication *> *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.adobe.illustrator"];
    if (apps.count == 0) {
        for (NSRunningApplication *a in [[NSWorkspace sharedWorkspace] runningApplications]) {
            if ([a.localizedName.lowercaseString containsString:@"illustrator"]) {
                apps = @[a];
                break;
            }
        }
    }
    if (apps.count > 0) {
        NSRunningApplication *app = apps.firstObject;
        if (@available(macOS 14.0, *)) {
            [app activateWithOptions:NSApplicationActivateAllWindows];
        } else {
            [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        }
        usleep(15000); // 15ms pause for window focus
        return YES;
    }
    return NO;
}

- (void)executeAction:(NSString *)action params:(NSDictionary *)params {
    if ([action isEqualToString:@"press_esc"]) {
        [self simulateKey:kVK_Escape];
    } else if ([action isEqualToString:@"set_volume"]) {
        int vol = [params[@"volume"] intValue];
        [self runScript:[NSString stringWithFormat:@"set volume output volume %d", MAX(0, MIN(100, vol))]];
        [self broadcastStatus:nil];
    } else if ([action isEqualToString:@"toggle_mute"]) {
        NSString *muted = [self runScript:@"output muted of (get volume settings)"];
        BOOL isMuted = [muted containsString:@"true"];
        [self runScript:[NSString stringWithFormat:@"set volume output muted %@", isMuted ? @"false" : @"true"]];
        [self broadcastStatus:nil];
    } else if ([action isEqualToString:@"set_brightness"]) {
        int val = [params[@"brightness"] intValue];
        if (val > 50) [self runScript:@"tell application \"System Events\" to key code 144"];
        else [self runScript:@"tell application \"System Events\" to key code 145"];
    } else if ([action isEqualToString:@"media_play_pause"]) {
        Boolean mrOk = MRMediaRemoteSendCommand(2, nil); // Universal TogglePlayPause (Chrome, Safari, Spotify, Music)
        if (!mrOk) {
            if ([self isAppRunning:@"com.apple.Music"]) {
                [self runScript:@"tell application \"Music\" to playpause"];
            } else if ([self isAppRunning:@"com.spotify.client"]) {
                [self runScript:@"tell application \"Spotify\" to playpause"];
            }
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self broadcastStatus:nil];
        });
    } else if ([action isEqualToString:@"media_next"]) {
        Boolean mrOk = MRMediaRemoteSendCommand(4, nil); // Universal Next Track
        if (!mrOk) {
            if ([self isAppRunning:@"com.apple.Music"]) {
                [self runScript:@"tell application \"Music\" to next track"];
            } else if ([self isAppRunning:@"com.spotify.client"]) {
                [self runScript:@"tell application \"Spotify\" to next track"];
            }
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self broadcastStatus:nil];
        });
    } else if ([action isEqualToString:@"media_prev"]) {
        Boolean mrOk = MRMediaRemoteSendCommand(5, nil); // Universal Previous Track
        if (!mrOk) {
            if ([self isAppRunning:@"com.apple.Music"]) {
                [self runScript:@"tell application \"Music\" to previous track"];
            } else if ([self isAppRunning:@"com.spotify.client"]) {
                [self runScript:@"tell application \"Spotify\" to previous track"];
            }
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self broadcastStatus:nil];
        });
    } else if ([action isEqualToString:@"set_player_position"]) {
        double pos = [params[@"position"] doubleValue];
        [self runScript:[NSString stringWithFormat:@"tell application \"Music\" to set player position to %f", pos]];
    } else if ([action isEqualToString:@"toggle_favorite"]) {
        [self runScript:@"tell application \"Music\" to set favorited of current track to not (favorited of current track)"];
    } else if ([action isEqualToString:@"type_emoji"] || [action isEqualToString:@"type_text"]) {
        NSString *text = params[@"text"];
        if (text.length > 0) {
            [self insertText:text];
        }
    } else if ([action isEqualToString:@"send_hotkey"]) {
        NSString *key = params[@"key"] ?: @"";
        NSArray *mods = params[@"modifiers"] ?: @[];
        if ([key.lowercaseString isEqualToString:@"x"] || [key.lowercaseString isEqualToString:@"i"]) {
            [self activateIllustrator];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.03 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self simulateHotkey:key modifiers:mods];
            if (key.length == 1 && mods.count == 0) {
                [self runScript:[NSString stringWithFormat:@"tell application \"System Events\" to tell process \"Adobe Illustrator\" to keystroke \"%@\"", key.lowercaseString]];
            }
        });
    } else if ([action isEqualToString:@"parse_hotkey_string"]) {
        NSString *str = params[@"hotkey"] ?: @"";
        [self executeHotkeyString:str];
    } else if ([action isEqualToString:@"launch_app"]) {
        NSString *app = params[@"app"];
        if (app.length > 0) {
            if ([app hasPrefix:@"/"]) {
                [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:app]];
            } else {
                [[NSWorkspace sharedWorkspace] openApplicationAtURL:[NSURL fileURLWithPath:[NSString stringWithFormat:@"/Applications/%@.app", app]]
                                                      configuration:[NSWorkspaceOpenConfiguration configuration]
                                                  completionHandler:nil];
            }
        }
    } else if ([action isEqualToString:@"terminal_cmd"]) {
        NSString *cmd = params[@"cmd"] ?: @"";
        if (cmd.length > 0) {
            [self insertText:cmd];
        }
    } else if ([action isEqualToString:@"play_sound"]) {
        NSString *sound = params[@"sound"];
        if (sound.length > 0) {
            [[NSSound soundNamed:sound] play];
        }
    } else if ([action isEqualToString:@"system_action"] || [action isEqualToString:@"system_command"]) {
        NSString *cmd = params[@"command"];
        [self handleSystemCommand:cmd];
    } else if ([action isEqualToString:@"illustrator_command"]) {
        NSString *cmd = params[@"command"] ?: @"";
        if (cmd.length > 0) {
            NSLog(@"[MacTouchBar] ✒️ Illustrator command received: %@", cmd);
            [self handleIllustratorCommand:cmd];
        }
    } else if ([action isEqualToString:@"illustrator_set_color"]) {
        NSString *hex = params[@"hex"] ?: @"FF0000";
        NSString *target = params[@"target"] ?: @"fill";
        [self queueIllustratorColor:hex target:target];
    } else if ([action isEqualToString:@"set_mic_gain"]) {
        float gain = [params[@"gain"] floatValue];
        [[MacMicEngine shared] setVolume:gain];
    } else if ([action isEqualToString:@"set_mic_dsp"]) {
        BOOL enabled = [params[@"enabled"] boolValue];
        const char *cmd = enabled ? "dsp_on" : "dsp_off";
        int sock = socket(AF_INET, SOCK_DGRAM, 0);
        if (sock >= 0) {
            struct sockaddr_in dest;
            memset(&dest, 0, sizeof(dest));
            dest.sin_family = AF_INET;
            dest.sin_port = htons(9877);
            inet_pton(AF_INET, "127.0.0.1", &dest.sin_addr);
            sendto(sock, cmd, strlen(cmd), 0, (struct sockaddr *)&dest, sizeof(dest));
            close(sock);
            NSLog(@"[MacTouchBar] Sent DSP control command: %s to 127.0.0.1:9877", cmd);
        }
    } else if ([action isEqualToString:@"install_virtual_mic"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *err = nil;
            BOOL ok = [VirtualMicManager installVirtualAudioDriverWithError:&err];
            NSLog(@"[MacTouchBar] install_virtual_mic result: %d, err: %@", ok, err);
            [self broadcastStatus:nil];
        });
    } else if ([action isEqualToString:@"set_default_mic"]) {
        [VirtualMicManager setDefaultInputToVirtualMic];
        [self broadcastStatus:nil];
    } else if ([action isEqualToString:@"get_status"]) {
        [self broadcastStatus:nil];
        [self broadcastDeckConfig];
        @try {
            NSString *wp = getWallpaperBase64();
            if (wp.length > 50) {
                NSDictionary *wpMsg = @{
                    @"type": @"wallpaper_update",
                    @"wallpaperBase64": wp
                };
                NSData *wpData = [NSJSONSerialization dataWithJSONObject:wpMsg options:0 error:nil];
                if (wpData) {
                    @synchronized (g_clientSockets) {
                        for (NSNumber *sockNum in [g_clientSockets copy]) {
                            [self sendWebSocketFrame:wpData toSocket:sockNum.intValue];
                        }
                    }
                }
            }
        } @catch (NSException *e) {}
    }
}

- (void)executeHotkeyString:(NSString *)hotkeyStr {
    NSArray *parts = [hotkeyStr componentsSeparatedByString:@"+"];
    NSMutableArray *mods = [NSMutableArray array];
    NSString *key = @"";
    for (NSString *p in parts) {
        NSString *lp = [p.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([lp isEqualToString:@"cmd"] || [lp isEqualToString:@"command"]) [mods addObject:@"command"];
        else if ([lp isEqualToString:@"shift"]) [mods addObject:@"shift"];
        else if ([lp isEqualToString:@"opt"] || [lp isEqualToString:@"option"] || [lp isEqualToString:@"alt"]) [mods addObject:@"option"];
        else if ([lp isEqualToString:@"ctrl"] || [lp isEqualToString:@"control"]) [mods addObject:@"control"];
        else key = lp;
    }
    if (key.length > 0) {
        [self simulateHotkey:key modifiers:mods];
    }
}

- (void)handleSystemCommand:(NSString *)cmd {
    if ([cmd isEqualToString:@"spotlight"]) {
        [self simulateHotkey:@"space" modifiers:@[@"command"]];
    } else if ([cmd isEqualToString:@"mission_control"]) {
        [self runScript:@"tell application \"Mission Control\" to launch"];
    } else if ([cmd isEqualToString:@"launchpad"] || [cmd isEqualToString:@"toggle_launchpad"]) {
        [self runScript:@"tell application \"System Events\" to key code 53 using {command down}"];
        [self runScript:@"tell application \"Launchpad\" to launch"];
    } else if ([cmd isEqualToString:@"screenshot_interactive"] || [cmd isEqualToString:@"screenshot_area"]) {
        [self simulateHotkey:@"4" modifiers:@[@"command", @"shift"]];
    } else if ([cmd isEqualToString:@"screenshot_fullscreen"]) {
        [self simulateHotkey:@"3" modifiers:@[@"command", @"shift"]];
    } else if ([cmd isEqualToString:@"screenshot_recording"] || [cmd isEqualToString:@"screen_record"]) {
        [self simulateHotkey:@"5" modifiers:@[@"command", @"shift"]];
    } else if ([cmd isEqualToString:@"show_desktop"] || [cmd isEqualToString:@"mesa"]) {
        [self simulateKey:kVK_F11];
    } else if ([cmd isEqualToString:@"lock_screen"] || [cmd isEqualToString:@"bloquear"]) {
        [self simulateHotkey:@"q" modifiers:@[@"command", @"control"]];
    } else if ([cmd isEqualToString:@"restart_mac"]) {
        [self runScript:@"tell application \"System Events\" to restart"];
    } else if ([cmd isEqualToString:@"shutdown_mac"]) {
        [self runScript:@"tell application \"System Events\" to shut down"];
    } else if ([cmd isEqualToString:@"sleep_mac"]) {
        [self runScript:@"tell application \"System Events\" to sleep"];
    } else if ([cmd isEqualToString:@"shazam_recognize"]) {
        [self runScript:@"tell application \"Music\" to activate"];
    } else if ([cmd isEqualToString:@"empty_trash"]) {
        [self simulateHotkey:@"delete" modifiers:@[@"command", @"shift", @"option"]];
    } else if ([cmd isEqualToString:@"finder_new_folder"]) {
        [self simulateHotkey:@"n" modifiers:@[@"command", @"shift"]];
    }
}

- (void)broadcastStatus:(NSString *)frontApp {
    @try {
        NSString *appName = frontApp ?: [[NSWorkspace sharedWorkspace] frontmostApplication].localizedName ?: @"Finder";
        NSString *volStr = [self runScript:@"output volume of (get volume settings)"];
        int volume = [volStr intValue];
        NSString *muteStr = [self runScript:@"output muted of (get volume settings)"];
        BOOL isMuted = [muteStr containsString:@"true"];
        NSString *wp = getWallpaperBase64();
        
        BOOL vmInstalled = [VirtualMicManager isVirtualMicInstalled];
        NSString *vmName = [VirtualMicManager installedVirtualMicName] ?: @"";
        
        NSMutableArray *runningAppNames = [NSMutableArray array];
        for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
            if (app.localizedName) [runningAppNames addObject:app.localizedName];
            if (app.bundleIdentifier) [runningAppNames addObject:app.bundleIdentifier];
            if (app.bundleURL.path) [runningAppNames addObject:app.bundleURL.path];
        }
        
        NSDictionary *status = @{
            @"type": @"status_update",
            @"mac_name": [[NSHost currentHost] localizedName] ?: @"Hackintosh",
            @"frontmost_app": appName,
            @"running_apps": runningAppNames,
            @"volume": @(volume),
            @"is_muted": @(isMuted),
            @"brightness": @(75),
            @"battery": getBatteryInfoDict() ?: @{},
            @"airpods": getAirPodsInfoDict() ?: @{},
            @"media": getMacMediaInfoFull() ?: @{},
            @"wallpaperBase64": wp ?: @"",
            @"virtual_mic_installed": @(vmInstalled),
            @"virtual_mic_name": vmName
        };
        
        NSError *err = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:status options:0 error:&err];
        if (!data || err) return;
        
        @synchronized (g_clientSockets) {
            for (NSNumber *sockNum in [g_clientSockets copy]) {
                [self sendWebSocketFrame:data toSocket:sockNum.intValue];
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[MacTouchBar] broadcastStatus exception caught: %@", e);
    }
}

- (void)broadcastDeckConfig {
    @try {
        NSArray *buttonsDict = [[DeckManager shared] toDictionaryArray];
        NSDictionary *msg = @{
            @"type": @"deck_config_update",
            @"buttons": buttonsDict ?: @[]
        };
        NSError *err = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:msg options:0 error:&err];
        if (!data || err) return;
        
        @synchronized (g_clientSockets) {
            for (NSNumber *sockNum in [g_clientSockets copy]) {
                [self sendWebSocketFrame:data toSocket:sockNum.intValue];
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[MacTouchBar] broadcastDeckConfig exception caught: %@", e);
    }
}

- (void)broadcastWallpaperIfChanged {
    @try {
        NSString *wp = getWallpaperBase64();
        if (wp.length > 50 && ![wp isEqualToString:self.lastWallpaperB64]) {
            self.lastWallpaperB64 = wp;
            NSDictionary *msg = @{
                @"type": @"wallpaper_update",
                @"wallpaperBase64": wp
            };
            NSError *err = nil;
            NSData *data = [NSJSONSerialization dataWithJSONObject:msg options:0 error:&err];
            if (data && !err) {
                @synchronized (g_clientSockets) {
                    for (NSNumber *sockNum in [g_clientSockets copy]) {
                        [self sendWebSocketFrame:data toSocket:sockNum.intValue];
                    }
                }
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[MacTouchBar] broadcastWallpaperIfChanged exception caught: %@", e);
    }
}

- (void)broadcastIllustratorColors:(NSArray<NSString *> *)colors {
    if (!colors || colors.count == 0) return;
    NSDictionary *msg = @{
        @"type": @"illustrator_recent_colors",
        @"colors": colors
    };
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:msg options:0 error:&err];
    if (data && !err) {
        @synchronized (g_clientSockets) {
            for (NSNumber *sockNum in [g_clientSockets copy]) {
                [self sendWebSocketFrame:data toSocket:sockNum.intValue];
            }
        }
    }
}

- (void)broadcastToast:(NSString *)msg {
    if (!msg || msg.length == 0) return;
    NSDictionary *toast = @{
        @"type": @"toast",
        @"message": msg
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:toast options:0 error:nil];
    if (data) {
        @synchronized (g_clientSockets) {
            for (NSNumber *sockNum in [g_clientSockets copy]) {
                [self sendWebSocketFrame:data toSocket:sockNum.intValue];
            }
        }
    }
}

static NSString *g_pendingColorHex = nil;
static NSString *g_pendingColorTarget = nil;
static BOOL g_isSettingColor = NO;

- (void)queueIllustratorColor:(NSString *)hex target:(NSString *)target {
    if (!hex || hex.length == 0) return;
    @synchronized (self) {
        g_pendingColorHex = [hex copy];
        g_pendingColorTarget = [target copy] ?: @"fill";
        if (g_isSettingColor) {
            return;
        }
        g_isSettingColor = YES;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        while (YES) {
            NSString *currentHex = nil;
            NSString *currentTarget = nil;
            @synchronized (self) {
                currentHex = g_pendingColorHex;
                currentTarget = g_pendingColorTarget;
                g_pendingColorHex = nil;
            }
            if (!currentHex) {
                @synchronized (self) {
                    g_isSettingColor = NO;
                }
                break;
            }
            [self applyColorToIllustratorDirect:currentHex target:currentTarget];
        }
    });
}

- (void)applyColorToIllustratorDirect:(NSString *)hex target:(NSString *)target {
    if (![self isIllustratorRunning]) return;
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    if (hex.length != 6) return;
    
    @try {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb setString:[NSString stringWithFormat:@"#%@", hex] forType:NSPasteboardTypeString];
    } @catch (NSException *e) {}
    
    NSString *jsCode = [NSString stringWithFormat:
        @"var hex='%@';var r=parseInt(hex.substring(0,2),16);var g=parseInt(hex.substring(2,4),16);var b=parseInt(hex.substring(4,6),16);var c=new RGBColor();c.red=r;c.green=g;c.blue=b;var isStroke=('%@'==='stroke');function applyToItem(it){if(!it)return;try{if(isStroke){if(it.stroked!==undefined){it.stroked=true;it.strokeColor=c;}}else{if(it.filled!==undefined){it.filled=true;it.fillColor=c;}}if(it.typename==='TextFrame'){var tr=it.textRange||(it.story?it.story.textRange:null);if(tr&&tr.characterAttributes){if(isStroke){tr.characterAttributes.strokeColor=c;tr.characterAttributes.stroked=true;}else{tr.characterAttributes.fillColor=c;}}}else if(it.typename==='GroupItem'&&it.pageItems){for(var k=0;k<it.pageItems.length;k++)applyToItem(it.pageItems[k]);}}catch(e){}}if(app.documents.length>0&&app.selection.length>0){for(var i=0;i<app.selection.length;i++)applyToItem(app.selection[i]);app.redraw();}", hex, target];
    [self runIllustratorJS:jsCode];
}

- (NSString *)runIllustratorJSSync:(NSString *)js {
    if (![self isIllustratorRunning]) return @"ERR:NOT_RUNNING";
    if (!js || js.length == 0) return @"";
    NSString *wrapped = [NSString stringWithFormat:
        @"try {\n"
        @"  var _prevLvl = app.userInteractionLevel;\n"
        @"  app.userInteractionLevel = UserInteractionLevel.DONTDISPLAYALERTS;\n"
        @"  var _res = (function(){\n%@\n})();\n"
        @"  app.userInteractionLevel = _prevLvl;\n"
        @"  _res !== undefined ? ('' + _res) : 'OK';\n"
        @"} catch(e) { 'ERR:' + e.message; }\n", js];
        
    NSString *escaped = [wrapped stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    NSString *osa = [NSString stringWithFormat:
        @"tell application \"Adobe Illustrator\"\n"
        @"try\n"
        @"return do javascript \"%@\"\n"
        @"on error errMsg\n"
        @"return \"ERR:\" & errMsg\n"
        @"end try\n"
        @"end tell", escaped];
        
    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:osa];
    NSDictionary *err = nil;
    NSAppleEventDescriptor *desc = [appleScript executeAndReturnError:&err];
    NSString *ret = desc.stringValue;
    if (!ret || err) {
        ret = [self runScript:osa];
    }
    return ret ?: @"";
}

- (void)runIllustratorJS:(NSString *)js {
    if (!js || js.length == 0) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self runIllustratorJSSync:js];
    });
}

- (void)handleIllustratorCommand:(NSString *)cmd {
    if (![self isIllustratorRunning]) return;
    if (![cmd isEqualToString:@"get_recent_colors"]) {
        [self activateIllustrator];
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSString *js = nil;
        
        if ([cmd isEqualToString:@"save"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; try { var doc = app.activeDocument; var hasFile = false; try { if (doc.fullName) hasFile = true; } catch(e) {} if (hasFile) { doc.save(); return 'SAVED'; } else { app.executeMenuCommand('save'); return 'SAVE_DIALOG'; } } catch(e) { return 'ERR:' + e.message; }";
        } else if ([cmd isEqualToString:@"saveas"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; try { app.executeMenuCommand('saveas'); return 'SAVE_DIALOG'; } catch(e) { return 'ERR:' + e.message; }";
        } else if ([cmd isEqualToString:@"export_screens"] || [cmd isEqualToString:@"export"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self activateIllustrator];
                [self simulateHotkey:@"e" modifiers:@[@"command", @"option"]];
                [self runScript:@"tell application \"System Events\" to tell process \"Adobe Illustrator\" to keystroke \"e\" using {command down, option down}"];
            });
            [self broadcastToast:@"📤 Exportar para Telas"];
            return;
        } else if ([cmd isEqualToString:@"new"] || [cmd isEqualToString:@"new_doc"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self activateIllustrator];
                [self simulateHotkey:@"n" modifiers:@[@"command"]];
                [self runScript:@"tell application \"System Events\" to tell process \"Adobe Illustrator\" to keystroke \"n\" using {command down}"];
            });
            [self broadcastToast:@"📄 Novo Documento (⌘N)"];
            return;
        } else if ([cmd isEqualToString:@"open"] || [cmd isEqualToString:@"open_doc"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self activateIllustrator];
                [self simulateHotkey:@"o" modifiers:@[@"command"]];
                [self runScript:@"tell application \"System Events\" to tell process \"Adobe Illustrator\" to keystroke \"o\" using {command down}"];
            });
            [self broadcastToast:@"📂 Abrir Documento (⌘O)"];
            return;
        } else if ([cmd isEqualToString:@"artboard"] || [cmd isEqualToString:@"artboard_tool"] || [cmd isEqualToString:@"prancheta"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self activateIllustrator];
                [self simulateHotkey:@"o" modifiers:@[@"shift"]];
                [self runScript:@"tell application \"System Events\" to tell process \"Adobe Illustrator\" to keystroke \"o\" using {shift down}"];
            });
            [self broadcastToast:@"📐 Ferramenta Prancheta (⇧O)"];
            return;
        } else if ([cmd isEqualToString:@"group"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; if (app.selection.length === 0) return 'NO_SEL'; try { app.executeMenuCommand('group'); app.redraw(); return 'GROUPED'; } catch(e) { return 'ERR:' + e.message; }";
        } else if ([cmd isEqualToString:@"ungroup"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; if (app.selection.length === 0) return 'NO_SEL'; try { app.executeMenuCommand('ungroup'); app.redraw(); return 'UNGROUPED'; } catch(e) { return 'ERR:' + e.message; }";
        } else if ([cmd isEqualToString:@"bringToFront"] || [cmd isEqualToString:@"sendToFront"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; if (app.selection.length === 0) return 'NO_SEL'; try { app.executeMenuCommand('sendToFront'); app.redraw(); return 'OK'; } catch(e) { return 'ERR:' + e.message; }";
        } else if ([cmd isEqualToString:@"sendToBack"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; if (app.selection.length === 0) return 'NO_SEL'; try { app.executeMenuCommand('sendToBack'); app.redraw(); return 'OK'; } catch(e) { return 'ERR:' + e.message; }";
        } else if ([cmd isEqualToString:@"align_obj_left"] || [cmd isEqualToString:@"align left"] || [cmd isEqualToString:@"Horizontal Align Left"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; if (app.selection.length === 0) return 'NO_SEL'; try { app.executeMenuCommand('Horizontal Align Left'); app.redraw(); return 'OK'; } catch(e) { return 'ERR:' + e.message; }";
        } else if ([cmd isEqualToString:@"align_obj_center"] || [cmd isEqualToString:@"align horizontal center"] || [cmd isEqualToString:@"Horizontal Align Center"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; if (app.selection.length === 0) return 'NO_SEL'; try { app.executeMenuCommand('Horizontal Align Center'); app.redraw(); return 'OK'; } catch(e) { return 'ERR:' + e.message; }";
        } else if ([cmd isEqualToString:@"align_obj_right"] || [cmd isEqualToString:@"align right"] || [cmd isEqualToString:@"Horizontal Align Right"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; if (app.selection.length === 0) return 'NO_SEL'; try { app.executeMenuCommand('Horizontal Align Right'); app.redraw(); return 'OK'; } catch(e) { return 'ERR:' + e.message; }";
        } else if ([cmd isEqualToString:@"align_obj_top"] || [cmd isEqualToString:@"align top"] || [cmd isEqualToString:@"Vertical Align Top"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; if (app.selection.length === 0) return 'NO_SEL'; try { app.executeMenuCommand('Vertical Align Top'); app.redraw(); return 'OK'; } catch(e) { return 'ERR:' + e.message; }";
        } else if ([cmd isEqualToString:@"align_obj_vcenter"] || [cmd isEqualToString:@"align vertical center"] || [cmd isEqualToString:@"Vertical Align Center"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; if (app.selection.length === 0) return 'NO_SEL'; try { app.executeMenuCommand('Vertical Align Center'); app.redraw(); return 'OK'; } catch(e) { return 'ERR:' + e.message; }";
        } else if ([cmd isEqualToString:@"align_obj_bottom"] || [cmd isEqualToString:@"align bottom"] || [cmd isEqualToString:@"Vertical Align Bottom"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; if (app.selection.length === 0) return 'NO_SEL'; try { app.executeMenuCommand('Vertical Align Bottom'); app.redraw(); return 'OK'; } catch(e) { return 'ERR:' + e.message; }";
        } else if ([cmd isEqualToString:@"align_center_artboard"] || [cmd isEqualToString:@"align_artboard_center"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; if (app.selection.length === 0) return 'NO_SEL'; try { var doc = app.activeDocument; var ab = doc.artboards[doc.artboards.getActiveArtboardIndex()]; var r = ab.artboardRect; var cx = (r[0] + r[2]) / 2; var cy = (r[1] + r[3]) / 2; var sel = app.selection; var minX = sel[0].geometricBounds[0], maxY = sel[0].geometricBounds[1], maxX = sel[0].geometricBounds[2], minY = sel[0].geometricBounds[3]; for (var i = 1; i < sel.length; i++) { var b = sel[i].geometricBounds; if (b[0] < minX) minX = b[0]; if (b[1] > maxY) maxY = b[1]; if (b[2] > maxX) maxX = b[2]; if (b[3] < minY) minY = b[3]; } var scx = (minX + maxX) / 2; var scy = (maxY + minY) / 2; var dx = cx - scx; var dy = cy - scy; for (var i = 0; i < sel.length; i++) { sel[i].translate(dx, dy); } app.redraw(); return 'OK'; } catch(e) { try { app.executeMenuCommand('Horizontal Align Center'); app.executeMenuCommand('Vertical Align Center'); app.redraw(); return 'OK'; } catch(e2) { return 'ERR:' + e.message; } }";
        } else if ([cmd isEqualToString:@"Live Pathfinder Unite"] || [cmd isEqualToString:@"pathfinder_unite"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; if (app.selection.length === 0) return 'NO_SEL'; try { app.executeMenuCommand('Live Pathfinder Add'); app.executeMenuCommand('expandStyle'); app.redraw(); return 'OK'; } catch(e) { return 'ERR:' + e.message; }";
        } else if ([cmd isEqualToString:@"Live Pathfinder Minus Front"] || [cmd isEqualToString:@"pathfinder_minus_front"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; if (app.selection.length === 0) return 'NO_SEL'; try { app.executeMenuCommand('Live Pathfinder Subtract'); app.executeMenuCommand('expandStyle'); app.redraw(); return 'OK'; } catch(e) { return 'ERR:' + e.message; }";
        } else if ([cmd isEqualToString:@"Live Pathfinder Intersect"] || [cmd isEqualToString:@"pathfinder_intersect"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; if (app.selection.length === 0) return 'NO_SEL'; try { app.executeMenuCommand('Live Pathfinder Intersect'); app.executeMenuCommand('expandStyle'); app.redraw(); return 'OK'; } catch(e) { return 'ERR:' + e.message; }";
        } else if ([cmd isEqualToString:@"Live Pathfinder Exclude"] || [cmd isEqualToString:@"pathfinder_exclude"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; if (app.selection.length === 0) return 'NO_SEL'; try { app.executeMenuCommand('Live Pathfinder Exclude'); app.executeMenuCommand('expandStyle'); app.redraw(); return 'OK'; } catch(e) { return 'ERR:' + e.message; }";
        } else if ([cmd isEqualToString:@"Live Pathfinder Divide"] || [cmd isEqualToString:@"pathfinder_divide"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; if (app.selection.length === 0) return 'NO_SEL'; try { app.executeMenuCommand('Live Pathfinder Divide'); app.executeMenuCommand('expandStyle'); app.redraw(); return 'OK'; } catch(e) { return 'ERR:' + e.message; }";
        } else if ([cmd isEqualToString:@"create_outlines"] || [cmd isEqualToString:@"createOutlines"]) {
            js = @"if (app.documents.length === 0) return 'NO_DOC'; if (app.selection.length === 0) return 'NO_SEL'; try { app.executeMenuCommand('Create Outline'); app.redraw(); return 'OK'; } catch(e) { return 'ERR:' + e.message; }";
        } else {
            NSString *typoOp = nil;
            if ([cmd isEqualToString:@"font_size_up"]) typoOp = @"var s=tr.characterAttributes.size; tr.characterAttributes.size=Math.max(1,s+2);";
            else if ([cmd isEqualToString:@"font_size_down"]) typoOp = @"var s=tr.characterAttributes.size; tr.characterAttributes.size=Math.max(1,s-2);";
            else if ([cmd isEqualToString:@"leading_up"]) typoOp = @"var l=tr.characterAttributes.leading||(tr.characterAttributes.size*1.2); tr.characterAttributes.autoLeading=false; tr.characterAttributes.leading=Math.max(1,l+2);";
            else if ([cmd isEqualToString:@"leading_down"]) typoOp = @"var l=tr.characterAttributes.leading||(tr.characterAttributes.size*1.2); tr.characterAttributes.autoLeading=false; tr.characterAttributes.leading=Math.max(1,l-2);";
            else if ([cmd isEqualToString:@"tracking_up"]) typoOp = @"var t=tr.characterAttributes.tracking||0; tr.characterAttributes.tracking=t+20;";
            else if ([cmd isEqualToString:@"tracking_down"]) typoOp = @"var t=tr.characterAttributes.tracking||0; tr.characterAttributes.tracking=t-20;";
            else if ([cmd isEqualToString:@"all_caps"]) typoOp = @"tr.characterAttributes.capitalization=(tr.characterAttributes.capitalization===FontCapsOption.ALLCAPS)?FontCapsOption.NORMAL:FontCapsOption.ALLCAPS;";
            else if ([cmd isEqualToString:@"small_caps"]) typoOp = @"tr.characterAttributes.capitalization=(tr.characterAttributes.capitalization===FontCapsOption.SMALLCAPS)?FontCapsOption.NORMAL:FontCapsOption.SMALLCAPS;";
            else if ([cmd isEqualToString:@"superscript"]) typoOp = @"tr.characterAttributes.baselinePosition=(tr.characterAttributes.baselinePosition===FontBaselinePosition.SUPERSCRIPT)?FontBaselinePosition.NORMALPOSITION:FontBaselinePosition.SUPERSCRIPT;";
            else if ([cmd isEqualToString:@"subscript"]) typoOp = @"tr.characterAttributes.baselinePosition=(tr.characterAttributes.baselinePosition===FontBaselinePosition.SUBSCRIPT)?FontBaselinePosition.NORMALPOSITION:FontBaselinePosition.SUBSCRIPT;";
            else if ([cmd isEqualToString:@"align_left"] || [cmd isEqualToString:@"para_align_left"]) typoOp = @"tr.paragraphAttributes.justification=Justification.LEFT;";
            else if ([cmd isEqualToString:@"align_center"] || [cmd isEqualToString:@"para_align_center"]) typoOp = @"tr.paragraphAttributes.justification=Justification.CENTER;";
            else if ([cmd isEqualToString:@"align_right"] || [cmd isEqualToString:@"para_align_right"]) typoOp = @"tr.paragraphAttributes.justification=Justification.RIGHT;";
            else if ([cmd isEqualToString:@"justify_left"]) typoOp = @"tr.paragraphAttributes.justification=Justification.LEFTJUSTIFIED;";
            else if ([cmd isEqualToString:@"justify_center"]) typoOp = @"tr.paragraphAttributes.justification=Justification.CENTERJUSTIFIED;";
            else if ([cmd isEqualToString:@"justify_right"]) typoOp = @"tr.paragraphAttributes.justification=Justification.RIGHTJUSTIFIED;";
            else if ([cmd isEqualToString:@"justify_all"]) typoOp = @"tr.paragraphAttributes.justification=Justification.FULLJUSTIFY;";
            else if ([cmd isEqualToString:@"area_align_top"]) typoOp = @"if(it.textPath&&it.textPath.verticalAlignment!==undefined) it.textPath.verticalAlignment=VerticalAlignment.TOP;";
            else if ([cmd isEqualToString:@"area_align_center"]) typoOp = @"if(it.textPath&&it.textPath.verticalAlignment!==undefined) it.textPath.verticalAlignment=VerticalAlignment.CENTER;";
            else if ([cmd isEqualToString:@"area_align_bottom"]) typoOp = @"if(it.textPath&&it.textPath.verticalAlignment!==undefined) it.textPath.verticalAlignment=VerticalAlignment.BOTTOM;";
            else if ([cmd isEqualToString:@"area_align_justify"]) typoOp = @"if(it.textPath&&it.textPath.verticalAlignment!==undefined) it.textPath.verticalAlignment=VerticalAlignment.JUSTIFY;";
            else if ([cmd isEqualToString:@"bullets_bullet"]) typoOp = @"var lines=it.contents.split('\\r');if(lines.length===1&&it.contents.indexOf('\\n')!==-1)lines=it.contents.split('\\n');for(var j=0;j<lines.length;j++){var raw=lines[j].replace(/^(\\d+\\.\\s*|[a-z]\\.\\s*|•\\s*)/i,'');lines[j]='• '+raw;}it.contents=lines.join('\\r');";
            else if ([cmd isEqualToString:@"bullets_number"]) typoOp = @"var lines=it.contents.split('\\r');if(lines.length===1&&it.contents.indexOf('\\n')!==-1)lines=it.contents.split('\\n');for(var j=0;j<lines.length;j++){var raw=lines[j].replace(/^(\\d+\\.\\s*|[a-z]\\.\\s*|•\\s*)/i,'');lines[j]=(j+1)+'. '+raw;}it.contents=lines.join('\\r');";
            else if ([cmd isEqualToString:@"bullets_alpha"]) typoOp = @"var lines=it.contents.split('\\r');if(lines.length===1&&it.contents.indexOf('\\n')!==-1)lines=it.contents.split('\\n');var abc='abcdefghijklmnopqrstuvwxyz';for(var j=0;j<lines.length;j++){var raw=lines[j].replace(/^(\\d+\\.\\s*|[a-z]\\.\\s*|•\\s*)/i,'');lines[j]=abc[j%26]+'. '+raw;}it.contents=lines.join('\\r');";
            else if ([cmd isEqualToString:@"bullets_none"]) typoOp = @"var lines=it.contents.split('\\r');if(lines.length===1&&it.contents.indexOf('\\n')!==-1)lines=it.contents.split('\\n');for(var j=0;j<lines.length;j++){var raw=lines[j].replace(/^(\\d+\\.\\s*|[a-z]\\.\\s*|•\\s*)/i,'');lines[j]=raw;}it.contents=lines.join('\\r');";
            else if ([cmd isEqualToString:@"toggle_hyphenation"]) typoOp = @"tr.paragraphAttributes.hyphenation=!tr.paragraphAttributes.hyphenation;";
            
            if (typoOp) {
                js = [NSString stringWithFormat:
                    @"if (app.documents.length === 0) return 'NO_DOC';\n"
                    @"if (app.selection.length === 0) return 'NO_SEL';\n"
                    @"function applyText(it){\n"
                    @"  if (!it) return;\n"
                    @"  if (it.typename === 'TextRange') { try { var tr = it; %@ } catch(e){} }\n"
                    @"  else if (it.typename === 'TextFrame') { try { var tr = it.textRange || (it.story ? it.story.textRange : null); if (tr) { %@ } } catch(e){} }\n"
                    @"  else if (it.typename === 'GroupItem' && it.pageItems) { for(var g=0; g<it.pageItems.length; g++) applyText(it.pageItems[g]); }\n"
                    @"}\n"
                    @"for (var i=0; i<app.selection.length; i++) applyText(app.selection[i]);\n"
                    @"app.redraw();\n"
                    @"return 'OK';", typoOp, typoOp];
            } else if ([cmd isEqualToString:@"get_recent_colors"] || [cmd isEqualToString:@"extract_colors"] || [cmd isEqualToString:@"get_swatches"]) {
                [self fetchAndBroadcastIllustratorColors];
                return;
            } else {
                js = [NSString stringWithFormat:@"try { app.executeMenuCommand('%@'); app.redraw(); return 'OK'; } catch(e) { return 'ERR:' + e.message; }", cmd];
            }
        }
        
        NSString *res = [self runIllustratorJSSync:js];
        NSLog(@"[MacTouchBar] ✒️ Illustrator command result: %@", res);
        
        if ([res isEqualToString:@"NO_DOC"]) {
            [self broadcastToast:@"⚠️ Nenhum documento aberto no Illustrator"];
        } else if ([res isEqualToString:@"NO_SEL"]) {
            [self broadcastToast:@"⚠️ Selecione um objeto no Illustrator"];
        } else if ([res isEqualToString:@"SAVED"]) {
            [self broadcastToast:@"💾 Documento salvo com sucesso!"];
        } else if ([res isEqualToString:@"GROUPED"]) {
            [self broadcastToast:@"📦 Objetos agrupados (⌘G)"];
        } else if ([res isEqualToString:@"UNGROUPED"]) {
            [self broadcastToast:@"🔓 Objetos desagrupados (⌘⇧G)"];
        }
    });
}

- (void)fetchAndBroadcastIllustratorColors {
    if (![self isIllustratorRunning]) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *js = @"var res = []; try { var _prevLvl = app.userInteractionLevel; app.userInteractionLevel = UserInteractionLevel.DONTDISPLAYALERTS; function contains(arr, val) { for (var i = 0; i < arr.length; i++) { if (arr[i] === val) return true; } return false; } function hexVal(n) { var v = Math.min(255, Math.max(0, Math.round(n))); var s = v.toString(16).toUpperCase(); return s.length < 2 ? '0' + s : s; } function parseColor(c) { if (!c) return null; if (c.typename === 'RGBColor') { return '#' + hexVal(c.red) + hexVal(c.green) + hexVal(c.blue); } else if (c.typename === 'CMYKColor') { var k = c.black / 100.0; var r = 255 * (1.0 - c.cyan / 100.0) * (1.0 - k); var g = 255 * (1.0 - c.magenta / 100.0) * (1.0 - k); var b = 255 * (1.0 - c.yellow / 100.0) * (1.0 - k); return '#' + hexVal(r) + hexVal(g) + hexVal(b); } else if (c.typename === 'GrayColor') { var gr = 255 * (1.0 - c.gray / 100.0); return '#' + hexVal(gr) + hexVal(gr) + hexVal(gr); } else if (c.typename === 'SpotColor' && c.spot) { return parseColor(c.spot.color); } return null; } function addHex(h) { if (h && !contains(res, h) && res.length < 20) { res.push(h); } } function processItem(item) { if (!item) return; try { if (item.filled && item.fillColor) addHex(parseColor(item.fillColor)); if (item.stroked && item.strokeColor) addHex(parseColor(item.strokeColor)); if (item.typename === 'TextFrame' && item.textRange && item.textRange.characterAttributes) { addHex(parseColor(item.textRange.characterAttributes.fillColor)); addHex(parseColor(item.textRange.characterAttributes.strokeColor)); } else if (item.typename === 'GroupItem' && item.pageItems) { for (var g = 0; g < item.pageItems.length && res.length < 20; g++) { processItem(item.pageItems[g]); } } } catch(e){} } if (app.documents.length > 0) { var doc = app.activeDocument; for (var i = 0; i < app.selection.length && res.length < 20; i++) { processItem(app.selection[i]); } for (var p = 0; p < doc.pathItems.length && res.length < 20; p++) { processItem(doc.pathItems[p]); } for (var t = 0; t < doc.textFrames.length && res.length < 20; t++) { processItem(doc.textFrames[t]); } } app.userInteractionLevel = _prevLvl; } catch(e) {} res.join(',');";
        
        NSString *escaped = [js stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
        escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        NSString *osa = [NSString stringWithFormat:
            @"tell application \"Adobe Illustrator\"\n"
            @"try\n"
            @"return do javascript \"%@\"\n"
            @"on error\n"
            @"return \"\"\n"
            @"end try\n"
            @"end tell", escaped];
        
        NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:osa];
        NSDictionary *err = nil;
        NSAppleEventDescriptor *desc = [appleScript executeAndReturnError:&err];
        NSString *outStr = [desc stringValue];
        if (!outStr || outStr.length == 0) {
            outStr = [self runScript:osa];
        }
        
        if (outStr.length > 0) {
            NSArray *hexList = [outStr componentsSeparatedByString:@","];
            NSMutableArray *cleaned = [NSMutableArray array];
            for (NSString *h in hexList) {
                NSString *trim = [h stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trim.length >= 4) {
                    if (![trim hasPrefix:@"#"]) trim = [@"#" stringByAppendingString:trim];
                    [cleaned addObject:trim];
                }
            }
            if (cleaned.count > 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self broadcastIllustratorColors:cleaned];
                });
            }
        }
    });
}

- (void)sendInitialStateToSocket:(int)sock {
    @try {
        NSString *appName = [[NSWorkspace sharedWorkspace] frontmostApplication].localizedName ?: @"Finder";
        NSString *volStr = [self runScript:@"output volume of (get volume settings)"];
        int volume = [volStr intValue];
        NSString *muteStr = [self runScript:@"output muted of (get volume settings)"];
        BOOL isMuted = [muteStr containsString:@"true"];
        
        NSString *wp = getWallpaperBase64();
        if (wp.length > 50) self.lastWallpaperB64 = wp;
        
        NSMutableArray *runningAppNames = [NSMutableArray array];
        for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
            if (app.localizedName) [runningAppNames addObject:app.localizedName];
            if (app.bundleIdentifier) [runningAppNames addObject:app.bundleIdentifier];
            if (app.bundleURL.path) [runningAppNames addObject:app.bundleURL.path];
        }
        
        NSDictionary *status = @{
            @"type": @"status_update",
            @"mac_name": [[NSHost currentHost] localizedName] ?: @"Hackintosh",
            @"frontmost_app": appName,
            @"running_apps": runningAppNames,
            @"volume": @(volume),
            @"is_muted": @(isMuted),
            @"brightness": @(75),
            @"battery": getBatteryInfoDict() ?: @{},
            @"airpods": getAirPodsInfoDict() ?: @{},
            @"media": getMacMediaInfoFull() ?: @{},
            @"wallpaperBase64": wp ?: @""
        };
        
        NSError *err = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:status options:0 error:&err];
        if (data && !err) [self sendWebSocketFrame:data toSocket:sock];
        
        NSArray *buttonsDict = [[DeckManager shared] toDictionaryArray];
        NSDictionary *deckMsg = @{
            @"type": @"deck_config_update",
            @"buttons": buttonsDict ?: @[]
        };
        NSData *deckData = [NSJSONSerialization dataWithJSONObject:deckMsg options:0 error:&err];
        if (deckData && !err) [self sendWebSocketFrame:deckData toSocket:sock];
        
        if (wp.length > 50) {
            NSDictionary *wpMsg = @{
                @"type": @"wallpaper_update",
                @"wallpaperBase64": wp
            };
            NSData *wpData = [NSJSONSerialization dataWithJSONObject:wpMsg options:0 error:&err];
            if (wpData && !err) [self sendWebSocketFrame:wpData toSocket:sock];
        }
    } @catch (NSException *e) {
        NSLog(@"[MacTouchBar] sendInitialStateToSocket exception caught: %@", e);
    }
}

- (void)sendWebSocketFrame:(NSData *)payload toSocket:(int)sock {
    if (sock < 0 || payload == nil) return;
    
    NSMutableData *frame = [NSMutableData data];
    uint8_t b1 = 0x81;
    [frame appendBytes:&b1 length:1];
    
    NSUInteger len = payload.length;
    if (len <= 125) {
        uint8_t b2 = (uint8_t)len;
        [frame appendBytes:&b2 length:1];
    } else if (len <= 65535) {
        uint8_t b2 = 126;
        [frame appendBytes:&b2 length:1];
        uint16_t ext = htons((uint16_t)len);
        [frame appendBytes:&ext length:2];
    } else {
        uint8_t b2 = 127;
        [frame appendBytes:&b2 length:1];
        uint64_t ext = CFSwapInt64HostToBig((uint64_t)len);
        [frame appendBytes:&ext length:8];
    }
    
    [frame appendData:payload];
    @synchronized (self) {
        writeFull(sock, frame.bytes, frame.length);
    }
}

- (NSString *)runScript:(NSString *)script {
    if (!script || script.length == 0) return @"";
    @try {
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/osascript";
        task.arguments = @[@"-e", script];
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        task.standardError = [NSPipe pipe];
        [task launch];
        [task waitUntilExit];
        
        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        NSString *outStr = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return outStr ?: @"";
    } @catch (NSException *e) {
        return @"";
    }
}

- (void)insertText:(NSString *)text {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:text forType:NSPasteboardTypeString];
    [self simulateHotkey:@"v" modifiers:@[@"command"]];
}

- (void)simulateKey:(CGKeyCode)keyCode {
    CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef down = CGEventCreateKeyboardEvent(src, keyCode, true);
    CGEventRef up = CGEventCreateKeyboardEvent(src, keyCode, false);
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    if (down) CFRelease(down);
    if (up) CFRelease(up);
    if (src) CFRelease(src);
}

- (void)simulateHotkey:(NSString *)key modifiers:(NSArray *)modifiers {
    CGEventFlags flags = 0;
    for (NSString *m in modifiers) {
        NSString *lm = m.lowercaseString;
        if ([lm isEqualToString:@"command"] || [lm isEqualToString:@"cmd"]) flags |= kCGEventFlagMaskCommand;
        if ([lm isEqualToString:@"option"] || [lm isEqualToString:@"alt"]) flags |= kCGEventFlagMaskAlternate;
        if ([lm isEqualToString:@"control"] || [lm isEqualToString:@"ctrl"]) flags |= kCGEventFlagMaskControl;
        if ([lm isEqualToString:@"shift"]) flags |= kCGEventFlagMaskShift;
    }
    
    CGKeyCode kc = [self keyCodeFromString:key];
    CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef down = CGEventCreateKeyboardEvent(src, kc, true);
    CGEventRef up = CGEventCreateKeyboardEvent(src, kc, false);
    CGEventSetFlags(down, flags);
    CGEventSetFlags(up, flags);
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    if (down) CFRelease(down);
    if (up) CFRelease(up);
    if (src) CFRelease(src);
}

- (CGKeyCode)keyCodeFromString:(NSString *)s {
    NSString *k = s.lowercaseString;
    if ([k isEqualToString:@"a"]) return kVK_ANSI_A;
    if ([k isEqualToString:@"s"]) return kVK_ANSI_S;
    if ([k isEqualToString:@"d"]) return kVK_ANSI_D;
    if ([k isEqualToString:@"f"]) return kVK_ANSI_F;
    if ([k isEqualToString:@"h"]) return kVK_ANSI_H;
    if ([k isEqualToString:@"g"]) return kVK_ANSI_G;
    if ([k isEqualToString:@"z"]) return kVK_ANSI_Z;
    if ([k isEqualToString:@"x"]) return kVK_ANSI_X;
    if ([k isEqualToString:@"c"]) return kVK_ANSI_C;
    if ([k isEqualToString:@"v"]) return kVK_ANSI_V;
    if ([k isEqualToString:@"b"]) return kVK_ANSI_B;
    if ([k isEqualToString:@"q"]) return kVK_ANSI_Q;
    if ([k isEqualToString:@"w"]) return kVK_ANSI_W;
    if ([k isEqualToString:@"e"]) return kVK_ANSI_E;
    if ([k isEqualToString:@"r"]) return kVK_ANSI_R;
    if ([k isEqualToString:@"y"]) return kVK_ANSI_Y;
    if ([k isEqualToString:@"t"]) return kVK_ANSI_T;
    if ([k isEqualToString:@"1"]) return kVK_ANSI_1;
    if ([k isEqualToString:@"2"]) return kVK_ANSI_2;
    if ([k isEqualToString:@"3"]) return kVK_ANSI_3;
    if ([k isEqualToString:@"4"]) return kVK_ANSI_4;
    if ([k isEqualToString:@"5"]) return kVK_ANSI_5;
    if ([k isEqualToString:@"6"]) return kVK_ANSI_6;
    if ([k isEqualToString:@"7"]) return kVK_ANSI_7;
    if ([k isEqualToString:@"8"]) return kVK_ANSI_8;
    if ([k isEqualToString:@"9"]) return kVK_ANSI_9;
    if ([k isEqualToString:@"0"]) return kVK_ANSI_0;
    if ([k isEqualToString:@"o"]) return kVK_ANSI_O;
    if ([k isEqualToString:@"u"]) return kVK_ANSI_U;
    if ([k isEqualToString:@"i"]) return kVK_ANSI_I;
    if ([k isEqualToString:@"p"]) return kVK_ANSI_P;
    if ([k isEqualToString:@"l"]) return kVK_ANSI_L;
    if ([k isEqualToString:@"j"]) return kVK_ANSI_J;
    if ([k isEqualToString:@"k"]) return kVK_ANSI_K;
    if ([k isEqualToString:@"m"]) return kVK_ANSI_M;
    if ([k isEqualToString:@"n"]) return kVK_ANSI_N;
    if ([k isEqualToString:@"space"]) return kVK_Space;
    if ([k isEqualToString:@"delete"] || [k isEqualToString:@"backspace"]) return kVK_Delete;
    if ([k isEqualToString:@"tab"]) return kVK_Tab;
    if ([k isEqualToString:@"escape"] || [k isEqualToString:@"esc"]) return kVK_Escape;
    if ([k isEqualToString:@"return"] || [k isEqualToString:@"enter"]) return kVK_Return;
    if ([k isEqualToString:@"f1"]) return kVK_F1;
    if ([k isEqualToString:@"f2"]) return kVK_F2;
    if ([k isEqualToString:@"f3"]) return kVK_F3;
    if ([k isEqualToString:@"f4"]) return kVK_F4;
    if ([k isEqualToString:@"f5"]) return kVK_F5;
    if ([k isEqualToString:@"f6"]) return kVK_F6;
    if ([k isEqualToString:@"f7"]) return kVK_F7;
    if ([k isEqualToString:@"f8"]) return kVK_F8;
    if ([k isEqualToString:@"f9"]) return kVK_F9;
    if ([k isEqualToString:@"f10"]) return kVK_F10;
    if ([k isEqualToString:@"f11"]) return kVK_F11;
    if ([k isEqualToString:@"f12"]) return kVK_F12;
    if ([k isEqualToString:@"`"]) return kVK_ANSI_Grave;
    if ([k isEqualToString:@"["]) return kVK_ANSI_LeftBracket;
    if ([k isEqualToString:@"]"]) return kVK_ANSI_RightBracket;
    if ([k isEqualToString:@"/"]) return kVK_ANSI_Slash;
    if ([k isEqualToString:@"\\"]) return kVK_ANSI_Backslash;
    if ([k isEqualToString:@";"]) return kVK_ANSI_Semicolon;
    if ([k isEqualToString:@"'"]) return kVK_ANSI_Quote;
    if ([k isEqualToString:@","]) return kVK_ANSI_Comma;
    if ([k isEqualToString:@"."]) return kVK_ANSI_Period;
    if ([k isEqualToString:@"="] || [k isEqualToString:@"+"]) return kVK_ANSI_Equal;
    if ([k isEqualToString:@"-"] || [k isEqualToString:@"_"]) return kVK_ANSI_Minus;
    if ([k isEqualToString:@"up"] || [k isEqualToString:@"uparrow"]) return kVK_UpArrow;
    if ([k isEqualToString:@"down"] || [k isEqualToString:@"downarrow"]) return kVK_DownArrow;
    if ([k isEqualToString:@"left"] || [k isEqualToString:@"leftarrow"]) return kVK_LeftArrow;
    if ([k isEqualToString:@"right"] || [k isEqualToString:@"rightarrow"]) return kVK_RightArrow;
    return 0;
}

- (void)stop {
    [[MacMicEngine shared] stop];
    [self.netService stop];
    if (g_serverSocket >= 0) {
        close(g_serverSocket);
        g_serverSocket = -1;
    }
    @synchronized (g_clientSockets) {
        for (NSNumber *s in g_clientSockets) {
            close(s.intValue);
        }
        [g_clientSockets removeAllObjects];
    }
}
@end

// MARK: - Advanced Configurator Window Controller
@interface ConfigWindowController : NSWindowController
@property (nonatomic, strong) NSMutableArray<NSButton *> *gridButtons;
@property (nonatomic, assign) NSInteger selectedIndex;

// UI Controls
@property (nonatomic, strong) NSTabView *tabView;
@property (nonatomic, strong) NSTextField *labelField;
@property (nonatomic, strong) NSImageView *iconPreviewView;
@property (nonatomic, strong) NSPopUpButton *colorPopup;

// Tab 1: Apps
@property (nonatomic, strong) NSPopUpButton *installedAppsPopup;
@property (nonatomic, strong) NSArray<NSDictionary *> *installedApps;

// Tab 2: Hotkey Builder
@property (nonatomic, strong) NSButton *chkCmd;
@property (nonatomic, strong) NSButton *chkOpt;
@property (nonatomic, strong) NSButton *chkCtrl;
@property (nonatomic, strong) NSButton *chkShift;
@property (nonatomic, strong) NSPopUpButton *keyPickerPopup;
@property (nonatomic, strong) NSTextField *emojiField;

// Tab 3: System Actions
@property (nonatomic, strong) NSPopUpButton *systemActionsPopup;

// Tab 4: Terminal Script
@property (nonatomic, strong) NSTextField *terminalCmdField;

// Tab 5: Sounds
@property (nonatomic, strong) NSPopUpButton *soundsPopup;

- (void)refreshGrid;
@end

@implementation ConfigWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(150, 150, 840, 640)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"MacDeck Studio (Configurador 2x6)";
    [window center];
    
    self = [super initWithWindow:window];
    if (self) {
        self.selectedIndex = 0;
        self.gridButtons = [NSMutableArray array];
        self.installedApps = getInstalledAppsList();
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    NSView *content = self.window.contentView;
    content.wantsLayer = YES;
    
    // Header & Presets Bar
    NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 595, 400, 30)];
    titleLabel.stringValue = @"Deck 2x6 • Clique em um slot para editar:";
    titleLabel.font = [NSFont boldSystemFontOfSize:15];
    titleLabel.editable = NO;
    titleLabel.bordered = NO;
    titleLabel.backgroundColor = [NSColor clearColor];
    [content addSubview:titleLabel];
    
    // Quick Presets
    NSTextField *lblPreset = [self makeLabel:@"Modelos:" frame:NSMakeRect(400, 600, 60, 20)];
    [content addSubview:lblPreset];
    
    NSPopUpButton *presetPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(460, 597, 240, 26) pullsDown:NO];
    [presetPopup addItemsWithTitles:@[@"Carregar Modelo...", @"🌟 Meus Apps (Chrome, Adobe, Figma...)", @"💻 Desenvolvedor (Coder)"]];
    presetPopup.target = self;
    presetPopup.action = @selector(presetChanged:);
    [content addSubview:presetPopup];
    
    // 2x6 Grid Area
    NSView *gridBox = [[NSView alloc] initWithFrame:NSMakeRect(20, 355, 800, 230)];
    gridBox.wantsLayer = YES;
    gridBox.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.12 alpha:1.0].CGColor;
    gridBox.layer.cornerRadius = 12;
    [content addSubview:gridBox];
    
    CGFloat btnW = 118;
    CGFloat btnH = 95;
    CGFloat gapX = 12;
    CGFloat gapY = 12;
    CGFloat startX = 14;
    
    for (int i = 0; i < 12; i++) {
        int row = i / 6;
        int col = i % 6;
        
        CGFloat y = (row == 0) ? (115 + gapY / 2) : 12;
        CGFloat x = startX + col * (btnW + gapX);
        
        NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, btnW, btnH)];
        btn.bezelStyle = NSBezelStyleRegularSquare;
        btn.tag = i;
        btn.target = self;
        btn.action = @selector(gridButtonClicked:);
        btn.imagePosition = NSImageAbove;
        btn.wantsLayer = YES;
        btn.layer.cornerRadius = 10;
        [gridBox addSubview:btn];
        [self.gridButtons addObject:btn];
    }
    
    // Form & Tab Area
    NSView *formBox = [[NSView alloc] initWithFrame:NSMakeRect(20, 15, 800, 330)];
    formBox.wantsLayer = YES;
    formBox.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.16 alpha:1.0].CGColor;
    formBox.layer.cornerRadius = 12;
    [content addSubview:formBox];
    
    // Live Button Preview on Left
    self.iconPreviewView = [[NSImageView alloc] initWithFrame:NSMakeRect(20, 210, 76, 76)];
    self.iconPreviewView.wantsLayer = YES;
    self.iconPreviewView.layer.cornerRadius = 14;
    self.iconPreviewView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [formBox addSubview:self.iconPreviewView];
    
    NSTextField *lbl1 = [self makeLabel:@"Nome do Botão:" frame:NSMakeRect(110, 260, 110, 20)];
    [formBox addSubview:lbl1];
    self.labelField = [[NSTextField alloc] initWithFrame:NSMakeRect(220, 258, 240, 24)];
    self.labelField.font = [NSFont systemFontOfSize:13];
    [formBox addSubview:self.labelField];
    
    NSTextField *lblColor = [self makeLabel:@"Cor de Fundo:" frame:NSMakeRect(480, 260, 95, 20)];
    [formBox addSubview:lblColor];
    self.colorPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(580, 257, 190, 26) pullsDown:NO];
    [self.colorPopup addItemsWithTitles:@[@"Grafite OLED (#1F1F24)", @"Azul Apple (#007AFF)", @"Roxo (#AF52DE)", @"Verde (#34C759)", @"Laranja (#FF9500)", @"Vermelho (#FF3B30)", @"Índigo (#5856D6)"]];
    [formBox addSubview:self.colorPopup];
    
    // Tab View for Actions
    self.tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(15, 60, 770, 190)];
    
    // Tab 1: Apps do Mac
    NSTabViewItem *tabApps = [[NSTabViewItem alloc] initWithIdentifier:@"apps"];
    tabApps.label = @"Aplicativos";
    NSView *viewApps = [[NSView alloc] initWithFrame:self.tabView.bounds];
    NSTextField *lblAppSelect = [self makeLabel:@"Selecione o app instalado no Mac:" frame:NSMakeRect(15, 115, 240, 20)];
    [viewApps addSubview:lblAppSelect];
    self.installedAppsPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(15, 80, 420, 30) pullsDown:NO];
    [self.installedAppsPopup addItemWithTitle:@"-- Selecione um Aplicativo --"];
    for (NSDictionary *app in self.installedApps) {
        [self.installedAppsPopup addItemWithTitle:app[@"name"]];
    }
    self.installedAppsPopup.target = self;
    self.installedAppsPopup.action = @selector(appSelected:);
    [viewApps addSubview:self.installedAppsPopup];
    tabApps.view = viewApps;
    [self.tabView addTabViewItem:tabApps];
    
    // Tab 2: Atalho de Teclado
    NSTabViewItem *tabHotkey = [[NSTabViewItem alloc] initWithIdentifier:@"hotkey"];
    tabHotkey.label = @"Atalho de Teclado";
    NSView *viewHotkey = [[NSView alloc] initWithFrame:self.tabView.bounds];
    NSTextField *lblMod = [self makeLabel:@"Teclas Modificadoras:" frame:NSMakeRect(15, 115, 150, 20)];
    [viewHotkey addSubview:lblMod];
    
    self.chkCmd = [[NSButton alloc] initWithFrame:NSMakeRect(170, 115, 110, 20)];
    self.chkCmd.buttonType = NSButtonTypeSwitch;
    self.chkCmd.title = @"⌘ Command";
    [viewHotkey addSubview:self.chkCmd];
    
    self.chkOpt = [[NSButton alloc] initWithFrame:NSMakeRect(290, 115, 110, 20)];
    self.chkOpt.buttonType = NSButtonTypeSwitch;
    self.chkOpt.title = @"⌥ Option";
    [viewHotkey addSubview:self.chkOpt];
    
    self.chkCtrl = [[NSButton alloc] initWithFrame:NSMakeRect(400, 115, 110, 20)];
    self.chkCtrl.buttonType = NSButtonTypeSwitch;
    self.chkCtrl.title = @"⌃ Control";
    [viewHotkey addSubview:self.chkCtrl];
    
    self.chkShift = [[NSButton alloc] initWithFrame:NSMakeRect(510, 115, 110, 20)];
    self.chkShift.buttonType = NSButtonTypeSwitch;
    self.chkShift.title = @"⇧ Shift";
    [viewHotkey addSubview:self.chkShift];
    
    NSTextField *lblKey = [self makeLabel:@"Tecla Principal:" frame:NSMakeRect(15, 75, 120, 20)];
    [viewHotkey addSubview:lblKey];
    self.keyPickerPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(140, 72, 140, 26) pullsDown:NO];
    [self.keyPickerPopup addItemsWithTitles:@[@"s", @"p", @"z", @"c", @"v", @"x", @"a", @"f", @"t", @"w", @"q", @"r", @"n", @"o", @"space", @"return", @"escape", @"tab", @"delete", @"f1", @"f2", @"f3", @"f4", @"f5", @"f6", @"f7", @"f8", @"f9", @"f10", @"f11", @"f12", @"`", @"[", @"]"]];
    [viewHotkey addSubview:self.keyPickerPopup];
    
    NSTextField *lblEmoji = [self makeLabel:@"Ícone / Emoji:" frame:NSMakeRect(310, 75, 100, 20)];
    [viewHotkey addSubview:lblEmoji];
    self.emojiField = [[NSTextField alloc] initWithFrame:NSMakeRect(410, 73, 80, 24)];
    self.emojiField.stringValue = @"⌨️";
    [viewHotkey addSubview:self.emojiField];
    tabHotkey.view = viewHotkey;
    [self.tabView addTabViewItem:tabHotkey];
    
    // Tab 3: Ações do Sistema macOS
    NSTabViewItem *tabSys = [[NSTabViewItem alloc] initWithIdentifier:@"system"];
    tabSys.label = @"Ações do Sistema";
    NSView *viewSys = [[NSView alloc] initWithFrame:self.tabView.bounds];
    NSTextField *lblSys = [self makeLabel:@"Escolha uma ação nativa do macOS:" frame:NSMakeRect(15, 115, 260, 20)];
    [viewSys addSubview:lblSys];
    
    self.systemActionsPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(15, 80, 480, 28) pullsDown:NO];
    [self.systemActionsPopup addItemsWithTitles:@[
        @"📸 Captura de Tela (Área com Seleção)",
        @"🖥️ Captura de Tela (Tela Inteira)",
        @"🎬 Gravação de Tela (QuickTime/macOS)",
        @"🔍 Spotlight Search",
        @"🪟 Mission Control",
        @"🚀 Launchpad",
        @"🔒 Bloquear Tela do Mac",
        @"💤 Colocar Mac para Dormir (Sleep)",
        @"🔇 Alternar Mudo",
        @"🔊 Aumentar Volume (+10%)",
        @"🔈 Diminuir Volume (-10%)",
        @"☀️ Aumentar Brilho",
        @"🌘 Diminuir Brilho",
        @"📶 Alternar Wi-Fi (HeliPort / Nativo)",
        @"🔵 Alternar Bluetooth",
        @"📱 Espelhamento de Tela (AirPlay)",
        @"📦 Criar Nova Pasta no Finder",
        @"🗑️ Esvaziar Lixeira"
    ]];
    [viewSys addSubview:self.systemActionsPopup];
    tabSys.view = viewSys;
    [self.tabView addTabViewItem:tabSys];
    
    // Tab 4: Terminal / Shell Script
    NSTabViewItem *tabTerm = [[NSTabViewItem alloc] initWithIdentifier:@"terminal"];
    tabTerm.label = @"Terminal / Script";
    NSView *viewTerm = [[NSView alloc] initWithFrame:self.tabView.bounds];
    NSTextField *lblTerm = [self makeLabel:@"Comando a ser digitado/executado no Terminal:" frame:NSMakeRect(15, 115, 360, 20)];
    [viewTerm addSubview:lblTerm];
    self.terminalCmdField = [[NSTextField alloc] initWithFrame:NSMakeRect(15, 80, 520, 26)];
    self.terminalCmdField.placeholderString = @"Ex: git status\\n ou npm run dev\\n ou clear\\n";
    [viewTerm addSubview:self.terminalCmdField];
    tabTerm.view = viewTerm;
    [self.tabView addTabViewItem:tabTerm];
    
    // Tab 5: Efeitos Sonoros
    NSTabViewItem *tabSound = [[NSTabViewItem alloc] initWithIdentifier:@"sound"];
    tabSound.label = @"Efeitos Sonoros";
    NSView *viewSound = [[NSView alloc] initWithFrame:self.tabView.bounds];
    NSTextField *lblSound = [self makeLabel:@"Som do sistema a ser reproduzido:" frame:NSMakeRect(15, 115, 300, 20)];
    [viewSound addSubview:lblSound];
    self.soundsPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(15, 80, 300, 28) pullsDown:NO];
    [self.soundsPopup addItemsWithTitles:@[@"Pop", @"Ping", @"Funk", @"Basso", @"Hero", @"Frog", @"Bottle", @"Submarine", @"Tink", @"Sosumi"]];
    [viewSound addSubview:self.soundsPopup];
    tabSound.view = viewSound;
    [self.tabView addTabViewItem:tabSound];
    
    [formBox addSubview:self.tabView];
    
    // Save & Sync Button
    NSButton *applyBtn = [[NSButton alloc] initWithFrame:NSMakeRect(15, 12, 770, 42)];
    applyBtn.title = @"Salvar e Sincronizar";
    applyBtn.font = [NSFont boldSystemFontOfSize:14];
    applyBtn.bezelStyle = NSBezelStylePush;
    applyBtn.keyEquivalent = @"\r";
    applyBtn.target = self;
    applyBtn.action = @selector(saveAndSync:);
    [formBox addSubview:applyBtn];
    
    [self refreshGrid];
    [self loadSelectedButtonToForm];
}

- (NSTextField *)makeLabel:(NSString *)text frame:(NSRect)frame {
    NSTextField *lbl = [[NSTextField alloc] initWithFrame:frame];
    lbl.stringValue = text;
    lbl.font = [NSFont systemFontOfSize:12];
    lbl.editable = NO;
    lbl.bordered = NO;
    lbl.backgroundColor = [NSColor clearColor];
    return lbl;
}

- (void)gridButtonClicked:(NSButton *)sender {
    self.selectedIndex = sender.tag;
    [self loadSelectedButtonToForm];
    [self refreshGrid];
}

- (void)presetChanged:(NSPopUpButton *)sender {
    if (sender.indexOfSelectedItem == 1) {
        [[DeckManager shared] applyUserAppsLayout];
    } else if (sender.indexOfSelectedItem == 2) {
        [[DeckManager shared] applyPreset:@"developer"];
    }
    [self refreshGrid];
    [self loadSelectedButtonToForm];
    if (g_server) [g_server broadcastDeckConfig];
}

- (void)appSelected:(NSPopUpButton *)sender {
    if (sender.indexOfSelectedItem > 0) {
        NSInteger appIdx = sender.indexOfSelectedItem - 1;
        if (appIdx < self.installedApps.count) {
            NSDictionary *app = self.installedApps[appIdx];
            self.labelField.stringValue = app[@"name"];
            NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:app[@"path"]];
            self.iconPreviewView.image = icon;
        }
    }
}

- (void)loadSelectedButtonToForm {
    NSArray *btns = [DeckManager shared].buttons;
    if (self.selectedIndex < btns.count) {
        DeckButtonConfig *cfg = btns[self.selectedIndex];
        self.labelField.stringValue = cfg.label;
        
        if ([cfg.colorHex isEqualToString:@"#007AFF"]) [self.colorPopup selectItemAtIndex:1];
        else if ([cfg.colorHex isEqualToString:@"#AF52DE"]) [self.colorPopup selectItemAtIndex:2];
        else if ([cfg.colorHex isEqualToString:@"#34C759"] || [cfg.colorHex isEqualToString:@"#28A745"]) [self.colorPopup selectItemAtIndex:3];
        else if ([cfg.colorHex isEqualToString:@"#FF9500"] || [cfg.colorHex isEqualToString:@"#FF9A00"]) [self.colorPopup selectItemAtIndex:4];
        else if ([cfg.colorHex isEqualToString:@"#FF3B30"] || [cfg.colorHex isEqualToString:@"#CB3837"]) [self.colorPopup selectItemAtIndex:5];
        else if ([cfg.colorHex isEqualToString:@"#5856D6"] || [cfg.colorHex isEqualToString:@"#A259FF"]) [self.colorPopup selectItemAtIndex:6];
        else [self.colorPopup selectItemAtIndex:0];
        
        if ([cfg.actionType isEqualToString:@"launch_app"]) {
            [self.tabView selectTabViewItemWithIdentifier:@"apps"];
            NSString *appName = [[cfg.payload lastPathComponent] stringByDeletingPathExtension];
            [self.installedAppsPopup selectItemWithTitle:appName.length > 0 ? appName : cfg.payload];
            if (cfg.iconBase64.length > 0) {
                NSData *imgData = [[NSData alloc] initWithBase64EncodedString:cfg.iconBase64 options:0];
                self.iconPreviewView.image = [[NSImage alloc] initWithData:imgData];
            } else {
                self.iconPreviewView.image = [[NSWorkspace sharedWorkspace] iconForFile:[[NSWorkspace sharedWorkspace] fullPathForApplication:cfg.payload] ?: cfg.payload];
            }
        } else if ([cfg.actionType isEqualToString:@"hotkey"]) {
            [self.tabView selectTabViewItemWithIdentifier:@"hotkey"];
            self.chkCmd.state = [cfg.payload containsString:@"cmd"] ? NSControlStateValueOn : NSControlStateValueOff;
            self.chkOpt.state = [cfg.payload containsString:@"opt"] ? NSControlStateValueOn : NSControlStateValueOff;
            self.chkCtrl.state = [cfg.payload containsString:@"ctrl"] ? NSControlStateValueOn : NSControlStateValueOff;
            self.chkShift.state = [cfg.payload containsString:@"shift"] ? NSControlStateValueOn : NSControlStateValueOff;
            self.emojiField.stringValue = cfg.icon;
            self.iconPreviewView.image = nil;
        } else if ([cfg.actionType isEqualToString:@"system"]) {
            [self.tabView selectTabViewItemWithIdentifier:@"system"];
            self.iconPreviewView.image = nil;
        } else if ([cfg.actionType isEqualToString:@"terminal_cmd"]) {
            [self.tabView selectTabViewItemWithIdentifier:@"terminal"];
            self.terminalCmdField.stringValue = cfg.payload;
            self.iconPreviewView.image = nil;
        } else if ([cfg.actionType isEqualToString:@"sound"]) {
            [self.tabView selectTabViewItemWithIdentifier:@"sound"];
            [self.soundsPopup selectItemWithTitle:cfg.payload];
            self.iconPreviewView.image = nil;
        }
    }
}

- (void)saveAndSync:(id)sender {
    NSArray *btns = [DeckManager shared].buttons;
    if (self.selectedIndex < btns.count) {
        DeckButtonConfig *cfg = btns[self.selectedIndex];
        cfg.label = self.labelField.stringValue;
        
        NSInteger cIdx = self.colorPopup.indexOfSelectedItem;
        if (cIdx == 1) cfg.colorHex = @"#007AFF";
        else if (cIdx == 2) cfg.colorHex = @"#AF52DE";
        else if (cIdx == 3) cfg.colorHex = @"#34C759";
        else if (cIdx == 4) cfg.colorHex = @"#FF9500";
        else if (cIdx == 5) cfg.colorHex = @"#FF3B30";
        else if (cIdx == 6) cfg.colorHex = @"#5856D6";
        else cfg.colorHex = @"#1F1F24";
        
        NSString *tabId = self.tabView.selectedTabViewItem.identifier;
        if ([tabId isEqualToString:@"apps"]) {
            cfg.actionType = @"launch_app";
            NSInteger appIdx = self.installedAppsPopup.indexOfSelectedItem - 1;
            if (appIdx >= 0 && appIdx < self.installedApps.count) {
                cfg.payload = self.installedApps[appIdx][@"path"];
            } else {
                cfg.payload = self.installedAppsPopup.titleOfSelectedItem;
            }
            cfg.icon = @"💻";
            cfg.iconBase64 = getIconBase64ForApp(cfg.payload);
        } else if ([tabId isEqualToString:@"hotkey"]) {
            cfg.actionType = @"hotkey";
            NSMutableArray *mods = [NSMutableArray array];
            if (self.chkCmd.state == NSControlStateValueOn) [mods addObject:@"cmd"];
            if (self.chkOpt.state == NSControlStateValueOn) [mods addObject:@"option"];
            if (self.chkCtrl.state == NSControlStateValueOn) [mods addObject:@"ctrl"];
            if (self.chkShift.state == NSControlStateValueOn) [mods addObject:@"shift"];
            [mods addObject:self.keyPickerPopup.titleOfSelectedItem];
            cfg.payload = [mods componentsJoinedByString:@"+"];
            cfg.icon = self.emojiField.stringValue.length > 0 ? self.emojiField.stringValue : @"⌨️";
            cfg.iconBase64 = @"";
        } else if ([tabId isEqualToString:@"system"]) {
            cfg.actionType = @"system";
            NSInteger sIdx = self.systemActionsPopup.indexOfSelectedItem;
            NSArray *sysCmds = @[
                @"screenshot_interactive", @"screenshot_fullscreen", @"screenshot_recording",
                @"spotlight", @"mission_control", @"launchpad", @"lock_screen", @"sleep_mac",
                @"toggle_mute", @"volume_up", @"volume_down", @"brightness_up", @"brightness_down",
                @"toggle_wifi", @"toggle_bluetooth", @"screen_mirror", @"finder_new_folder", @"empty_trash"
            ];
            cfg.payload = (sIdx < sysCmds.count) ? sysCmds[sIdx] : @"spotlight";
            cfg.icon = @"⚡️";
            cfg.iconBase64 = @"";
        } else if ([tabId isEqualToString:@"terminal"]) {
            cfg.actionType = @"terminal_cmd";
            cfg.payload = self.terminalCmdField.stringValue;
            cfg.icon = @"📟";
            cfg.iconBase64 = @"";
        } else if ([tabId isEqualToString:@"sound"]) {
            cfg.actionType = @"sound";
            cfg.payload = self.soundsPopup.titleOfSelectedItem;
            cfg.icon = @"🔔";
            cfg.iconBase64 = @"";
        }
        
        [[DeckManager shared] saveConfigs];
        [self refreshGrid];
        
        if (g_server) {
            [g_server broadcastDeckConfig];
        }
    }
}

- (void)refreshGrid {
    NSArray *btns = [DeckManager shared].buttons;
    for (int i = 0; i < self.gridButtons.count; i++) {
        NSButton *btn = self.gridButtons[i];
        if (i < btns.count) {
            DeckButtonConfig *cfg = btns[i];
            btn.title = cfg.label;
            
            if (cfg.iconBase64.length > 0) {
                NSData *imgData = [[NSData alloc] initWithBase64EncodedString:cfg.iconBase64 options:0];
                NSImage *img = [[NSImage alloc] initWithData:imgData];
                img.size = NSMakeSize(44, 44);
                btn.image = img;
            } else {
                btn.image = nil;
                btn.title = [NSString stringWithFormat:@"%@\n%@", cfg.icon, cfg.label];
            }
            
            btn.layer.borderWidth = (i == self.selectedIndex) ? 2.5 : 0.8;
            btn.layer.borderColor = (i == self.selectedIndex) ? [NSColor colorWithCalibratedRed:0.0 green:0.48 blue:1.0 alpha:1.0].CGColor : [NSColor colorWithCalibratedWhite:0.3 alpha:1.0].CGColor;
            btn.layer.backgroundColor = (i == self.selectedIndex) ? [NSColor colorWithCalibratedWhite:0.25 alpha:1.0].CGColor : [NSColor colorWithCalibratedWhite:0.18 alpha:1.0].CGColor;
        }
    }
}
@end

// MARK: - App Delegate
@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) TouchBarServer *server;
@property (nonatomic, strong) ConfigWindowController *configWindowController;
@property (nonatomic, strong) NSMenuItem *statusMenuItem;
@property (nonatomic, strong) NSMenuItem *ipMenuItem;
@property (nonatomic, strong) NSMenuItem *clientMenuItem;
@property (nonatomic, strong) NSMenuItem *appMenuItem;
@property (nonatomic, strong) NSMenuItem *virtualMicMenuItem;
@property (nonatomic, strong) NSMenuItem *setDefaultMicMenuItem;
@property (nonatomic, strong) NSMenuItem *launchAtLoginMenuItem;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Set application icon for Dock & App Switcher
    NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"];
    if (!iconPath) {
        iconPath = @"/Volumes/Work/APP TESTE/MacTouchBar.app/Contents/Resources/AppIcon.icns";
    }
    if (iconPath) {
        NSImage *appIcon = [[NSImage alloc] initWithContentsOfFile:iconPath];
        if (appIcon) {
            [NSApp setApplicationIconImage:appIcon];
        }
    }

    // Ensure launch at login is configured
    if (![self isLaunchAtStartupEnabled]) {
        [self setLaunchAtStartupEnabled:YES];
    }
    
    [self setupMenuBar];
    [self startServer];
    [self observeActiveApps];
    
    self.configWindowController = [[ConfigWindowController alloc] init];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    StopAudioDSPEngine();
    [[MacMicEngine shared] stop];
}

- (NSImage *)createStatusBarIcon {
    // High-DPI Apple HIG drawn template TouchBar icon (21pt x 11pt, perfect optical balance for macOS Menu Bar)
    NSSize size = NSMakeSize(21, 11);
    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        // 1. Outer TouchBar chassis/pill
        NSRect frameRect = NSMakeRect(0.5, 0.5, 20.0, 10.0);
        NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:frameRect xRadius:2.2 yRadius:2.2];
        [pill setLineWidth:1.2];
        [[NSColor blackColor] setStroke];
        [pill stroke];
        
        // 2. Esc Key (left rounded capsule)
        NSRect escRect = NSMakeRect(2.2, 2.0, 2.6, 6.0);
        NSBezierPath *escPath = [NSBezierPath bezierPathWithRoundedRect:escRect xRadius:0.8 yRadius:0.8];
        [[NSColor blackColor] setFill];
        [escPath fill];
        
        // 3. Central TouchBar Active Tool Segments
        NSRect seg1Rect = NSMakeRect(6.2, 2.4, 3.8, 5.2);
        NSBezierPath *seg1Path = [NSBezierPath bezierPathWithRoundedRect:seg1Rect xRadius:0.8 yRadius:0.8];
        [seg1Path fill];
        
        NSRect seg2Rect = NSMakeRect(11.0, 2.4, 3.8, 5.2);
        NSBezierPath *seg2Path = [NSBezierPath bezierPathWithRoundedRect:seg2Rect xRadius:0.8 yRadius:0.8];
        [seg2Path fill];
        
        // 4. Right Sensor (Touch ID / Control Strip Pip)
        NSRect sensorRect = NSMakeRect(15.8, 2.4, 2.6, 5.2);
        NSBezierPath *sensorPath = [NSBezierPath bezierPathWithRoundedRect:sensorRect xRadius:0.8 yRadius:0.8];
        [sensorPath fill];
        
        return YES;
    }];
    [image setTemplate:YES];
    return image;
}

- (void)updateVirtualMicMenuState {
    NSString *devName = nil;
    NSString *devUID = GetVirtualAudioDeviceUID(&devName);
    if (devUID) {
        self.virtualMicMenuItem.title = [NSString stringWithFormat:@"Microfone Virtual: Conectado (%@)", devName];
        [self.virtualMicMenuItem setAction:nil];
        [self.virtualMicMenuItem setEnabled:NO];
        [self.setDefaultMicMenuItem setHidden:NO];
    } else {
        self.virtualMicMenuItem.title = @"Instalar Microfone Virtual...";
        [self.virtualMicMenuItem setTarget:self];
        [self.virtualMicMenuItem setAction:@selector(installVirtualAudioDriverAction:)];
        [self.virtualMicMenuItem setEnabled:YES];
        [self.setDefaultMicMenuItem setHidden:YES];
    }
}

- (void)installVirtualAudioDriverAction:(id)sender {
    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"Instalar Microfone Virtual CoreAudio?";
    confirm.informativeText = @"Isso instalará os drivers 'TouchBar Microphone' e 'BlackHole 2ch' diretamente no sistema do macOS (/Library/Audio/Plug-Ins/HAL).\n\nPermite que a voz captada pelo celular funcione como microfone de entrada no Discord, Zoom, Google Meet, OBS, WhatsApp e em qualquer app do Mac sem eco nos alto-falantes.";
    [confirm addButtonWithTitle:@"Instalar Agora"];
    [confirm addButtonWithTitle:@"Cancelar"];
    
    if ([confirm runModal] == NSAlertFirstButtonReturn) {
        NSString *errorStr = nil;
        BOOL success = [VirtualMicManager installVirtualAudioDriverWithError:&errorStr];
        if (success) {
            [self updateVirtualMicMenuState];
            [VirtualMicManager setDefaultInputToVirtualMic];
            
            NSAlert *done = [[NSAlert alloc] init];
            done.messageText = @"Microfone Virtual Instalado!";
            done.informativeText = @"O driver de áudio virtual foi instalado com sucesso!\n\nEle já foi configurado como entrada de áudio padrão do macOS. Você também pode selecioná-lo em 'TouchBar Microphone' ou 'BlackHole 2ch' no Discord, Zoom, OBS, etc.";
            [done addButtonWithTitle:@"OK"];
            [done runModal];
            
            [self.server broadcastStatus:nil];
        } else {
            NSAlert *errAlert = [[NSAlert alloc] init];
            errAlert.messageText = @"Instalação Cancelada ou Falhou";
            errAlert.informativeText = [NSString stringWithFormat:@"Não foi possível concluir a instalação:\n%@", errorStr ?: @"Autorização não concedida."];
            [errAlert addButtonWithTitle:@"OK"];
            [errAlert runModal];
        }
    }
}

- (void)setDefaultMicAction:(id)sender {
    if ([VirtualMicManager setDefaultInputToVirtualMic]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Microfone Padrão Atualizado";
        alert.informativeText = @"O 'TouchBar Microphone' foi configurado com sucesso como a entrada de áudio padrão do macOS.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Aviso";
        alert.informativeText = @"Selecione 'TouchBar Microphone' ou 'BlackHole 2ch' manualmente em Ajustes do Sistema > Som > Entrada.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    }
}

- (void)setupMenuBar {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    
    NSImage *icon = [self createStatusBarIcon];
    if (icon) {
        self.statusItem.button.image = icon;
        self.statusItem.button.imagePosition = NSImageOnly;
        self.statusItem.button.title = @"";
    } else {
        self.statusItem.button.title = @"TouchBar";
    }
    self.statusItem.button.toolTip = @"Mac Touch Bar";
    
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Mac Touch Bar"];
    
    self.statusMenuItem = [[NSMenuItem alloc] initWithTitle:@"Servidor: Ativo" action:nil keyEquivalent:@""];
    [self.statusMenuItem setEnabled:NO];
    [menu addItem:self.statusMenuItem];
    
    self.ipMenuItem = [[NSMenuItem alloc] initWithTitle:@"Endereço IP: Obtendo..." action:nil keyEquivalent:@""];
    [self.ipMenuItem setEnabled:NO];
    [menu addItem:self.ipMenuItem];
    
    self.clientMenuItem = [[NSMenuItem alloc] initWithTitle:@"Dispositivos: Nenhum conectado" action:nil keyEquivalent:@""];
    [self.clientMenuItem setEnabled:NO];
    [menu addItem:self.clientMenuItem];
    
    self.appMenuItem = [[NSMenuItem alloc] initWithTitle:@"Aplicativo Ativo: Finder" action:nil keyEquivalent:@""];
    [self.appMenuItem setEnabled:NO];
    [menu addItem:self.appMenuItem];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    self.virtualMicMenuItem = [[NSMenuItem alloc] initWithTitle:@"Microfone Virtual" action:nil keyEquivalent:@""];
    [menu addItem:self.virtualMicMenuItem];
    
    self.setDefaultMicMenuItem = [[NSMenuItem alloc] initWithTitle:@"   ↳ Definir como Microfone Padrão do Mac" action:@selector(setDefaultMicAction:) keyEquivalent:@""];
    [self.setDefaultMicMenuItem setTarget:self];
    [menu addItem:self.setDefaultMicMenuItem];
    
    [self updateVirtualMicMenuState];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    NSMenuItem *openConfig = [[NSMenuItem alloc] initWithTitle:@"Personalizar Atalhos do Deck..." action:@selector(openConfigWindow) keyEquivalent:@"c"];
    [openConfig setTarget:self];
    [menu addItem:openConfig];
    
    self.launchAtLoginMenuItem = [[NSMenuItem alloc] initWithTitle:@"Abrir ao Iniciar o Mac" action:@selector(toggleLaunchAtStartup) keyEquivalent:@""];
    [self.launchAtLoginMenuItem setTarget:self];
    self.launchAtLoginMenuItem.state = [self isLaunchAtStartupEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:self.launchAtLoginMenuItem];
    
    NSMenuItem *restart = [[NSMenuItem alloc] initWithTitle:@"Reiniciar Servidor" action:@selector(restartServer) keyEquivalent:@"r"];
    [restart setTarget:self];
    [menu addItem:restart];
    
    NSMenuItem *access = [[NSMenuItem alloc] initWithTitle:@"Permissões de Acessibilidade..." action:@selector(openAccessibility) keyEquivalent:@""];
    [access setTarget:self];
    [menu addItem:access];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Encerrar Mac Touch Bar" action:@selector(quitApp) keyEquivalent:@"q"];
    [quit setTarget:self];
    [menu addItem:quit];
    
    self.statusItem.menu = menu;
}

- (BOOL)isLaunchAtStartupEnabled {
    NSString *plistPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/io.github.luxfajah.mactouchbar.plist"];
    return [[NSFileManager defaultManager] fileExistsAtPath:plistPath];
}

- (void)setLaunchAtStartupEnabled:(BOOL)enabled {
    NSString *plistPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/io.github.luxfajah.mactouchbar.plist"];
    if (enabled) {
        NSString *launchAgentsDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents"];
        [[NSFileManager defaultManager] createDirectoryAtPath:launchAgentsDir withIntermediateDirectories:YES attributes:nil error:nil];
        
        NSString *plistContent = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                                 @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
                                 @"<plist version=\"1.0\">\n"
                                 @"<dict>\n"
                                 @"    <key>Label</key>\n"
                                 @"    <string>io.github.luxfajah.mactouchbar</string>\n"
                                 @"    <key>ProgramArguments</key>\n"
                                 @"    <array>\n"
                                 @"        <string>/usr/bin/open</string>\n"
                                 @"        <string>-a</string>\n"
                                 @"        <string>/Volumes/Work/APP TESTE/MacTouchBar.app</string>\n"
                                 @"    </array>\n"
                                 @"    <key>RunAtLoad</key>\n"
                                 @"    <true/>\n"
                                 @"    <key>ProcessType</key>\n"
                                 @"    <string>Interactive</string>\n"
                                 @"</dict>\n"
                                 @"</plist>\n";
        [plistContent writeToFile:plistPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
        NSString *script = @"tell application \"System Events\"\n"
                           @"if not (exists login item \"MacTouchBar\") then\n"
                           @"make login item at end with properties {path:\"/Volumes/Work/APP TESTE/MacTouchBar.app\", hidden:false, name:\"MacTouchBar\"}\n"
                           @"end if\n"
                           @"end tell";
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/osascript";
        task.arguments = @[@"-e", script];
        @try { [task launch]; [task waitUntilExit]; } @catch (NSException *e) {}
    } else {
        [[NSFileManager defaultManager] removeItemAtPath:plistPath error:nil];
        NSString *script = @"tell application \"System Events\"\n"
                           @"if (exists login item \"MacTouchBar\") then\n"
                           @"delete login item \"MacTouchBar\"\n"
                           @"end if\n"
                           @"end tell";
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/osascript";
        task.arguments = @[@"-e", script];
        @try { [task launch]; [task waitUntilExit]; } @catch (NSException *e) {}
    }
}

- (void)toggleLaunchAtStartup {
    BOOL current = [self isLaunchAtStartupEnabled];
    BOOL next = !current;
    [self setLaunchAtStartupEnabled:next];
    self.launchAtLoginMenuItem.state = next ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)openConfigWindow {
    [NSApp activateIgnoringOtherApps:YES];
    [self.configWindowController.window makeKeyAndOrderFront:nil];
}

- (void)startServer {
    self.server = [[TouchBarServer alloc] initWithPort:9876];
    g_server = self.server;
    __weak typeof(self) weakSelf = self;
    self.server.onStatusChange = ^(NSString *frontApp, NSString *clientIp, int clientCount) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.clientMenuItem.title = clientCount > 0 ? 
                [NSString stringWithFormat:@"Dispositivo Conectado (%@)", clientIp] : 
                @"Dispositivos: Nenhum conectado";
            weakSelf.appMenuItem.title = [NSString stringWithFormat:@"Aplicativo Ativo: %@", frontApp];
        });
    };
    [self.server start];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSString *ip = [self getLocalIPAddress] ?: @"127.0.0.1";
        self.ipMenuItem.title = [NSString stringWithFormat:@"Endereço IP: %@:9876", ip];
    });
}

- (void)restartServer {
    [self.server stop];
    [self startServer];
}

- (void)openAccessibility {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    if (url) [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)quitApp {
    [self.server stop];
    [NSApp terminate:nil];
}

- (void)observeActiveApps {
    NSNotificationCenter *nc = [[NSWorkspace sharedWorkspace] notificationCenter];
    
    [nc addObserverForName:NSWorkspaceDidActivateApplicationNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification * _Nonnull note) {
        NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
        if (app.localizedName) {
            self.appMenuItem.title = [NSString stringWithFormat:@"Aplicativo Ativo: %@", app.localizedName];
            [self.server broadcastStatus:app.localizedName];
            [self.server broadcastDeckConfig];
        }
    }];
    
    [nc addObserverForName:NSWorkspaceDidLaunchApplicationNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification * _Nonnull note) {
        [self.server broadcastDeckConfig];
        [self.server broadcastStatus:nil];
    }];
    
    [nc addObserverForName:NSWorkspaceDidTerminateApplicationNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification * _Nonnull note) {
        [self.server broadcastDeckConfig];
        [self.server broadcastStatus:nil];
    }];
}

- (NSString *)getLocalIPAddress {
    NSString *address = @"127.0.0.1";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = getifaddrs(&interfaces);
    if (success == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
                NSString *name = [NSString stringWithUTF8String:temp_addr->ifa_name];
                if ([name isEqualToString:@"en0"] || [name isEqualToString:@"en1"] || [name isEqualToString:@"bridge0"] || [name isEqualToString:@"wlan0"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    if (![address hasPrefix:@"127."]) break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    return address;
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <VideoToolbox/VideoToolbox.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <Network/Network.h>

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

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property (nonatomic, readonly) CGDirectDisplayID displayID;
@end

@interface ScreenStreamer : NSObject <SCStreamOutput, SCStreamDelegate>
@property (nonatomic, strong) nw_connection_t connection;
@property (nonatomic) VTCompressionSessionRef compressionSession;
@property (nonatomic, strong) SCStream *stream;
@property (nonatomic) uint32_t width;
@property (nonatomic) uint32_t height;
@property (nonatomic) int64_t frameIndex;
@end

static void compressionOutputCallback(
    void *outputCallbackRefCon,
    void *sourceFrameRefCon,
    OSStatus status,
    VTEncodeInfoFlags infoFlags,
    CMSampleBufferRef sampleBuffer
) {
    if (status != noErr || !sampleBuffer) return;
    ScreenStreamer *streamer = (__bridge ScreenStreamer *)outputCallbackRefCon;

    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (!blockBuffer) return;

    // Check if keyframe
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    BOOL isKeyframe = YES;
    if (attachments && CFArrayGetCount(attachments) > 0) {
        CFDictionaryRef attachment = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFBooleanRef notSync = (CFBooleanRef)CFDictionaryGetValue(attachment, kCMSampleAttachmentKey_NotSync);
        if (notSync && CFBooleanGetValue(notSync)) {
            isKeyframe = NO;
        }
    }

    NSMutableData *packetData = [NSMutableData data];

    // If keyframe, prepend SPS and PPS parameter sets
    if (isKeyframe) {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        size_t spsSize = 0, ppsSize = 0, spsCount = 0;
        const uint8_t *sps = NULL, *pps = NULL;
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sps, &spsSize, &spsCount, NULL);
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pps, &ppsSize, NULL, NULL);

        if (sps && spsSize > 0) {
            uint8_t startCode[] = {0x00, 0x00, 0x00, 0x01};
            [packetData appendBytes:startCode length:4];
            [packetData appendBytes:sps length:spsSize];
        }
        if (pps && ppsSize > 0) {
            uint8_t startCode[] = {0x00, 0x00, 0x00, 0x01};
            [packetData appendBytes:startCode length:4];
            [packetData appendBytes:pps length:ppsSize];
        }
    }

    // Extract NAL units
    size_t totalLength = 0;
    char *dataPointer = NULL;
    if (CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &totalLength, &dataPointer) == noErr) {
        size_t offset = 0;
        while (offset + 4 <= totalLength) {
            uint32_t nalLength = CFSwapInt32BigToHost(*(uint32_t *)(dataPointer + offset));
            offset += 4;
            if (offset + nalLength <= totalLength) {
                uint8_t startCode[] = {0x00, 0x00, 0x00, 0x01};
                [packetData appendBytes:startCode length:4];
                [packetData appendBytes:(dataPointer + offset) length:nalLength];
                offset += nalLength;
            } else {
                break;
            }
        }
    }

    if (packetData.length > 0 && streamer.connection) {
        // Build 8-byte framing header: [MAGIC: 0xDE 0x5C 0x00 0x01] [4-byte payload size]
        uint8_t header[8];
        header[0] = 0xDE;
        header[1] = 0x5C;
        header[2] = 0x00;
        header[3] = (isKeyframe ? 0x01 : 0x00);
        uint32_t pLen = (uint32_t)packetData.length;
        header[4] = (pLen >> 24) & 0xFF;
        header[5] = (pLen >> 16) & 0xFF;
        header[6] = (pLen >> 8) & 0xFF;
        header[7] = pLen & 0xFF;

        NSMutableData *fullPacket = [NSMutableData dataWithBytes:header length:8];
        [fullPacket appendData:packetData];

        dispatch_data_t dispatchData = dispatch_data_create(fullPacket.bytes, fullPacket.length, dispatch_get_main_queue(), DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        nw_connection_send(streamer.connection, dispatchData, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, false, ^(nw_error_t error) {
            if (error) {
                // Ignore transient send errors
            }
        });
    }
}

@implementation ScreenStreamer

- (void)startWithWidth:(uint32_t)w height:(uint32_t)h displayID:(CGDirectDisplayID)displayID host:(NSString *)host port:(uint16_t)port {
    self.width = w;
    self.height = h;
    self.frameIndex = 0;

    printf("📡 Conectando ao Samsung DeX em %s:%u...\n", [host UTF8String], port);

    nw_endpoint_t endpoint = nw_endpoint_create_host([host UTF8String], [[NSString stringWithFormat:@"%u", port] UTF8String]);
    nw_parameters_t params = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    self.connection = nw_connection_create(endpoint, params);

    dispatch_semaphore_t connSem = dispatch_semaphore_create(0);

    nw_connection_set_state_changed_handler(self.connection, ^(nw_connection_state_t state, nw_error_t error) {
        if (state == nw_connection_state_ready) {
            printf("✅ Conectado ao Samsung DeX com sucesso!\n");
            dispatch_semaphore_signal(connSem);
        } else if (state == nw_connection_state_failed) {
            printf("❌ Falha na conexão de rede com o DeX: %s\n", error ? "Erro de rede" : "");
            exit(1);
        }
    });

    nw_connection_set_queue(self.connection, dispatch_get_main_queue());
    nw_connection_start(self.connection);

    if (dispatch_semaphore_wait(connSem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0) {
        printf("⚠️ Timeout aguardando conexão...\n");
    }

    // 2. Setup Hardware H.264 Encoder (VideoToolbox)
    NSDictionary *encoderSpecs = @{
        (id)kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: @YES
    };

    NSDictionary *sourceAttributes = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferWidthKey: @(w),
        (id)kCVPixelBufferHeightKey: @(h)
    };

    OSStatus status = VTCompressionSessionCreate(
        kCFAllocatorDefault,
        w,
        h,
        kCMVideoCodecType_H264,
        (__bridge CFDictionaryRef)encoderSpecs,
        (__bridge CFDictionaryRef)sourceAttributes,
        NULL,
        compressionOutputCallback,
        (__bridge void *)self,
        &_compressionSession
    );

    if (status != noErr) {
        printf("❌ Erro ao criar sessão VideoToolbox: %d\n", status);
        return;
    }

    // Configure VideoToolbox for real-time low latency
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel);
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(8000000)); // 8 Mbps
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef)@(60)); // Keyframe every 1s
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_ExpectedFrameRate, (__bridge CFTypeRef)@(60));
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);

    VTCompressionSessionPrepareToEncodeFrames(self.compressionSession);
    printf("⚡ Codificador H.264 por Hardware pronto (%ux%u @ 60 FPS)\n", w, h);

    // 3. Setup ScreenCaptureKit for Virtual Display
    if (@available(macOS 12.3, *)) {
        [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent *content, NSError *error) {
            if (error || !content) {
                printf("❌ Erro no ScreenCaptureKit: %s\n", error.localizedDescription.UTF8String);
                return;
            }

            SCDisplay *targetDisplay = nil;
            for (SCDisplay *d in content.displays) {
                if (d.displayID == displayID) {
                    targetDisplay = d;
                    break;
                }
            }

            if (!targetDisplay) {
                targetDisplay = content.displays.firstObject;
            }

            SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:targetDisplay excludingWindows:@[]];
            SCStreamConfiguration *config = [[SCStreamConfiguration alloc] init];
            config.width = w;
            config.height = h;
            config.minimumFrameInterval = CMTimeMake(1, 60);
            config.queueDepth = 3;
            config.pixelFormat = kCVPixelFormatType_32BGRA;
            config.showsCursor = YES;

            self.stream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:self];
            NSError *streamError = nil;
            [self.stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0) error:&streamError];

            [self.stream startCaptureWithCompletionHandler:^(NSError *startError) {
                if (startError) {
                    printf("❌ Erro ao iniciar captura: %s\n", startError.localizedDescription.UTF8String);
                } else {
                    printf("🎉 TRANSMISSÃO DO SEGUNDO MONITOR ATIVA A 60 FPS!\n");
                    printf("👉 Arraste qualquer janela para a segunda tela no DeX!\n");
                }
            }];
        }];
    }
}

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(SCStreamOutputType)type {
    if (type != SCStreamOutputTypeScreen || !self.compressionSession) return;

    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!imageBuffer) return;

    int64_t idx = ++self.frameIndex;
    CMTime pts = CMTimeMake(idx, 60);
    CMTime duration = CMTimeMake(1, 60);

    NSDictionary *frameProperties = nil;
    if (idx % 60 == 1) {
        frameProperties = @{(id)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES};
    }

    VTCompressionSessionEncodeFrame(
        self.compressionSession,
        imageBuffer,
        pts,
        duration,
        (__bridge CFDictionaryRef)frameProperties,
        NULL,
        NULL
    );
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        printf("=====================================================\n");
        printf("🚀 DeXExtend Pro - Transmissor de Monitor Estendido\n");
        printf("=====================================================\n\n");

        char ipInput[128];
        printf("Digite o IP do Samsung DeX [Padrão: 192.168.1.3]: ");
        if (fgets(ipInput, sizeof(ipInput), stdin)) {
            strtok(ipInput, "\r\n");
        }
        NSString *targetIP = (strlen(ipInput) > 0) ? [NSString stringWithUTF8String:ipInput] : @"192.168.1.3";

        printf("\nEscolha a orientação do Monitor Estendido no DeX:\n");
        printf("1) 1080x1920 (Vertical / Retrato)\n");
        printf("2) 1920x1080 (Horizontal / Paisagem)\n");
        printf("Opção [Padrão: 1]: ");
        char opt[32];
        if (fgets(opt, sizeof(opt), stdin)) {
            strtok(opt, "\r\n");
        }

        uint32_t width = (strcmp(opt, "2") == 0) ? 1920 : 1080;
        uint32_t height = (strcmp(opt, "2") == 0) ? 1080 : 1920;

        printf("\nCriando Monitor Virtual Secundário (%ux%u @ 60Hz)...\n", width, height);

        Class descClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
        Class dispClass = NSClassFromString(@"CGVirtualDisplay");
        Class settClass = NSClassFromString(@"CGVirtualDisplaySettings");

        CGDirectDisplayID displayID = CGMainDisplayID();

        if (descClass && dispClass && settClass) {
            CGVirtualDisplayDescriptor *descriptor = [[descClass alloc] init];
            descriptor.name = @"Samsung DeX Extended Display";
            descriptor.maxPixelsWide = width;
            descriptor.maxPixelsHigh = height;
            descriptor.sizeInMillimeters = CGSizeMake(300, 500);
            descriptor.queue = dispatch_get_main_queue();

            CGVirtualDisplay *virtualDisplay = [[dispClass alloc] initWithDescriptor:descriptor];
            if (virtualDisplay) {
                CGVirtualDisplaySettings *settings = [[settClass alloc] init];
                settings.pixelsWide = width;
                settings.pixelsHigh = height;
                settings.refreshRate = 60.0;
                [virtualDisplay applySettings:settings];
                displayID = virtualDisplay.displayID;
                printf("✅ Monitor Virtual Secundário Criado! DisplayID: %u\n", displayID);
            }
        }

        ScreenStreamer *streamer = [[ScreenStreamer alloc] init];
        [streamer startWithWidth:width height:height displayID:displayID host:targetIP port:7000];

        printf("\nPressione Ctrl+C para encerrar o Segundo Monitor.\n");
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}

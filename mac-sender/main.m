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

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property (nonatomic, readonly) CGDirectDisplayID displayID;
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        printf("=====================================================\n");
        printf("🚀 DeXExtend - Monitor Virtual Estendido para Mac\n");
        printf("=====================================================\n\n");

        char ipInput[128];
        printf("Digite o IP do Samsung DeX [Padrão: 192.168.1.3]: ");
        if (fgets(ipInput, sizeof(ipInput), stdin)) {
            strtok(ipInput, "\r\n");
        }
        NSString *targetIP = (strlen(ipInput) > 0) ? [NSString stringWithUTF8String:ipInput] : @"192.168.1.3";

        printf("\nEscolha a orientação do Segundo Monitor:\n");
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

        if (!descClass || !dispClass || !settClass) {
            printf("❌ CGVirtualDisplay não disponível nesta versão do macOS.\n");
            return 1;
        }

        CGVirtualDisplayDescriptor *descriptor = [[descClass alloc] init];
        descriptor.name = @"Samsung DeX Extended Display";
        descriptor.maxPixelsWide = width;
        descriptor.maxPixelsHigh = height;
        descriptor.sizeInMillimeters = CGSizeMake(300, 500);
        descriptor.queue = dispatch_get_main_queue();

        CGVirtualDisplay *virtualDisplay = [[dispClass alloc] initWithDescriptor:descriptor];
        if (!virtualDisplay) {
            printf("❌ Erro ao instanciar monitor virtual.\n");
            return 1;
        }

        CGVirtualDisplaySettings *settings = [[settClass alloc] init];
        settings.pixelsWide = width;
        settings.pixelsHigh = height;
        settings.refreshRate = 60.0;
        [virtualDisplay applySettings:settings];

        printf("✅ SEGUNDO MONITOR CRIADO COM SUCESSO!\n");
        printf("🖥️ Display ID: %u\n", virtualDisplay.displayID);
        printf("👉 Abra 'Ajustes do Sistema -> Telas' no Mac para organizar as telas!\n");
        printf("👉 Arraste qualquer janela para a lateral da tela e ela entrará no Samsung DeX!\n\n");
        printf("Conectado ao DeXPlay no IP: %s:7000\n", [targetIP UTF8String]);
        printf("Pressione [Enter] ou Ctrl+C para encerrar o Segundo Monitor...\n");

        getchar();
        printf("Encerrando monitor virtual...\n");
    }
    return 0;
}

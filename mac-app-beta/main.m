#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <Carbon/Carbon.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Sparkle/Sparkle.h>
#import <ifaddrs.h>
#import <arpa/inet.h>

// ─── Vista transparente de arraste (titlebar drag area) ───────────────────────
// O WKWebView cobre toda a janela, bloqueando o drag nativo.
// Esta NSView fica sobreposta ao topo, retornando o evento para a janela.
@interface WindowDragView : NSView
@end

@implementation WindowDragView

- (BOOL)mouseDownCanMoveWindow { return YES; }
- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)dirtyRect { /* totalmente transparente */ }

- (void)mouseDown:(NSEvent *)event {
    // Delega o drag diretamente para a janela (macOS 10.11+)
    [self.window performWindowDragWithEvent:event];
}

@end
// ─────────────────────────────────────────────────────────────────────────────

@interface BetaWindow : NSWindow
- (void)adjustTrafficLights;
@end

@implementation BetaWindow

- (void)layoutIfNeeded {
    [super layoutIfNeeded];
    [self adjustTrafficLights];
}

- (void)setFrame:(NSRect)frameRect display:(BOOL)displayFlag {
    [super setFrame:frameRect display:displayFlag];
    [self adjustTrafficLights];
}

- (void)becomeKeyWindow {
    [super becomeKeyWindow];
    [self adjustTrafficLights];
}

- (void)resignKeyWindow {
    [super resignKeyWindow];
    [self adjustTrafficLights];
}

- (void)adjustTrafficLights {
    static BOOL adjusting = NO;
    if (adjusting) return;
    adjusting = YES;
    
    NSButton *closeBtn = [self standardWindowButton:NSWindowCloseButton];
    NSButton *minBtn = [self standardWindowButton:NSWindowMiniaturizeButton];
    NSButton *zoomBtn = [self standardWindowButton:NSWindowZoomButton];
    if (!closeBtn || !minBtn || !zoomBtn) {
        adjusting = NO;
        return;
    }
    
    [closeBtn setHidden:NO];
    [minBtn setHidden:NO];
    [zoomBtn setHidden:NO];
    
    NSView *titlebarView = closeBtn.superview;
    if (!titlebarView) {
        adjusting = NO;
        return;
    }
    
    CGFloat btnW = 14.0;
    CGFloat btnH = 16.0;
    CGFloat titlebarHeight = titlebarView.bounds.size.height;
    if (titlebarHeight < 20.0) titlebarHeight = 52.0;
    CGFloat btnY = (titlebarHeight - btnH) / 2.0;
    CGFloat startX = 18.0;
    CGFloat spacing = 6.0;
    
    closeBtn.frame = NSMakeRect(startX, btnY, btnW, btnH);
    minBtn.frame = NSMakeRect(startX + btnW + spacing, btnY, btnW, btnH);
    zoomBtn.frame = NSMakeRect(startX + (btnW + spacing) * 2, btnY, btnW, btnH);
    
    adjusting = NO;
}

@end

@interface BetaAppDelegate : NSObject <NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, copy) NSString *lastWallpaperPath;
@property (nonatomic, strong) NSTimer *wallpaperTimer;
@property (nonatomic, strong) SPUStandardUpdaterController *updaterController;
@end

static BetaAppDelegate *gDelegate = nil;

@implementation BetaAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSLog(@"[MacTouchBarBeta] Iniciando MacTouchBar Studio (Apple HIG)...");
    
    // Sparkle Updater Initialization
    self.updaterController = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:YES
                                                                            updaterDelegate:nil
                                                                         userDriverDelegate:nil];
    [self setupMainMenu];
    
    // Window creation with solid Apple dark appearance
    NSRect screenRect = [[NSScreen mainScreen] visibleFrame];
    CGFloat width = 1040;
    CGFloat height = 700;
    NSRect frame = NSMakeRect(screenRect.origin.x + (screenRect.size.width - width) / 2.0,
                              screenRect.origin.y + (screenRect.size.height - height) / 2.0,
                              width, height);
    
    NSWindowStyleMask style = NSWindowStyleMaskTitled | 
                              NSWindowStyleMaskClosable | 
                              NSWindowStyleMaskMiniaturizable | 
                              NSWindowStyleMaskResizable |
                              NSWindowStyleMaskFullSizeContentView;
    
    self.window = [[BetaWindow alloc] initWithContentRect:frame
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"MacTouchBar Studio";
    self.window.titlebarAppearsTransparent = YES;
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.minSize = NSMakeSize(880, 560);
    self.window.opaque = YES;
    self.window.releasedWhenClosed = NO;
    self.window.delegate = self;
    
    // HIG: Define appearance da janela de acordo com o tema do sistema.
    // Isso garante que prefers-color-scheme no WKWebView reflita o estado correto
    // e as scrollbars nativas usem a variante certa desde o primeiro frame.
    // Ref: HIG Dark Mode > "Ensure that your app looks good in both appearance modes."
    BOOL isDarkOnLaunch = [self isDarkModeActive];
    self.window.appearance = [NSAppearance appearanceNamed:
        isDarkOnLaunch ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    self.window.backgroundColor = isDarkOnLaunch
        ? [NSColor colorWithCalibratedRed:0.12 green:0.12 blue:0.14 alpha:1.0]
        : [NSColor colorWithCalibratedRed:0.95 green:0.95 blue:0.97 alpha:1.0];
    
    // Expand titlebar cleanly using Apple HIG recommended titlebar accessory
    NSTitlebarAccessoryViewController *titlebarAccessory = [[NSTitlebarAccessoryViewController alloc] init];
    titlebarAccessory.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 0, 24)];
    titlebarAccessory.layoutAttribute = NSLayoutAttributeBottom;
    [self.window addTitlebarAccessoryViewController:titlebarAccessory];
    [(BetaWindow *)self.window adjustTrafficLights];
    
    // WKWebView Configuration with Apple Native Bridge
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:self name:@"macNative"];
    config.userContentController = ucc;
    [config.preferences setValue:@YES forKey:@"developerExtrasEnabled"];
    
    self.webView = [[WKWebView alloc] initWithFrame:self.window.contentView.bounds configuration:config];
    self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.webView.navigationDelegate = self;
    [self.webView setValue:@NO forKey:@"drawsBackground"];
    
    [self.window.contentView addSubview:self.webView];
    


    
    // Load HTML UI
    NSString *bundlePath = [[NSBundle mainBundle] resourcePath];
    NSString *htmlPath = [bundlePath stringByAppendingPathComponent:@"index.html"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:htmlPath]) {
        htmlPath = @"/Volumes/Work/APP TESTE/mac-app-beta/index.html";
    }
    NSURL *fileURL = [NSURL fileURLWithPath:htmlPath];
    [self.webView loadFileURL:fileURL allowingReadAccessToURL:[fileURL URLByDeletingLastPathComponent]];
    
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];
    [NSApp activateIgnoringOtherApps:YES];
    
    // Observers
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(onAppActivated:)
                                                               name:NSWorkspaceDidActivateApplicationNotification
                                                             object:nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(onAppearanceChanged:)
                                                            name:@"AppleColorPreferencesChangedNotification"
                                                          object:nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(onAppearanceChanged:)
                                                            name:@"AppleInterfaceThemeChangedNotification"
                                                          object:nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(onRunScriptNotification:)
                                                            name:@"MacTouchBarRunScriptNotification"
                                                          object:nil
                                              suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    
    // Check and monitor macOS Wallpaper
    [self checkAndSyncWallpaper];
    self.wallpaperTimer = [NSTimer scheduledTimerWithTimeInterval:4.0
                                                           target:self
                                                         selector:@selector(checkAndSyncWallpaper)
                                                         userInfo:nil
                                                          repeats:YES];
}

- (void)onRunScriptNotification:(NSNotification *)note {
    NSString *js = note.userInfo[@"script"];
    if (js && js.length > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.webView evaluateJavaScript:js completionHandler:nil];
        });
    }
}

- (void)onAppActivated:(NSNotification *)note {
    [self sendSystemInfoToUI];
}

- (void)windowDidResize:(NSNotification *)notification {
    [(BetaWindow *)self.window adjustTrafficLights];
}

- (void)saveSnapshotToPath:(NSString *)destPath {
    WKSnapshotConfiguration *cfg = [[WKSnapshotConfiguration alloc] init];
    [self.webView takeSnapshotWithConfiguration:cfg completionHandler:^(NSImage *snapshot, NSError *error) {
        if (snapshot) {
            NSData *tiffData = [snapshot TIFFRepresentation];
            NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:tiffData];
            NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            [pngData writeToFile:destPath atomically:YES];
            NSLog(@"[MacTouchBarBeta] Snapshot salvo com sucesso em: %@", destPath);
        }
    }];
}

- (void)captureSequenceStep1 {
    [self.webView evaluateJavaScript:@"if (typeof switchSimScreen === 'function') switchSimScreen(4);" completionHandler:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self saveSnapshotToPath:@"/Volumes/Work/APP TESTE/screenshot_sim_illustrator.png"];
        [self captureSequenceStep2];
    });
}

- (void)captureSequenceStep2 {
    [self.webView evaluateJavaScript:@"if (typeof switchSimScreen === 'function') switchSimScreen(5);" completionHandler:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self saveSnapshotToPath:@"/Volumes/Work/APP TESTE/screenshot_sim_photoshop.png"];
        [self captureSequenceStep3];
    });
}

- (void)captureSequenceStep3 {
    [self.webView evaluateJavaScript:@"if (typeof navigateTo === 'function') navigateTo('pane-extensions'); setTimeout(() => { if (typeof openExtensionConfig === 'function') openExtensionConfig('addon-illustrator'); }, 200);" completionHandler:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self saveSnapshotToPath:@"/Volumes/Work/APP TESTE/screenshot_addon_illustrator_modal.png"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.webView evaluateJavaScript:@"if (typeof closeExtensionConfig === 'function') closeExtensionConfig(); if (typeof navigateTo === 'function') navigateTo('pane-overview'); if (typeof switchSimScreen === 'function') switchSimScreen(1);" completionHandler:nil];
        });
    });
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self sendSystemInfoToUI];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self saveSnapshotToPath:@"/Volumes/Work/APP TESTE/screenshot_webview.png"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self captureSequenceStep1];
        });
    });
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
                if ([name hasPrefix:@"en"]) {
                    NSString *ip = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    if (![ip isEqualToString:@"127.0.0.1"]) {
                        address = ip;
                        break;
                    }
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    if (interfaces) freeifaddrs(interfaces);
    return address;
}

- (NSString *)getCurrentDesktopWallpaperPath {
    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:
        @"tell application \"System Events\" to tell current desktop to get picture"];
    NSDictionary *err = nil;
    NSAppleEventDescriptor *desc = [script executeAndReturnError:&err];
    if (desc) {
        return [desc stringValue];
    }
    return nil;
}

- (void)checkAndSyncWallpaper {
    NSString *currentPath = [self getCurrentDesktopWallpaperPath];
    if (!currentPath || currentPath.length == 0) return;
    
    if (![currentPath isEqualToString:self.lastWallpaperPath]) {
        self.lastWallpaperPath = currentPath;
        NSLog(@"[MacTouchBarBeta] Papel de parede dinâmico detectado: %@", currentPath);
        [self copyWallpaperToProject:currentPath];
        
        // Notify WebView
        NSString *js = [NSString stringWithFormat:@"if (window.onDynamicWallpaperUpdated) window.onDynamicWallpaperUpdated('%@');",
                        [currentPath stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.webView evaluateJavaScript:js completionHandler:nil];
        });
    }
}

- (void)copyWallpaperToProject:(NSString *)sourcePath {
    if (![[NSFileManager defaultManager] fileExistsAtPath:sourcePath]) return;
    
    NSArray *destinations = @[
        @"/Volumes/Work/APP TESTE/wallpaper.jpg",
        @"/Volumes/Work/APP TESTE/ipados-preview/wallpaper.jpg",
        @"/Volumes/Work/APP TESTE/touchbar-hackintosh/src/main/assets/ipados/wallpaper.jpg"
    ];
    
    for (NSString *dest in destinations) {
        NSError *err = nil;
        [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
        [[NSFileManager defaultManager] copyItemAtPath:sourcePath toPath:dest error:&err];
        if (err) {
            NSLog(@"[MacTouchBarBeta] Erro ao sincronizar wallpaper para %@: %@", dest, err.localizedDescription);
        } else {
            NSLog(@"[MacTouchBarBeta] Sincronizado com sucesso para %@", dest);
        }
    }
}

- (NSString *)getSystemAccentColorHex {
    NSColor *color = [[NSColor controlAccentColor] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (color) {
        return [NSString stringWithFormat:@"#%02X%02X%02X",
                (int)(color.redComponent * 255.0),
                (int)(color.greenComponent * 255.0),
                (int)(color.blueComponent * 255.0)];
    }
    return @"#007AFF";
}

- (BOOL)isDarkModeActive {
    NSAppearance *appAppearance = [NSApp effectiveAppearance] ?: [self.window effectiveAppearance];
    if (@available(macOS 10.14, *)) {
        NSAppearanceName bestMatch = [appAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        return [bestMatch isEqualToString:NSAppearanceNameDarkAqua];
    }
    return YES;
}

- (void)onAppearanceChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL isDark = [self isDarkModeActive];
        
        // HIG: Atualiza appearance da janela para que o WKWebView receba
        // o prefers-color-scheme correto e as scrollbars nativas troquem de tema.
        // Ref: HIG Dark Mode > "Embrace colors that adapt to the current appearance."
        self.window.appearance = [NSAppearance appearanceNamed:
            isDark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
        
        self.window.backgroundColor = isDark
            ? [NSColor colorWithCalibratedRed:0.12 green:0.12 blue:0.14 alpha:1.0]
            : [NSColor colorWithCalibratedRed:0.95 green:0.95 blue:0.97 alpha:1.0];
        
        [self sendSystemInfoToUI];
    });
}

- (void)sendSystemInfoToUI {
    NSRunningApplication *app = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSString *appName = app.localizedName ?: @"Finder";
    NSString *bundleId = app.bundleIdentifier ?: @"com.apple.finder";
    NSString *ip = [self getLocalIPAddress];
    NSString *hostName = [[NSHost currentHost] localizedName] ?: @"Mac";
    NSString *wallPath = self.lastWallpaperPath ?: [self getCurrentDesktopWallpaperPath] ?: @"";
    NSString *accent = [self getSystemAccentColorHex];
    BOOL isDark = [self isDarkModeActive];
    
    NSString *js = [NSString stringWithFormat:@"if (window.onSystemInfo) window.onSystemInfo({appName: '%@', bundleId: '%@', ip: '%@', hostName: '%@', wallpaperPath: '%@', accentColor: '%@', isDark: %@});",
                    [appName stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"],
                    [bundleId stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"],
                    ip,
                    [hostName stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"],
                    [wallPath stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"],
                    accent,
                    isDark ? @"true" : @"false"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.body isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *body = (NSDictionary *)message.body;
    NSString *action = body[@"action"];
    
    if ([action isEqualToString:@"getSystemInfo"]) {
        [self sendSystemInfoToUI];
    } else if ([action isEqualToString:@"closeWindow"]) {
        [self.window performClose:nil];
    } else if ([action isEqualToString:@"minimizeWindow"]) {
        [self.window performMiniaturize:nil];
    } else if ([action isEqualToString:@"zoomWindow"]) {
        BOOL isAlt = [body[@"altKey"] boolValue];
        if (isAlt) {
            [self.window zoom:nil];
        } else {
            [self.window toggleFullScreen:nil];
        }
    } else if ([action isEqualToString:@"syncWallpaperNow"]) {
        NSString *path = [self getCurrentDesktopWallpaperPath];
        if (path) {
            [self copyWallpaperToProject:path];
            [self sendSystemInfoToUI];
        }
    } else if ([action isEqualToString:@"chooseCustomWallpaper"]) {
        [self openWallpaperPicker];
    } else if ([action isEqualToString:@"checkTechnicalStatus"]) {
        [self checkTechnicalStatus];
    } else if ([action isEqualToString:@"requestAccessibility"]) {
        NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
        [self checkTechnicalStatus];
    } else if ([action isEqualToString:@"openSystemSettings"]) {
        NSString *pane = body[@"pane"] ?: @"Privacy_Accessibility";
        NSString *urlStr = [NSString stringWithFormat:@"x-apple.systempreferences:com.apple.preference.security?%@", pane];
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlStr]];
    } else if ([action isEqualToString:@"restartDaemon"]) {
        [self restartDaemonProcess];
    } else if ([action isEqualToString:@"saveConfig"]) {
        NSLog(@"[MacTouchBarBeta] Ajustes salvos: %@", body);
    } else if ([action isEqualToString:@"checkForUpdates"]) {
        NSLog(@"[MacTouchBarBeta] Sparkle: Verificando atualizações...");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.updaterController checkForUpdates:nil];
        });
    } else if ([action isEqualToString:@"takeSnapshot"]) {
        NSString *dest = body[@"path"] ?: @"/Volumes/Work/APP TESTE/screenshot_webview.png";
        [self saveSnapshotToPath:dest];
    }
}

- (void)setupMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];
    
    // App Menu
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"MacTouchBar Beta"];
    
    [appMenu addItemWithTitle:@"Sobre o MacTouchBar Studio" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    
    NSMenuItem *checkUpdatesItem = [[NSMenuItem alloc] initWithTitle:@"Verificar Atualizações..." action:@selector(checkForUpdates:) keyEquivalent:@""];
    [checkUpdatesItem setTarget:self.updaterController];
    [appMenu addItem:checkUpdatesItem];
    
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Ocultar MacTouchBar Studio" action:@selector(hide:) keyEquivalent:@"h"];
    
    NSMenuItem *hideOthersItem = [[NSMenuItem alloc] initWithTitle:@"Ocultar Outros" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    [hideOthersItem setKeyEquivalentModifierMask:(NSEventModifierFlagOption | NSEventModifierFlagCommand)];
    [appMenu addItem:hideOthersItem];
    
    [appMenu addItemWithTitle:@"Mostrar Todos" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Encerrar MacTouchBar Studio" action:@selector(terminate:) keyEquivalent:@"q"];
    
    [appMenuItem setSubmenu:appMenu];
    [mainMenu addItem:appMenuItem];
    
    // Edit Menu (para comandos normais de clipboard)
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Editar"];
    [editMenu addItemWithTitle:@"Desfazer" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Refazer" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Recortar" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copiar" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Colar" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Selecionar Tudo" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenuItem setSubmenu:editMenu];
    [mainMenu addItem:editMenuItem];
    
    // Window Menu
    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] init];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Janela"];
    [windowMenu addItemWithTitle:@"Minimizar" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [windowMenuItem setSubmenu:windowMenu];
    [mainMenu addItem:windowMenuItem];
    
    [NSApp setMainMenu:mainMenu];
}

- (BOOL)isAccessibilityGranted {
    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @NO};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

- (BOOL)isDaemonPortListening {
    struct sockaddr_in server_addr;
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return NO;
    
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(9876);
    inet_pton(AF_INET, "127.0.0.1", &server_addr.sin_addr);
    
    // Set 500ms timeout
    struct timeval tv;
    tv.tv_sec = 0;
    tv.tv_usec = 500000;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof tv);
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, (const char*)&tv, sizeof tv);
    
    int res = connect(sock, (struct sockaddr *)&server_addr, sizeof(server_addr));
    close(sock);
    return (res == 0);
}

- (void)checkTechnicalStatus {
    BOOL axGranted = [self isAccessibilityGranted];
    BOOL daemonOnline = [self isDaemonPortListening];
    NSString *ip = [self getLocalIPAddress];
    NSString *macOSVer = [[NSProcessInfo processInfo] operatingSystemVersionString];
    
    NSString *js = [NSString stringWithFormat:@"if (window.onTechnicalStatus) window.onTechnicalStatus({accessibility: %@, daemonOnline: %@, port: 9876, ip: '%@', osVersion: '%@'});",
                    axGranted ? @"true" : @"false",
                    daemonOnline ? @"true" : @"false",
                    ip,
                    [macOSVer stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

- (void)restartDaemonProcess {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        system("killall -9 python3 2>/dev/null || true");
        NSString *scriptPath = @"/Volumes/Work/APP TESTE/mac-companion/mac_deck_server.py";
        if ([[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {
            NSString *cmd = [NSString stringWithFormat:@"python3 \"%@\" > /dev/null 2>&1 &", scriptPath];
            system([cmd UTF8String]);
        }
        [NSThread sleepForTimeInterval:1.0];
        [self checkTechnicalStatus];
    });
}

#pragma mark - NSWindowDelegate

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [self.webView evaluateJavaScript:@"if (window.setWindowActive) window.setWindowActive(true);" completionHandler:nil];
}

- (void)windowDidResignKey:(NSNotification *)notification {
    [self.webView evaluateJavaScript:@"if (window.setWindowActive) window.setWindowActive(false);" completionHandler:nil];
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification {
    [self.webView evaluateJavaScript:@"if (window.setFullScreenState) window.setFullScreenState(true);" completionHandler:nil];
}

- (void)windowDidExitFullScreen:(NSNotification *)notification {
    [self.webView evaluateJavaScript:@"if (window.setFullScreenState) window.setFullScreenState(false);" completionHandler:nil];
}

- (void)openWallpaperPicker {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.allowedContentTypes = @[UTTypeJPEG, UTTypePNG, UTTypeHEIC];
    
    [panel beginWithCompletionHandler:^(NSInteger result) {
        if (result == NSModalResponseOK && panel.URL) {
            NSString *chosenPath = panel.URL.path;
            [self copyWallpaperToProject:chosenPath];
            NSString *js = [NSString stringWithFormat:@"if (window.onCustomWallpaperChosen) window.onCustomWallpaperChosen('%@');",
                            [chosenPath stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]];
            [self.webView evaluateJavaScript:js completionHandler:nil];
        }
    }];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        gDelegate = [[BetaAppDelegate alloc] init];
        app.delegate = gDelegate;
        [app run];
    }
    return 0;
}

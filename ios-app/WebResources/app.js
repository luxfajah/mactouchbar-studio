/* ==========================================================================
   MacTouchBar 3-Screen Engine & Native Mac Companion Client
   - Screen 0: Apple StandBy Landscape Music Player (Live Apple Music / Music.app)
   - Screen 1: Native Deck 2x6 (Double Size Icons, Liquid Glass, Running Dots)
   - Screen 2: Apple Control Center (Connectivity, Battery, AirPods, Sliders, Hotkeys)
   - Ultra-Low Latency WebSocket & Dynamic Apple Backdrop Blur
   ========================================================================== */

(function () {
  'use strict';

  // Determine intelligent default IP
  let defaultIp = '192.168.1.6';
  if (typeof window !== 'undefined' && window.location && window.location.hostname) {
    if (window.location.hostname !== '' && window.location.hostname !== 'localhost' && window.location.hostname !== '127.0.0.1') {
      defaultIp = window.location.hostname;
    }
  }

  // Global App State
  const state = {
    currentScreen: 1, // 0: Music, 1: Deck 2x6 (Center), 2: Control Center
    connected: false,
    connecting: false,
    macIp: localStorage.getItem('mac_touchbar_ip') || defaultIp,
    macPort: localStorage.getItem('mac_touchbar_port') || '9876',
    ws: null,
    reconnectTimer: null,
    heartbeatTimer: null,
    volume: 50,
    brightness: 75,
    media: {
      player: 'None',
      title: 'Nenhuma reprodução',
      artist: 'Apple Music',
      state: 'stopped'
    },
    buttons: []
  };

  // 12 Native Mac Apps with Official Icons (Zero Emojis)
  const DEFAULT_DECK = [
    // Row 1: Chrome, Música, Discord, Photoshop, Illustrator, InDesign
    { id: 'chrome', label: 'Chrome', iconUrl: 'icons/chrome.png', actionType: 'launch_app', payload: '/Applications/Google Chrome.app', isRunning: false },
    { id: 'music', label: 'Música', iconUrl: 'icons/music.png', actionType: 'launch_app', payload: '/System/Applications/Music.app', isRunning: false },
    { id: 'discord', label: 'Discord', iconUrl: 'icons/discord.png', actionType: 'launch_app', payload: '/Applications/Discord.app', isRunning: false },
    { id: 'photoshop', label: 'Photoshop', iconUrl: 'icons/photoshop.png', actionType: 'launch_app', payload: '/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app', isRunning: false },
    { id: 'illustrator', label: 'Illustrator', iconUrl: 'icons/illustrator.png', actionType: 'launch_app', payload: '/Applications/Adobe Illustrator 2026/Adobe Illustrator.app', isRunning: false },
    { id: 'indesign', label: 'InDesign', iconUrl: 'icons/indesign.png', actionType: 'launch_app', payload: '/Applications/Adobe InDesign 2026/Adobe InDesign 2026.app', isRunning: false },
    
    // Row 2: Figma, Affinity, Antigravity, WhatsApp, Finder, Launchpad
    { id: 'figma', label: 'Figma', iconUrl: 'icons/figma.png', actionType: 'launch_app', payload: '/Applications/Figma.app', isRunning: false },
    { id: 'affinity', label: 'Affinity', iconUrl: 'icons/affinity.png', actionType: 'launch_app', payload: '/Applications/Affinity.app', isRunning: false },
    { id: 'antigravity', label: 'Antigravity', iconUrl: 'icons/antigravity.png', actionType: 'launch_app', payload: '/Applications/Antigravity.app', isRunning: false },
    { id: 'whatsapp', label: 'WhatsApp', iconUrl: 'icons/whatsapp.png', actionType: 'launch_app', payload: '/Applications/WhatsApp.app', isRunning: false },
    { id: 'finder', label: 'Finder', iconUrl: 'icons/finder.png', actionType: 'launch_app', payload: '/System/Library/CoreServices/Finder.app', isRunning: true },
    { id: 'launchpad', label: 'Launchpad', iconUrl: 'icons/settings.png', actionType: 'launch_app', payload: '/System/Applications/Launchpad.app', isRunning: false }
  ];

  // Helper to safely fetch elements
  function getEl(id) {
    return document.getElementById(id);
  }

  // DOM Elements Map
  let el = {};

  function initElements() {
    el = {
      viewport: getEl('carousel-viewport'),
      track: getEl('carousel-track'),
      dotPage0: getEl('dot-page-0'),
      dotPage1: getEl('dot-page-1'),
      dotPage2: getEl('dot-page-2'),
      dotPage3: getEl('dot-page-3'),
      cameraLedDot: getEl('camera-led-dot'),
      btnConnSettings: getEl('btn-conn-settings'),
      deckGrid: getEl('deck-grid'),
      // Dynamic Backdrop Overlay
      screenBackdropOverlay: getEl('screen-backdrop-overlay'),
      // Music Player Elements
      musicScreenContainer: getEl('music-screen-container'),
      musicArtBox: getEl('music-art-box'),
      musicArtImg: getEl('music-art-img'),
      musicTitle: getEl('music-title'),
      musicArtist: getEl('music-artist'),
      btnMusicFav: getEl('btn-music-fav'),
      musicScrubberTrack: getEl('music-scrubber-track'),
      musicScrubberFill: getEl('music-scrubber-fill'),
      musicTimeElapsed: getEl('music-time-elapsed'),
      musicTimeRemaining: getEl('music-time-remaining'),
      glyphPlay: getEl('glyph-play'),
      musicVolSlider: getEl('music-vol-slider'),
      musicVolFill: getEl('music-vol-fill'),
      sliderBrightness: getEl('slider-box-brightness'),
      sliderFillBrightness: getEl('slider-fill-brightness'),
      sliderVolume: getEl('slider-box-volume'),
      sliderFillVolume: getEl('slider-fill-volume'),
      modalConn: getEl('modal-conn-setup'),
      inputIp: getEl('input-mac-ip'),
      inputPort: getEl('input-mac-port'),
      btnSaveConnect: getEl('btn-save-connect'),
      toast: getEl('toast-bubble'),
      // Battery Elements
      batteryLevelBar: getEl('cc-battery-level-bar'),
      batteryPctLabel: getEl('cc-battery-pct-label'),
      batteryBoltIcon: getEl('cc-battery-bolt-icon'),
      batteryModeLabel: getEl('cc-battery-mode-label'),
      navBatteryLevel: getEl('nav-battery-level'),
      // AirPods Elements
      airpodsCard: getEl('cc-airpods-card'),
      airpodsName: getEl('cc-airpods-name'),
      airpodsStatus: getEl('cc-airpods-status'),
      airpodPctLeft: getEl('cc-airpod-pct-left'),
      airpodFillLeft: getEl('cc-airpod-fill-left'),
      airpodPctRight: getEl('cc-airpod-pct-right'),
      airpodFillRight: getEl('cc-airpod-fill-right'),
      airpodPctCase: getEl('cc-airpod-pct-case'),
      airpodFillCase: getEl('cc-airpod-fill-case')
    };
  }

  // User slider drag states to prevent sync jitter & broadcast overwrite
  let isDraggingVolume = false;
  let isDraggingBrightness = false;
  let isInteractingWithColorPicker = false;
  let lastUserVolTime = 0;
  let lastUserBrightTime = 0;

  // Media Playback State & Timers
  let currentDuration = 0;
  let currentPosition = 0;
  let scrubberTimer = null;
  let currentArtKey = '';

  // ==========================================================================
  // ==========================================================================
  // 1. 4-Screen Carousel Navigation & Control Center Pull-Down System
  //    Screen 0: StandBy Apple Music Player (Esquerda)
  //    Screen 1: Deck de Atalhos 2x6 (Centro)
  //    Screen 2: Adobe Illustrator Studio - Cores & Vetor (Direita 1)
  //    Screen 3: Adobe Illustrator Studio - Tipografia & Texto (Direita 2)
  // ==========================================================================
  function goToScreen(index) {
    const screens = document.querySelectorAll('.carousel-screen');
    const totalScreens = Math.max(screens.length, 4);
    if (index < 0 || index >= totalScreens) return;
    state.currentScreen = index;

    // Shift Carousel Track dynamically: 0 -> 0%, 1 -> -25%, 2 -> -50%, 3 -> -75%
    const translatePercent = -(index * (100 / totalScreens));
    const track = el.track || getEl('carousel-track');
    if (track) {
      track.style.transform = `translateX(${translatePercent}%)`;
    }

    // Dynamic Apple Album Gradient on Music (Screen 0)
    const overlay = el.screenBackdropOverlay || getEl('screen-backdrop-overlay');
    if (overlay) {
      if (index === 0) {
        overlay.classList.add('active-music');
      } else {
        overlay.classList.remove('active-music');
      }
    }

    // Update Minimalist Apple Page Dots (0 to 3)
    const dots = [
      el.dotPage0 || getEl('dot-page-0'),
      el.dotPage1 || getEl('dot-page-1'),
      el.dotPage2 || getEl('dot-page-2'),
      el.dotPage3 || getEl('dot-page-3')
    ];
    dots.forEach((dot, i) => {
      if (dot) {
        if (i === index) dot.classList.add('active');
        else dot.classList.remove('active');
      }
    });

    if (index === 2) {
      setTimeout(() => {
        updateCursorPosition();
        updateColorDisplay(aiState.currentHex, hsvToRgb(aiState.currentHue / 360, aiState.currentSat, aiState.currentVal));
        renderRecentIllustratorColors();
        const isRunning = (state.runningApps || []).some(a => typeof a === 'string' && a.toLowerCase().includes('illustrator'));
        if (isRunning) {
          sendMacAction('illustrator_command', { command: 'get_recent_colors' });
        }
      }, 40);
    }

    triggerHaptic();
  }
  window.goToScreen = goToScreen;

  // Vertical Sub-Page Scrolling for Modular Add-ons (e.g. Illustrator with 3 sub-pages)
  function scrollAddonSubPage(containerId, subPageIndex) {
    const rawEl = getEl(containerId);
    if (!rawEl) return;
    const scrollContainer = rawEl.classList.contains('addon-vertical-scroll') ? rawEl : rawEl.querySelector('.addon-vertical-scroll') || rawEl;
    const subPages = (scrollContainer || rawEl).querySelectorAll('.addon-sub-page');
    if (subPageIndex < 0 || subPageIndex >= subPages.length) return;
    
    const targetPage = subPages[subPageIndex];
    if (targetPage) {
      if (typeof scrollContainer.scrollTo === 'function') {
        const topOffset = targetPage.offsetTop || (subPageIndex * scrollContainer.clientHeight);
        scrollContainer.scrollTo({ top: topOffset, behavior: 'smooth' });
      } else {
        targetPage.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
      triggerHaptic();
    }
  }
  window.scrollAddonSubPage = scrollAddonSubPage;

  function initVerticalAddonScrollTracking() {
    const scrollContainers = document.querySelectorAll('.addon-vertical-scroll');
    scrollContainers.forEach(container => {
      const containerId = container.id;
      const indicatorId = containerId.replace('-scroll', '-indicator');
      const indicator = getEl(indicatorId) || (container.parentElement ? container.parentElement.querySelector('.addon-vertical-indicator') : null);
      if (!indicator) return;

      const dots = indicator.querySelectorAll('.addon-vdot');

      container.addEventListener('scroll', () => {
        const scrollTop = container.scrollTop;
        const pageHeight = container.clientHeight || 1;
        const activeIndex = Math.min(dots.length - 1, Math.max(0, Math.round(scrollTop / pageHeight)));

        dots.forEach((dot, i) => {
          if (i === activeIndex) {
            dot.classList.add('active');
          } else {
            dot.classList.remove('active');
          }
        });
      }, { passive: true });
    });
  }

  // Control Center Pull-Down Overlay Controls
  function openControlCenter() {
    const screenCc = getEl('screen-cc');
    const overlay = el.screenBackdropOverlay || getEl('screen-backdrop-overlay');
    const viewport = el.viewport || getEl('carousel-viewport');
    const dots = getEl('screen-page-dots');
    
    if (screenCc) {
      if (document.body.style.backgroundImage) {
        screenCc.style.backgroundImage = document.body.style.backgroundImage;
      }
      screenCc.classList.add('active');
    }
    if (overlay) overlay.classList.add('active-cc');
    if (viewport) viewport.style.opacity = '0';
    if (dots) dots.style.opacity = '0';
    initPhoneBattery();
    triggerHaptic();
  }
  window.openControlCenter = openControlCenter;

  function closeControlCenter() {
    const screenCc = getEl('screen-cc');
    const overlay = el.screenBackdropOverlay || getEl('screen-backdrop-overlay');
    const viewport = el.viewport || getEl('carousel-viewport');
    const dots = getEl('screen-page-dots');

    if (screenCc) screenCc.classList.remove('active');
    if (overlay) overlay.classList.remove('active-cc');
    if (viewport) viewport.style.opacity = '1';
    if (dots) dots.style.opacity = '1';
    triggerHaptic();
  }
  window.closeControlCenter = closeControlCenter;

  function toggleControlCenter() {
    const screenCc = getEl('screen-cc');
    if (screenCc && screenCc.classList.contains('active')) {
      closeControlCenter();
    } else {
      openControlCenter();
    }
  }
  window.toggleControlCenter = toggleControlCenter;

  // Top-Edge Pull-Down Gesture & Horizontal Carousel Swipe Gestures
  function initSwipeGestures() {
    const viewport = el.viewport || getEl('carousel-viewport');
    const screenCc = getEl('screen-cc');
    const ccHandle = document.querySelector('.top-cc-handle-pill');

    let touchStartX = 0;
    let touchStartY = 0;
    let isSwipingCarousel = false;
    let isPullingFromTopEdge = false;
    let isPullingGeneralDown = false;

    // Helper: is target an interactive control where horizontal swipe should NEVER change pages?
    function isInteractiveControl(target) {
      if (!target) return false;
      return !!target.closest(
        '.ai-block-color, .ai-picker-viewport, .color-disc, canvas, ' +
        '#ai-wheel-container, #ai-triangle-ring, #ai-triangle-canvas, #ai-square-container, ' +
        '.ai-swatch-grid-wrapper, #ai-swatch-grid-20, .ai-swatch-grid-10, .ai-swatches-card, ' +
        '.apple-slider-pill, .slider-vertical, .slider-horizontal, .slider-box, .scrubber-container, ' +
        '.ai-recent-color-btn, input, select, textarea, [data-no-swipe="true"]'
      );
    }

    // 1. Global Listener for Pull Down to open Control Center
    window.addEventListener('touchstart', (e) => {
      if (!e.touches || e.touches.length === 0) return;
      const startY = e.touches[0].clientY;
      const startX = e.touches[0].clientX;
      const target = e.target;

      touchStartY = startY;
      touchStartX = startX;

      // Top Edge Zone (Top 95px or 18% screen height or anywhere on top nav / handle)
      const topBoundary = Math.max(95, window.innerHeight * 0.18);
      const isTopNav = !!target.closest('.top-nav-bar, .top-cc-handle-pill, .cc-pull-notch, .battery-shell, .nav-left, .nav-right');

      if (startY <= topBoundary || isTopNav) {
        isPullingFromTopEdge = true;
        isPullingGeneralDown = false;
      } else if (startY < window.innerHeight * 0.35 && !isInteractiveControl(target)) {
        // Upper zone general pull-down (outside interactive components)
        isPullingFromTopEdge = false;
        isPullingGeneralDown = true;
      } else {
        isPullingFromTopEdge = false;
        isPullingGeneralDown = false;
      }
    }, { passive: true });

    window.addEventListener('touchmove', (e) => {
      if ((!isPullingFromTopEdge && !isPullingGeneralDown) || !e.touches || e.touches.length === 0) return;
      const currentY = e.touches[0].clientY;
      const currentX = e.touches[0].clientX;
      const deltaY = currentY - touchStartY;
      const deltaX = Math.abs(currentX - touchStartX);

      // Trigger Control Center open when pulled down
      if (isPullingFromTopEdge) {
        // Highly responsive, natural downward swipe from top edge (22px)
        if (deltaY > 22 && deltaY > deltaX * 0.5) {
          isPullingFromTopEdge = false;
          triggerHaptic();
          openControlCenter();
        }
      } else if (isPullingGeneralDown) {
        // Upper screen downward pull
        if (deltaY > 45 && deltaY > deltaX * 1.3) {
          isPullingGeneralDown = false;
          triggerHaptic();
          openControlCenter();
        }
      }
    }, { passive: true });

    window.addEventListener('touchend', () => {
      isPullingFromTopEdge = false;
      isPullingGeneralDown = false;
    }, { passive: true });

    window.addEventListener('touchcancel', () => {
      isPullingFromTopEdge = false;
      isPullingGeneralDown = false;
    }, { passive: true });

    // Click/tap on top handle directly toggles Control Center
    if (ccHandle) {
      ccHandle.addEventListener('click', (e) => {
        e.stopPropagation();
        triggerHaptic();
        toggleControlCenter();
      });
    }

    // 2. Control Center Dismiss Gesture (Swipe Up from inside Control Center)
    if (screenCc) {
      let ccStartY = 0;
      let ccStartX = 0;
      screenCc.addEventListener('touchstart', (e) => {
        if (e.touches && e.touches.length > 0) {
          ccStartY = e.touches[0].clientY;
          ccStartX = e.touches[0].clientX;
        }
      }, { passive: true });

      screenCc.addEventListener('touchmove', (e) => {
        if (!e.touches || e.touches.length === 0) return;
        const currentY = e.touches[0].clientY;
        const currentX = e.touches[0].clientX;
        const deltaY = currentY - ccStartY;
        const deltaX = Math.abs(currentX - ccStartX);
        if (deltaY < -24 && Math.abs(deltaY) > deltaX * 0.6) {
          triggerHaptic();
          closeControlCenter();
        }
      }, { passive: true });
    }

    // 3. Carousel Horizontal Swipe (Between Screens 0, 1, 2, 3)
    if (viewport) {
      let carouselStartX = 0;
      let carouselStartY = 0;

      viewport.addEventListener('touchstart', (e) => {
        if (!e.touches || e.touches.length === 0) return;

        // Never allow carousel swipe if user is interacting with color picker or sliders
        if (isInteractingWithColorPicker || isDraggingBrightness || isDraggingVolume) {
          isSwipingCarousel = false;
          return;
        }

        // Never allow carousel swipe if touch started on any interactive control:
        // Color picker, swatches, wheel, triangle, square, sliders, inputs, etc.
        if (isInteractiveControl(e.target)) {
          isSwipingCarousel = false;
          return;
        }

        carouselStartX = e.touches[0].clientX;
        carouselStartY = e.touches[0].clientY;

        // Don't swipe carousel if starting near top edge (reserved for Control Center)
        const topBoundary = Math.max(90, window.innerHeight * 0.18);
        if (carouselStartY > topBoundary) {
          isSwipingCarousel = true;
        } else {
          isSwipingCarousel = false;
        }
      }, { passive: true });

      viewport.addEventListener('touchmove', (e) => {
        if (!isSwipingCarousel || !e.touches || e.touches.length === 0) return;
        // If color picker or slider interaction started while moving, abort carousel swipe immediately
        if (isInteractingWithColorPicker || isDraggingBrightness || isDraggingVolume) {
          isSwipingCarousel = false;
          return;
        }
      }, { passive: true });

      viewport.addEventListener('touchend', (e) => {
        if (!isSwipingCarousel || isInteractingWithColorPicker || !e.changedTouches || e.changedTouches.length === 0) {
          isSwipingCarousel = false;
          return;
        }
        isSwipingCarousel = false;

        const touchEndX = e.changedTouches[0].clientX;
        const touchEndY = e.changedTouches[0].clientY;
        const deltaX = touchEndX - carouselStartX;
        const deltaY = touchEndY - carouselStartY;

        // Ensure horizontal drag is dominant and deliberate (minimum 70px)
        if (Math.abs(deltaX) > Math.abs(deltaY) * 1.5 && Math.abs(deltaX) > 70) {
          const screens = document.querySelectorAll('.carousel-screen');
          const totalScreens = Math.max(screens.length, 6);
          if (deltaX < 0) {
            // Drag Left -> Move to Next Screen
            if (state.currentScreen < totalScreens - 1) goToScreen(state.currentScreen + 1);
          } else {
            // Drag Right -> Move to Previous Screen
            if (state.currentScreen > 0) goToScreen(state.currentScreen - 1);
          }
        }
      }, { passive: true });
    }

    // 4. Touch isolation on Color Picker and Swatches
    const colorBlocks = document.querySelectorAll('.ai-block-color, .ai-swatch-grid-wrapper, #ai-wheel-container, #ai-triangle-ring, #ai-triangle-canvas, #ai-square-container');
    colorBlocks.forEach((block) => {
      block.addEventListener('touchstart', () => {
        isInteractingWithColorPicker = true;
        isSwipingCarousel = false;
      }, { passive: true });
      block.addEventListener('touchmove', () => {
        isInteractingWithColorPicker = true;
        isSwipingCarousel = false;
      }, { passive: true });
      block.addEventListener('touchend', () => {
        setTimeout(() => { isInteractingWithColorPicker = false; }, 150);
      }, { passive: true });
      block.addEventListener('touchcancel', () => {
        setTimeout(() => { isInteractingWithColorPicker = false; }, 150);
      }, { passive: true });
    });
  }

  // Haptic Feedback Helper
  function triggerHaptic() {
    if (window.AndroidBridge && window.AndroidBridge.performHapticFeedback) {
      window.AndroidBridge.performHapticFeedback();
    } else if (navigator.vibrate) {
      navigator.vibrate(10);
    }
  }

  // Toast Helper
  function showToast(msg) {
    if (!msg) return;
    const lower = String(msg).toLowerCase();
    // Silenciar notificações de conexão e cores conforme solicitado
    if (lower.includes('conectad') || lower.includes('conex') || lower.includes('offline') || lower.includes('desconectad')) return;
    if (lower.includes('cor') || lower.includes('cores') || lower.includes('amostra') || lower.includes('preenchimento') || lower.includes('traçado') || lower.includes('copiado') || lower.includes('swatch')) return;

    const toast = el.toast || getEl('toast-bubble');
    if (!toast) return;
    toast.textContent = msg;
    toast.classList.add('show');
    setTimeout(() => {
      toast.classList.remove('show');
    }, 2000);
  }

  // ==========================================================================
  // 2. Ultra-Low Latency WebSocket Client
  // ==========================================================================
  function connectWebSocket(customIp, customPort) {
    if (customIp) state.macIp = customIp;
    if (customPort) state.macPort = customPort;

    if (window.AndroidBridge && (state.macIp === '127.0.0.1' || state.macIp === 'localhost')) {
      state.macIp = '192.168.1.6';
    }

    localStorage.setItem('mac_touchbar_ip', state.macIp);
    localStorage.setItem('mac_touchbar_port', state.macPort);

    if (window.AndroidBridge && window.AndroidBridge.saveIp) {
      window.AndroidBridge.saveIp(state.macIp);
    }

    // In Android APK, the native OkHttp TouchbarClient manages connection & forwards telemetry
    if (window.AndroidBridge) {
      return;
    }

    if (state.ws) {
      try { state.ws.close(); } catch (e) {}
      state.ws = null;
    }

    state.connecting = true;
    updateConnectionUI('connecting');

    const wsUrl = `ws://${state.macIp}:${state.macPort}`;
    console.log('[TouchBar] Conectando a:', wsUrl);

    try {
      state.ws = new WebSocket(wsUrl);

      state.ws.onopen = function () {
        console.log('[TouchBar] Conectado ao Mac com sucesso!');
        state.connected = true;
        state.connecting = false;
        updateConnectionUI('connected');
        const modal = el.modalConn || getEl('modal-conn-setup');
        if (modal) modal.classList.remove('active');

        sendMacAction('get_status', {});
        startHeartbeat();
      };

      state.ws.onmessage = function (event) {
        try {
          const data = JSON.parse(event.data);
          handleServerMessage(data);
        } catch (e) {
          console.error('Erro ao processar mensagem:', e);
        }
      };

      state.ws.onerror = function (e) {
        console.warn('Erro no WebSocket:', e);
      };

      state.ws.onclose = function () {
        state.connected = false;
        state.connecting = false;
        updateConnectionUI('disconnected');
        stopHeartbeat();
        scheduleReconnect();
      };
    } catch (e) {
      state.connected = false;
      state.connecting = false;
      updateConnectionUI('disconnected');
      scheduleReconnect();
    }
  }

  let reconnectAttempts = 0;
  function scheduleReconnect() {
    if (state.reconnectTimer) clearTimeout(state.reconnectTimer);
    state.reconnectTimer = setTimeout(() => {
      if (!state.connected && !window.AndroidBridge) {
        reconnectAttempts++;
        // Fallback strategy: alternate every 3 attempts to USB tether (127.0.0.1) if on remote IP
        if (reconnectAttempts % 4 === 0 && state.macIp !== '127.0.0.1') {
          console.log('[TouchBar] Tentando fallback via túnel USB (127.0.0.1)...');
          connectWebSocket('127.0.0.1', state.macPort);
        } else {
          const cachedIp = localStorage.getItem('mac_touchbar_ip') || state.macIp;
          connectWebSocket(cachedIp, state.macPort);
        }
      }
    }, 2000);
  }

  function startHeartbeat() {
    stopHeartbeat();
    state.heartbeatTimer = setInterval(() => {
      if (state.connected && state.ws && state.ws.readyState === WebSocket.OPEN) {
        sendMacAction('get_status', {});
      }
    }, 4000);
  }

  function stopHeartbeat() {
    if (state.heartbeatTimer) clearInterval(state.heartbeatTimer);
    state.heartbeatTimer = null;
  }

  // Send Action to Mac with Zero Overhead & Smart Debouncing
  let lastActionTime = 0;
  const ACTION_COOLDOWN_MS = 300;

  function sendMacAction(action, params = {}) {
    const now = Date.now();
    // Prevent double invocation from touch+click or rapid spamming
    if (action.startsWith('media_') || action === 'toggle_favorite') {
      if (now - lastActionTime < ACTION_COOLDOWN_MS) {
        return;
      }
      lastActionTime = now;
    }

    triggerHaptic();

    // User feedback for shortcuts
    if (action === 'system_command') {
      const cmd = params.command || '';
      if (cmd === 'screenshot_area') showToast('Captura de Área (⌘4)');
      else if (cmd === 'screen_record') showToast('Gravação de Tela (⌘5)');
      else if (cmd === 'show_desktop') showToast('Mostrar Mesa (F11)');
      else if (cmd === 'lock_screen') showToast('Bloquear Mac (⌃⌘Q)');
      else if (cmd === 'restart_mac') showToast('Reiniciando Mac...');
      else if (cmd === 'shutdown_mac') showToast('⏻ Desligando Mac...');
      else if (cmd === 'shazam_recognize') showToast('Shazam: Ouvindo...');
      else if (cmd === 'toggle_wifi') showToast('Wi-Fi');
      else if (cmd === 'toggle_bluetooth') showToast('Bluetooth');
      else if (cmd === 'toggle_airdrop') showToast('AirDrop');
    } else if (action === 'illustrator_command') {
      const c = params.command || '';
      if (c === 'new') {
        showToast('Novo Documento (⌘N)');
        sendMacAction('send_hotkey', {key: 'n', modifiers: ['command']});
      } else if (c === 'open') {
        showToast('Abrir Documento (⌘O)');
        sendMacAction('send_hotkey', {key: 'o', modifiers: ['command']});
      } else if (c === 'artboard' || c === 'prancheta') {
        showToast('Ferramenta Prancheta (O)');
        sendMacAction('send_hotkey', {key: 'o', modifiers: ['shift']});
      } else if (c === 'save') showToast('Salvando no Illustrator...');
      else if (c === 'saveas') showToast('Salvar Como...');
      else if (c === 'align_center_artboard' || c === 'align_artboard_center') {
        showToast('Centro da Prancheta');
        sendMacAction('illustrator_command', {command: 'align horizontal center'});
        setTimeout(() => {
          sendMacAction('illustrator_command', {command: 'Vertical Align Center'});
        }, 80);
      }
      else if (c.includes('align left') || c === 'align_obj_left' || c === 'align_left') showToast('Alinhar à Esquerda');
      else if (c.includes('horizontal center') || c === 'align_obj_center' || c === 'align_center_h') showToast('Alinhar ao Centro');
      else if (c.includes('align right') || c === 'align_obj_right' || c === 'align_right') showToast('Alinhar à Direita');
      else if (c.includes('Top') || c === 'align top' || c === 'align_top') showToast('Alinhar ao Topo');
      else if (c.includes('Vertical Align Center') || c === 'align vertical center' || c === 'align_center_v') showToast('Alinhar ao Meio');
      else if (c.includes('Bottom') || c === 'align bottom' || c === 'align_bottom') showToast('Alinhar à Base');
      else if (c === 'distribute_h') showToast('Distribuir Espaçamento H');
      else if (c === 'distribute_v') showToast('Distribuir Espaçamento V');
      else if (c === 'bringToFront') showToast('⏫ Trazer para Frente');
      else if (c === 'sendToBack') showToast('⏬ Enviar para Trás');
      else if (c === 'group') {
        showToast('Agrupar Objetos (⌘G)');
        sendMacAction('send_hotkey', {key: 'g', modifiers: ['command']});
      } else if (c === 'ungroup') {
        showToast('Desagrupar Objetos (⌘G)');
        sendMacAction('send_hotkey', {key: 'g', modifiers: ['shift', 'command']});
      } else if (c.includes('Unite') || c === 'unite') showToast('Pathfinder: Unir');
      else if (c.includes('Minus Front') || c === 'minus_front') showToast('Pathfinder: Menos Frente');
      else if (c.includes('Intersect') || c === 'intersect') showToast('Pathfinder: Intersecção');
      else if (c.includes('Exclude') || c === 'exclude') showToast('Pathfinder: Excluir');
      else if (c.includes('Divide') || c === 'divide') showToast('Pathfinder: Dividir');
      else if (c === 'trim') showToast('Pathfinder: Cortar');
      else if (c === 'pen') {
        showToast('Caneta Bézier (P)');
        sendMacAction('send_hotkey', {key: 'p'});
      } else if (c === 'direct_select') {
        showToast('Seleção Direta (A)');
        sendMacAction('send_hotkey', {key: 'a'});
      } else if (c === 'select') {
        showToast('Seleção Principal (V)');
        sendMacAction('send_hotkey', {key: 'v'});
      } else if (c === 'add_anchor') showToast('Adicionar Ponto de Âncora');
      else if (c === 'convert_smooth') showToast('Ponto Suave (Curva)');
      else if (c === 'convert_corner') showToast('Ponto em Canto Reto');
      else if (c === 'scissors') {
        showToast('Tesoura: Cortar Caminho (C)');
        sendMacAction('send_hotkey', {key: 'c'});
      } else if (c === 'join_paths') {
        showToast('Juntar Caminhos (⌘J)');
        sendMacAction('send_hotkey', {key: 'j', modifiers: ['command']});
      } else if (c === 'outline_stroke') showToast('Traçado em Contorno');
      else if (c === 'font_size_up') showToast('A+ Aumentar Fonte (⌘>)');
      else if (c === 'font_size_down') showToast('A- Diminuir Fonte (⌘<)');
      else if (c === 'leading_up') showToast('+ Aumentar Entrelinha');
      else if (c === 'leading_down') showToast('- Diminuir Entrelinha');
      else if (c === 'all_caps') showToast('Todas Maiúsculas (TT)');
      else if (c === 'small_caps') showToast('Versaletes (Tt)');
    } else if (action === 'photoshop_command') {
      const c = params.command || '';
      if (c === 'frequency_separation') showToast('Separação de Frequências (Alta/Baixa)');
      else if (c === 'dodge_burn') showToast('Dodge & Burn Dinâmico');
      else if (c === 'spot_healing') {
        showToast('Pincel de Recuperação (J)');
        sendMacAction('send_hotkey', {key: 'j'});
      } else if (c === 'clone_stamp') {
        showToast('Carimbo de Clone (S)');
        sendMacAction('send_hotkey', {key: 's'});
      } else if (c === 'gaussian_blur') showToast('Desfoque Gaussiano');
      else if (c === 'patch_tool') showToast('Ferramenta Correção');
      else if (c === 'blend_normal') {
        showToast('Modo: Normal (⌥N)');
        sendMacAction('send_hotkey', {key: 'n', modifiers: ['option', 'shift']});
      } else if (c === 'blend_multiply') {
        showToast('Modo: Multiplicação (⌥M)');
        sendMacAction('send_hotkey', {key: 'm', modifiers: ['option', 'shift']});
      } else if (c === 'blend_screen') {
        showToast('Modo: Divisão / Screen (⌥S)');
        sendMacAction('send_hotkey', {key: 's', modifiers: ['option', 'shift']});
      } else if (c === 'blend_overlay') {
        showToast('Modo: Sobrepor / Overlay (⌥O)');
        sendMacAction('send_hotkey', {key: 'o', modifiers: ['option', 'shift']});
      } else if (c === 'blend_soft_light') {
        showToast('Modo: Luz Suave (⌥F)');
        sendMacAction('send_hotkey', {key: 'f', modifiers: ['option', 'shift']});
      } else if (c === 'new_layer') {
        showToast('Nova Camada (⌘N)');
        sendMacAction('send_hotkey', {key: 'n', modifiers: ['shift', 'command']});
      } else if (c === 'layer_mask') showToast('Adicionar Máscara de Camada');
      else if (c === 'smart_object') showToast('Converter em Smart Object');
      else if (c === 'stamp_visible') {
        showToast('Carimbar Camadas Visíveis (⌥⌘E)');
        sendMacAction('send_hotkey', {key: 'e', modifiers: ['shift', 'option', 'command']});
      } else if (c === 'duplicate_layer') {
        showToast('Duplicar Camada (⌘J)');
        sendMacAction('send_hotkey', {key: 'j', modifiers: ['command']});
      } else if (c === 'rasterize') showToast('Rasterizar Camada');
      else if (c === 'select_subject') showToast('IA: Selecionar Assunto');
      else if (c === 'remove_background') showToast('IA: Remover Fundo');
      else if (c === 'select_sky') showToast('IA: Selecionar Céu');
      else if (c === 'refine_hair') showToast('Refinar Cabelo & Borda');
      else if (c === 'quick_mask') {
        showToast('Alternar Máscara Rápida (Q)');
        sendMacAction('send_hotkey', {key: 'q'});
      } else if (c === 'invert_mask') {
        showToast('Inverter Máscara / Cores (⌘I)');
        sendMacAction('send_hotkey', {key: 'i', modifiers: ['command']});
      } else if (c === 'deselect') {
        showToast('Desmarcar Seleção (⌘D)');
        sendMacAction('send_hotkey', {key: 'd', modifiers: ['command']});
      } else if (c === 'inverse_selection') {
        showToast('Inverter Seleção (⌘I)');
        sendMacAction('send_hotkey', {key: 'i', modifiers: ['shift', 'command']});
      } else if (c === 'curves') {
        showToast('Curvas (⌘M)');
        sendMacAction('send_hotkey', {key: 'm', modifiers: ['command']});
      } else if (c === 'levels') {
        showToast('Níveis (⌘L)');
        sendMacAction('send_hotkey', {key: 'l', modifiers: ['command']});
      } else if (c === 'hue_saturation') {
        showToast('Matiz / Saturação (⌘U)');
        sendMacAction('send_hotkey', {key: 'u', modifiers: ['command']});
      } else if (c === 'camera_raw') {
        showToast('Filtro Camera Raw (⌘A)');
        sendMacAction('send_hotkey', {key: 'a', modifiers: ['shift', 'command']});
      } else if (c === 'color_balance') {
        showToast('Balanço de Cores (⌘B)');
        sendMacAction('send_hotkey', {key: 'b', modifiers: ['command']});
      } else if (c === 'black_and_white') {
        showToast('Preto e Branco (⌥⌘B)');
        sendMacAction('send_hotkey', {key: 'b', modifiers: ['option', 'shift', 'command']});
      } else if (c === 'auto_tone') {
        showToast('Auto Tom (⌘L)');
        sendMacAction('send_hotkey', {key: 'l', modifiers: ['shift', 'command']});
      } else if (c === 'auto_contrast') {
        showToast('Auto Contraste (⌥⌘L)');
        sendMacAction('send_hotkey', {key: 'l', modifiers: ['option', 'shift', 'command']});
      }
    }

    // Optimistic UI updates
    if (action === 'media_play_pause') {
      const isCurrentlyPlaying = state.media && state.media.state === 'playing';
      const nextState = isCurrentlyPlaying ? 'paused' : 'playing';
      if (state.media) state.media.state = nextState;
      if (typeof lastKnownMedia !== 'undefined' && lastKnownMedia) {
        lastKnownMedia.state = nextState;
      }
      const glyph = el.glyphPlay || getEl('glyph-play');
      if (glyph) {
        glyph.innerHTML = nextState === 'playing' ?
          '<svg viewBox="0 0 24 24" width="42" height="42" fill="currentColor"><rect x="6" y="4" width="4" height="16" rx="1.5"/><rect x="14" y="4" width="4" height="16" rx="1.5"/></svg>' :
          '<svg viewBox="0 0 24 24" width="42" height="42" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>';
      }
      if (nextState === 'playing') {
        startScrubberTicker();
      } else {
        if (scrubberTimer) clearInterval(scrubberTimer);
      }
    } else if (action === 'toggle_favorite') {
      const favBtn = el.btnMusicFav || getEl('btn-music-fav');
      if (favBtn) favBtn.classList.toggle('favorited');
    }

    const payload = JSON.stringify({ action: action, params: params });

    // Send via Android Bridge if available, otherwise native WebSocket (NEVER duplicate!)
    if (window.AndroidBridge && window.AndroidBridge.sendMacAction) {
      window.AndroidBridge.sendMacAction(payload);
    } else if (state.connected && state.ws && state.ws.readyState === WebSocket.OPEN) {
      state.ws.send(payload);
    }
  }
  window.sendMacAction = sendMacAction;

  // Handle Server Message
  function handleServerMessage(data) {
    if (data.type === 'status_update') {
      if (data.cpu_percent !== undefined) {
        const cpuEl = getEl('cockpit-cpu-val');
        if (cpuEl) cpuEl.textContent = `${Math.round(data.cpu_percent)}%`;
      }
      if (data.ram_percent !== undefined) {
        const ramEl = getEl('cockpit-ram-val');
        if (ramEl) ramEl.textContent = `${Math.round(data.ram_percent)}%`;
      }
      if (typeof data.volume === 'number') {
        if (!isDraggingVolume && (Date.now() - lastUserVolTime > 2000)) {
          state.volume = data.volume;
          updateVolumeUI(state.volume);
        }
      }
      if (typeof data.brightness === 'number') {
        if (!isDraggingBrightness && (Date.now() - lastUserBrightTime > 2000)) {
          state.brightness = data.brightness;
          updateBrightnessUI(state.brightness);
        }
      }
      if (data.battery) {
        updateBatteryUI(data.battery);
      }
      if (data.airpods) {
        updateAirPodsUI(data.airpods);
      }
      if (data.media) {
        state.media = data.media;
        updateMediaUI(data.media);
      }
      if (Array.isArray(data.running_apps)) {
        updateRunningDots(data.running_apps);
      }
      // Check for Adobe Illustrator presence & contextual badge
      const front = (data.frontmost_app || '').toLowerCase();
      const isAiFront = front.includes('illustrator');
      const isAiRunning = isAppRunningCheck({ id: 'illustrator', label: 'Illustrator' }, data.running_apps);
      
      const aiBadge = getEl('nav-illustrator-badge');
      if (aiBadge) {
        if (isAiRunning || isAiFront) {
          aiBadge.classList.remove('hidden');
        } else {
          aiBadge.classList.add('hidden');
        }
      }

      // Illustrator status tracking (DO NOT auto-open: only open when user clicks shortcut)
      aiState.lastFrontApp = front;
      if (!isAiFront) {
        aiState.userDismissedThisSession = false;
      }
      if (data.wallpaperBase64 && data.wallpaperBase64.length > 50) {
        setGlobalWallpaper(`url(data:image/jpeg;base64,${data.wallpaperBase64})`);
      }
    } else if (data.type === 'deck_config_update') {
      if (data.rows && data.cols) {
        state.deckRows = data.rows;
        state.deckCols = data.cols;
        const grid = el.deckGrid || getEl('deck-grid');
        if (grid) {
          grid.style.gridTemplateColumns = `repeat(${data.cols}, 1fr)`;
          grid.style.gridTemplateRows = `repeat(${data.rows}, 1fr)`;
        }
      }
      if (Array.isArray(data.buttons) && data.buttons.length > 0) {
        state.buttons = data.buttons;
        renderDeckButtons(state.buttons);
      }
    } else if (data.type === 'wallpaper_update') {
      if (data.wallpaperBase64 && data.wallpaperBase64.length > 50) {
        setGlobalWallpaper(`url(data:image/jpeg;base64,${data.wallpaperBase64})`);
        console.log('[TouchBar] Papel de parede sincronizado com o Mac');
      }
    } else if (data.type === 'illustrator_recent_colors' && Array.isArray(data.colors)) {
      if (typeof handleImportedAiColors === 'function') {
        handleImportedAiColors(data.colors);
      }
    } else if (data.type === 'toast' && data.message) {
      showToast(data.message);
    }
  }

  // Native Android Bridge Listeners
  window.onMacConnected = function (ip, name) {
    console.log('[Bridge] Conectado ao Mac:', ip, name);
    state.connected = true;
    state.connecting = false;
    state.macIp = ip;
    updateConnectionUI('connected');
    sendMacAction('get_status', {});
  };

  window.onMacDisconnected = function () {
    console.log('[Bridge] Desconectado do Mac');
    state.connected = false;
    state.connecting = false;
    updateConnectionUI('disconnected');
    stopHeartbeat();
  };

  window.onMacDiscovered = function (ip) {
    console.log('[Bridge] Mac descoberto no IP:', ip);
    if (ip && ip !== state.macIp) {
      state.macIp = ip;
      if (window.AndroidBridge && window.AndroidBridge.connectToMac) {
        window.AndroidBridge.connectToMac(ip);
      } else {
        connectWebSocket(ip, state.macPort);
      }
    }
  };

  window.onMacStateUpdate = function (jsonStr) {
    try {
      const data = typeof jsonStr === 'string' ? JSON.parse(jsonStr) : jsonStr;
      if (data) {
        if (!state.connected) {
          state.connected = true;
          state.connecting = false;
          updateConnectionUI('connected');
        }
        handleServerMessage(data);
      }
    } catch (e) {
      console.error('[Bridge] Erro ao processar mensagem do Mac:', e);
    }
  };

  // ==========================================================================
  // 3. UI Updating & Rendering
  // ==========================================================================
  function updateConnectionUI(status) {
    const dot = el.cameraLedDot || getEl('camera-led-dot');
    if (dot) {
      dot.className = 'camera-led-dot';
      if (status === 'connected') {
        dot.classList.add('connected');
        dot.title = `Mac Conectado (${state.macIp})`;
      } else if (status === 'connecting') {
        dot.classList.add('connecting');
        dot.title = `Conectando (${state.macIp})...`;
      } else {
        dot.title = `Mac Offline (${state.macIp})`;
      }
    }
  }

  function updateVolumeUI(val) {
    const fillV = el.sliderFillVolume || getEl('slider-fill-volume');
    if (fillV) fillV.style.height = `${val}%`;
    const fillH = el.musicVolFill || getEl('music-vol-fill');
    if (fillH) fillH.style.width = `${val}%`;
  }

  function updateBrightnessUI(val) {
    const fillB = el.sliderFillBrightness || getEl('slider-fill-brightness');
    if (fillB) fillB.style.height = `${val}%`;
  }

  // ==========================================================================
  // Apple 4-Ring Battery Widget (Imagem 2: Celular + AirPods L + AirPods R + Estojo)
  // ==========================================================================
  const RING_CIRCUMFERENCE = 131.95;

  function updatePhoneBatteryUI(pct, isCharging) {
    const p = Math.max(0, Math.min(100, typeof pct === 'number' ? Math.round(pct) : 100));
    const fill = el.ringFillPhone || getEl('cc-ring-fill-phone');
    const label = el.ringPctPhone || getEl('cc-ring-pct-phone');
    const bolt = el.ringBoltPhone || getEl('cc-ring-bolt-phone');
    const navBat = el.navBatteryLevel || getEl('nav-battery-level');

    if (fill) {
      fill.style.strokeDashoffset = RING_CIRCUMFERENCE * (1 - p / 100);
      fill.style.stroke = p <= 10 ? 'var(--apple-red)' : (p <= 20 ? 'var(--apple-orange)' : 'var(--apple-green)');
    }
    if (label) {
      label.textContent = `${p}%`;
    }
    if (bolt) {
      bolt.style.opacity = isCharging ? '1' : '0';
    }
    if (navBat) {
      navBat.style.width = `${p}%`;
      navBat.style.background = p <= 20 ? 'var(--apple-red)' : (p <= 40 ? 'var(--apple-orange)' : 'var(--apple-green)');
    }
  }

  function initPhoneBattery() {
    // 1. Native Android Bridge
    if (window.AndroidBridge && window.AndroidBridge.getDeviceBattery) {
      try {
        const raw = window.AndroidBridge.getDeviceBattery();
        const data = JSON.parse(raw);
        updatePhoneBatteryUI(data.level, data.charging);
      } catch (e) {
        console.warn('Native battery error', e);
      }
    }
    // 2. Web Battery API
    if (navigator.getBattery) {
      navigator.getBattery().then(function(battery) {
        function sync() {
          const level = Math.round(battery.level * 100);
          const isCharging = battery.charging;
          updatePhoneBatteryUI(level, isCharging);
        }
        sync();
        battery.addEventListener('levelchange', sync);
        battery.addEventListener('chargingchange', sync);
      }).catch(function(err) {
        console.log('Web Battery API not available', err);
      });
    }
  }
  window.onPhoneBatteryUpdate = function(level, isCharging) {
    updatePhoneBatteryUI(level, isCharging);
  };

  function updateBatteryUI(battery) {
    if (!battery) return;
    if (typeof battery.phone_percent === 'number') {
      updatePhoneBatteryUI(battery.phone_percent, !!battery.phone_charging);
    }
  }

  function updateAirPodsUI(airpods) {
    if (!airpods) return;
    const isConn = !!airpods.connected;
    const leftPct = typeof airpods.left === 'number' ? Math.round(airpods.left) : 100;
    const rightPct = typeof airpods.right === 'number' ? Math.round(airpods.right) : 100;
    const casePct = typeof airpods.case === 'number' ? Math.round(airpods.case) : 90;
    const isCaseCharging = !!airpods.case_charging;

    // 1. Left
    const fillLeft = el.ringFillLeft || getEl('cc-ring-fill-left');
    const labelLeft = el.ringPctLeft || getEl('cc-ring-pct-left');
    if (fillLeft) {
      fillLeft.style.strokeDashoffset = isConn ? RING_CIRCUMFERENCE * (1 - leftPct / 100) : RING_CIRCUMFERENCE;
      fillLeft.style.stroke = leftPct <= 10 ? 'var(--apple-red)' : (leftPct <= 20 ? 'var(--apple-orange)' : 'var(--apple-green)');
    }
    if (labelLeft) {
      labelLeft.textContent = isConn ? `${leftPct}%` : '—';
    }

    // 2. Right
    const fillRight = el.ringFillRight || getEl('cc-ring-fill-right');
    const labelRight = el.ringPctRight || getEl('cc-ring-pct-right');
    if (fillRight) {
      fillRight.style.strokeDashoffset = isConn ? RING_CIRCUMFERENCE * (1 - rightPct / 100) : RING_CIRCUMFERENCE;
      fillRight.style.stroke = rightPct <= 10 ? 'var(--apple-red)' : (rightPct <= 20 ? 'var(--apple-orange)' : 'var(--apple-green)');
    }
    if (labelRight) {
      labelRight.textContent = isConn ? `${rightPct}%` : '—';
    }

    // 3. Case
    const fillCase = el.ringFillCase || getEl('cc-ring-fill-case');
    const labelCase = getEl('cc-ring-pct-case');
    const boltCase = el.ringBoltCase || getEl('cc-ring-bolt-case');
    if (fillCase) {
      fillCase.style.strokeDashoffset = isConn ? RING_CIRCUMFERENCE * (1 - casePct / 100) : RING_CIRCUMFERENCE;
      fillCase.style.stroke = casePct <= 10 ? 'var(--apple-red)' : (casePct <= 20 ? 'var(--apple-orange)' : 'var(--apple-green)');
    }
    if (labelCase) {
      labelCase.textContent = isConn ? `${casePct}%` : '—';
    }
    if (boltCase) {
      boltCase.style.opacity = isConn && isCaseCharging ? '1' : '0';
    }
  }

  // ==========================================================================
  // Music & Artwork Color Extraction Engine
  // ==========================================================================
  function formatTime(seconds) {
    if (!seconds || isNaN(seconds) || seconds < 0) return '0:00';
    const m = Math.floor(seconds / 60);
    const s = Math.floor(seconds % 60);
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  }

  function formatRemaining(seconds) {
    if (!seconds || isNaN(seconds) || seconds < 0) return '-0:00';
    const m = Math.floor(seconds / 60);
    const s = Math.floor(seconds % 60);
    return `-${m}:${s < 10 ? '0' : ''}${s}`;
  }

  function extractDominantColorAndApply(imgEl) {
    try {
      const canvas = document.createElement('canvas');
      const ctx = canvas.getContext('2d');
      canvas.width = 48;
      canvas.height = 48;
      ctx.drawImage(imgEl, 0, 0, 48, 48);
      const imgData = ctx.getImageData(0, 0, 48, 48).data;

      const candidates = [];
      let totalR = 0, totalG = 0, totalB = 0, count = 0;

      for (let i = 0; i < imgData.length; i += 16) {
        const cr = imgData[i];
        const cg = imgData[i + 1];
        const cb = imgData[i + 2];
        const max = Math.max(cr, cg, cb);
        const min = Math.min(cr, cg, cb);
        const sat = max === 0 ? 0 : (max - min) / max;
        const bri = max / 255;

        if (sat > 0.16 && bri > 0.14 && bri < 0.92) {
          const score = sat * 1.6 + (1 - Math.abs(bri - 0.55));
          candidates.push({ r: cr, g: cg, b: cb, score, sat, bri });
        }
        totalR += cr; totalG += cg; totalB += cb; count++;
      }

      candidates.sort((a, b) => b.score - a.score);

      let p = { r: 50, g: 75, b: 125 };
      let s = { r: 24, g: 38, b: 64 };
      let d = { r: 10, g: 15, b: 26 };

      if (candidates.length > 0) {
        p = candidates[0];
        const secondCand = candidates.find(c => {
          const dist = Math.abs(c.r - p.r) + Math.abs(c.g - p.g) + Math.abs(c.b - p.b);
          return dist > 55;
        });
        if (secondCand) {
          s = secondCand;
        } else {
          s = {
            r: Math.max(12, Math.round(p.r * 0.55)),
            g: Math.max(14, Math.round(p.g * 0.55)),
            b: Math.max(22, Math.round(p.b * 0.55))
          };
        }
        d = {
          r: Math.max(6, Math.round(p.r * 0.2)),
          g: Math.max(8, Math.round(p.g * 0.2)),
          b: Math.max(14, Math.round(p.b * 0.25))
        };
      } else if (count > 0) {
        const avgR = Math.round(totalR / count);
        const avgG = Math.round(totalG / count);
        const avgB = Math.round(totalB / count);
        p = { r: avgR, g: avgG, b: avgB };
        s = { r: Math.round(avgR * 0.5), g: Math.round(avgG * 0.5), b: Math.round(avgB * 0.5) };
        d = { r: Math.round(avgR * 0.2), g: Math.round(avgG * 0.2), b: Math.round(avgB * 0.2) };
      }

      const root = document.documentElement;
      root.style.setProperty('--m-r1', p.r);
      root.style.setProperty('--m-g1', p.g);
      root.style.setProperty('--m-b1', p.b);
      root.style.setProperty('--m-r2', s.r);
      root.style.setProperty('--m-g2', s.g);
      root.style.setProperty('--m-b2', s.b);
      root.style.setProperty('--m-r3', d.r);
      root.style.setProperty('--m-g3', d.g);
      root.style.setProperty('--m-b3', d.b);

      const c1 = `rgb(${p.r}, ${p.g}, ${p.b})`;
      const c2 = `rgb(${s.r}, ${s.g}, ${s.b})`;
      const c3 = `rgb(${d.r}, ${d.g}, ${d.b})`;
      const glow = `rgba(${p.r}, ${p.g}, ${p.b}, 0.5)`;

      root.style.setProperty('--music-accent-1', c1);
      root.style.setProperty('--music-accent-2', c2);
      root.style.setProperty('--music-accent-3', c3);
      root.style.setProperty('--music-glow', glow);

      const container = el.musicScreenContainer || getEl('music-screen-container');
      if (container) {
        container.style.setProperty('--music-accent-1', c1);
        container.style.setProperty('--music-accent-2', c2);
        container.style.setProperty('--music-accent-3', c3);
        container.style.setProperty('--music-glow', glow);
      }
    } catch (e) {
      console.warn('Could not extract color:', e);
    }
  }

  function updateScrubberUI(pos, dur) {
    const elElapsed = el.musicTimeElapsed || getEl('music-time-elapsed');
    if (elElapsed) elElapsed.textContent = formatTime(pos);

    const elRemain = el.musicTimeRemaining || getEl('music-time-remaining');
    if (elRemain) elRemain.textContent = formatRemaining(dur - pos);

    const fill = el.musicScrubberFill || getEl('music-scrubber-fill');
    if (fill && dur > 0) {
      const pct = Math.min(100, Math.max(0, (pos / dur) * 100));
      fill.style.width = `${pct}%`;
    }
  }

  function startScrubberTicker() {
    if (scrubberTimer) clearInterval(scrubberTimer);
    scrubberTimer = setInterval(() => {
      if (state.media && state.media.state === 'playing' && currentDuration > 0) {
        currentPosition = Math.min(currentDuration, currentPosition + 1);
        updateScrubberUI(currentPosition, currentDuration);
      }
    }, 1000);
  }

  let lastKnownMedia = {
    player: 'Music',
    title: '',
    artist: '',
    album: '',
    artwork: '',
    state: 'stopped',
    duration: 0,
    position: 0
  };

  function updateMediaUI(media) {
    if (!media) return;

    const hasValidTitle = Boolean(media.title && media.title.trim() && media.title !== 'Nenhuma reprodução');
    const isNewTrack = hasValidTitle && (media.title !== lastKnownMedia.title || media.artist !== lastKnownMedia.artist);

    if (hasValidTitle) {
      lastKnownMedia = {
        player: media.player || 'Music',
        title: media.title,
        artist: media.artist || 'Apple Music',
        album: media.album || '',
        // Always use the new track's artwork on track change, never fall back to stale previous song artwork
        artwork: isNewTrack ? (media.artwork || '') : (media.artwork || lastKnownMedia.artwork || ''),
        state: media.state || 'stopped',
        duration: typeof media.duration === 'number' ? media.duration : 0,
        position: typeof media.position === 'number' ? media.position : 0
      };
    } else if (lastKnownMedia.title) {
      lastKnownMedia.state = media.state || lastKnownMedia.state;
      if (typeof media.position === 'number' && media.position > 0) {
        lastKnownMedia.position = media.position;
      }
      if (media.artwork) {
        lastKnownMedia.artwork = media.artwork;
      }
    }

    const displayMedia = (lastKnownMedia && lastKnownMedia.title) ? lastKnownMedia : media;
    const isPlaying = (media.state === 'playing') || (displayMedia.state === 'playing');

    const titleEl = el.musicTitle || getEl('music-title');
    if (titleEl) {
      titleEl.textContent = displayMedia.title || 'Nenhuma reprodução';
    }

    const artistEl = el.musicArtist || getEl('music-artist');
    if (artistEl) {
      artistEl.textContent = displayMedia.artist || (displayMedia.player === 'Music' ? 'Apple Music' : 'Mac Pronto');
    }

    const glyph = el.glyphPlay || getEl('glyph-play');
    if (glyph) {
      glyph.innerHTML = isPlaying ?
        '<svg viewBox="0 0 24 24" width="42" height="42" fill="currentColor"><rect x="6" y="4" width="4" height="16" rx="1.5"/><rect x="14" y="4" width="4" height="16" rx="1.5"/></svg>' :
        '<svg viewBox="0 0 24 24" width="42" height="42" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>';
    }

    // Artwork handling with fluid Apple crossfade transition
    const artImg = el.musicArtImg || getEl('music-art-img');
    const container = el.musicScreenContainer || getEl('music-screen-container');

    if (artImg) {
      if (displayMedia.artwork && displayMedia.artwork.length > 50) {
        const src = displayMedia.artwork.startsWith('http') ? displayMedia.artwork : `data:image/jpeg;base64,${displayMedia.artwork}`;
        const artKey = `${displayMedia.artist}_${displayMedia.title}_${displayMedia.artwork.substring(0, 30)}`;
        if (currentArtKey !== artKey) {
          currentArtKey = artKey;
          // Smooth Apple Crossfade
          artImg.style.opacity = '0.3';
          artImg.style.transform = 'scale(0.94)';
          const imgLoader = new Image();
          imgLoader.onload = function () {
            artImg.src = src;
            artImg.style.opacity = '1';
            artImg.style.transform = 'scale(1)';
            extractDominantColorAndApply(artImg);
          };
          imgLoader.src = src;
        }
      } else {
        const defaultKey = `default_${displayMedia.title || 'none'}`;
        if (currentArtKey !== defaultKey) {
          currentArtKey = defaultKey;
          artImg.style.opacity = '0.3';
          artImg.style.transform = 'scale(0.94)';
          setTimeout(() => {
            artImg.src = 'icons/music.png';
            artImg.style.opacity = '1';
            artImg.style.transform = 'scale(1)';
          }, 80);

          const root = document.documentElement;
          root.style.setProperty('--m-r1', 55);
          root.style.setProperty('--m-g1', 80);
          root.style.setProperty('--m-b1', 140);
          root.style.setProperty('--m-r2', 25);
          root.style.setProperty('--m-g2', 40);
          root.style.setProperty('--m-b2', 75);
          root.style.setProperty('--m-r3', 12);
          root.style.setProperty('--m-g3', 18);
          root.style.setProperty('--m-b3', 30);
        }
      }
    }

    // Scrubber & Duration handling
    currentDuration = typeof displayMedia.duration === 'number' ? displayMedia.duration : 0;
    currentPosition = typeof displayMedia.position === 'number' ? displayMedia.position : 0;
    updateScrubberUI(currentPosition, currentDuration);

    if (isPlaying) {
      startScrubberTicker();
    } else {
      if (scrubberTimer) clearInterval(scrubberTimer);
    }
  }

  function initScrubber() {
    const scrubberTrack = el.musicScrubberTrack || getEl('music-scrubber-track');
    if (!scrubberTrack) return;

    let isScrubbing = false;

    function applyScrub(clientX, isFinal = false) {
      const rect = scrubberTrack.getBoundingClientRect();
      const relX = clientX - rect.left;
      let pct = relX / rect.width;
      pct = Math.max(0, Math.min(1, pct));
      if (currentDuration > 0) {
        const targetSec = Math.round(pct * currentDuration);
        currentPosition = targetSec;
        updateScrubberUI(currentPosition, currentDuration);
        if (isFinal) {
          sendMacAction('set_player_position', { position: targetSec });
        }
      }
    }

    scrubberTrack.addEventListener('pointerdown', (e) => {
      isScrubbing = true;
      scrubberTrack.setPointerCapture(e.pointerId);
      applyScrub(e.clientX, false);

      function onMove(m) {
        if (isScrubbing) applyScrub(m.clientX, false);
      }
      function onUp(u) {
        if (isScrubbing) {
          applyScrub(u.clientX, true);
          isScrubbing = false;
        }
        scrubberTrack.removeEventListener('pointermove', onMove);
        scrubberTrack.removeEventListener('pointerup', onUp);
        scrubberTrack.removeEventListener('pointercancel', onUp);
      }

      scrubberTrack.addEventListener('pointermove', onMove);
      scrubberTrack.addEventListener('pointerup', onUp);
      scrubberTrack.addEventListener('pointercancel', onUp);
    });
  }

  // Render Deck 2x6: Single Glass Dock, Floating Icons with Shadows & Running Dots
  function renderDeckButtons(buttons) {
    const grid = el.deckGrid || getEl('deck-grid');
    if (!grid) return;
    grid.innerHTML = '';

    const list = Array.isArray(buttons) && buttons.length > 0 ? buttons : DEFAULT_DECK;

    list.forEach((btn, index) => {
      const btnEl = document.createElement('div');
      btnEl.className = 'app-tile-btn';

      if (btn.isRunning) {
        btnEl.classList.add('running');
      }

      // 1. Icon Squircle with Authentic Drop Shadow
      const iconWrap = document.createElement('div');
      iconWrap.className = 'app-icon-squircle';

      const img = document.createElement('img');
      img.alt = btn.label;

      if (btn.iconBase64 && btn.iconBase64.length > 50) {
        img.src = `data:image/png;base64,${btn.iconBase64}`;
      } else if (btn.iconUrl) {
        img.src = btn.iconUrl;
      } else {
        img.src = `icons/${btn.id}.png`;
      }

      img.onerror = function () {
        img.src = `icons/${btn.id || 'settings'}.png`;
      };

      iconWrap.appendChild(img);

      // 2. Text Label
      const label = document.createElement('span');
      label.className = 'app-tile-label';
      label.textContent = btn.label || `Slot ${index + 1}`;

      // 3. macOS Running Indicator Dot
      const runningDot = document.createElement('span');
      runningDot.className = 'app-running-dot';

      btnEl.appendChild(iconWrap);
      btnEl.appendChild(label);
      btnEl.appendChild(runningDot);

      btnEl.addEventListener('click', () => {
        executeDeckButton(btn);
      });

      grid.appendChild(btnEl);
    });
  }

  function isAppRunningCheck(btn, runningList) {
    if (!runningList || !Array.isArray(runningList)) return Boolean(btn.isRunning);
    const id = (btn.id || '').toLowerCase();
    const label = (btn.label || '').toLowerCase();
    const payload = (btn.payload || '').toLowerCase();
    
    return runningList.some(item => {
      const r = String(item).toLowerCase();
      if (payload && r.includes(payload)) return true;
      if (label && (r === label || r.includes(label) || label.includes(r))) return true;
      if (id && (r.includes(id) || id.includes(r))) return true;
      if (id === 'chrome' && r.includes('chrome')) return true;
      if (id === 'music' && (r.includes('music') || r.includes('música'))) return true;
      if (id === 'discord' && r.includes('discord')) return true;
      if (id === 'photoshop' && r.includes('photoshop')) return true;
      if (id === 'illustrator' && r.includes('illustrator')) return true;
      if (id === 'indesign' && r.includes('indesign')) return true;
      if (id === 'figma' && r.includes('figma')) return true;
      if (id === 'affinity' && r.includes('affinity')) return true;
      if (id === 'antigravity' && r.includes('antigravity')) return true;
      if (id === 'whatsapp' && r.includes('whatsapp')) return true;
      if (id === 'finder' && r.includes('finder')) return true;
      if (id === 'settings' && (r.includes('settings') || r.includes('ajustes'))) return true;
      return false;
    });
  }

  function updateRunningDots(runningList) {
    const grid = el.deckGrid || getEl('deck-grid');
    if (!grid) return;
    const tiles = grid.querySelectorAll('.app-tile-btn');
    const buttons = (state.buttons && state.buttons.length > 0) ? state.buttons : DEFAULT_DECK;
    
    tiles.forEach((tile, index) => {
      const btn = buttons[index];
      if (btn) {
        const isRunning = isAppRunningCheck(btn, runningList);
        btn.isRunning = isRunning;
        if (isRunning) {
          tile.classList.add('running');
        } else {
          tile.classList.remove('running');
        }
      }
    });
  }

  function executeDeckButton(btn) {
    const act = btn.actionType || 'launch_app';
    const payload = btn.payload || '';
    const label = btn.label || '';
    const id = (btn.id || '').toLowerCase();

    if (act === 'shortcut') {
      sendMacAction('shortcut', { shortcut: payload, name: payload, label: label });
      showToast(`Atalho macOS: ${label || payload}`);
    } else if (act === 'url') {
      sendMacAction('open_url', { url: payload });
      showToast(`Abrindo URL: ${payload}`);
    } else if (act === 'launch_app') {
      sendMacAction('launch_app', { app: payload, payload: payload, label: label });
      showToast(`Abrindo ${label}...`);
      if (id === 'illustrator' || label.toLowerCase().includes('illustrator') || payload.toLowerCase().includes('illustrator')) {
        setTimeout(() => {
          toggleIllustratorScreen(true);
        }, 150);
      }
    } else if (act === 'hotkey') {
      sendMacAction('parse_hotkey_string', { hotkey: payload, payload: payload, label: label });
      showToast(`Atalho: ${label} (${payload})`);
    } else if (act === 'terminal_cmd') {
      sendMacAction('terminal_cmd', { cmd: payload });
      showToast(`Terminal: ${label}`);
    } else if (act === 'system') {
      sendMacAction('system_command', { command: payload });
    } else if (act === 'sound') {
      sendMacAction('play_sound', { sound: payload });
    }
  }

  // ==========================================================================
  // 4. Interactive Sliders (Vertical CC + Horizontal Music)
  // ==========================================================================
  function initSliders() {
    // 1. Vertical Brightness Slider
    const sBright = el.sliderBrightness || getEl('slider-box-brightness');
    if (sBright) {
      let lastSend = 0;
      function onBrightTouch(e, isFinal = false) {
        const rect = sBright.getBoundingClientRect();
        const clientY = e.touches ? e.touches[0].clientY : e.clientY;
        const relY = rect.bottom - clientY;
        let percent = Math.round((relY / rect.height) * 100);
        percent = Math.max(0, Math.min(100, percent));

        state.brightness = percent;
        const fillB = el.sliderFillBrightness || getEl('slider-fill-brightness');
        if (fillB) fillB.style.height = `${percent}%`;

        const now = Date.now();
        if (isFinal || now - lastSend > 50) {
          lastSend = now;
          sendMacAction('set_brightness', { brightness: percent });
        }
      }

      sBright.addEventListener('pointerdown', (e) => {
        isDraggingBrightness = true;
        lastUserBrightTime = Date.now();
        sBright.setPointerCapture(e.pointerId);
        onBrightTouch(e);

        function move(m) {
          lastUserBrightTime = Date.now();
          onBrightTouch(m);
        }
        function up(u) {
          sBright.removeEventListener('pointermove', move);
          sBright.removeEventListener('pointerup', up);
          sBright.removeEventListener('pointercancel', up);
          onBrightTouch(u, true);
          isDraggingBrightness = false;
          lastUserBrightTime = Date.now();
        }

        sBright.addEventListener('pointermove', move);
        sBright.addEventListener('pointerup', up);
        sBright.addEventListener('pointercancel', up);
      });
    }

    // 2. Vertical CC Volume Slider
    const sVol = el.sliderVolume || getEl('slider-box-volume');
    if (sVol) {
      let lastSend = 0;
      function onVolTouch(e, isFinal = false) {
        const rect = sVol.getBoundingClientRect();
        const clientY = e.touches ? e.touches[0].clientY : e.clientY;
        const relY = rect.bottom - clientY;
        let percent = Math.round((relY / rect.height) * 100);
        percent = Math.max(0, Math.min(100, percent));

        state.volume = percent;
        updateVolumeUI(percent);

        const now = Date.now();
        if (isFinal || now - lastSend > 50) {
          lastSend = now;
          sendMacAction('set_volume', { volume: percent });
        }
      }

      sVol.addEventListener('pointerdown', (e) => {
        isDraggingVolume = true;
        lastUserVolTime = Date.now();
        sVol.setPointerCapture(e.pointerId);
        onVolTouch(e);

        function move(m) {
          lastUserVolTime = Date.now();
          onVolTouch(m);
        }
        function up(u) {
          sVol.removeEventListener('pointermove', move);
          sVol.removeEventListener('pointerup', up);
          sVol.removeEventListener('pointercancel', up);
          onVolTouch(u, true);
          isDraggingVolume = false;
          lastUserVolTime = Date.now();
        }

        sVol.addEventListener('pointermove', move);
        sVol.addEventListener('pointerup', up);
        sVol.addEventListener('pointercancel', up);
      });
    }

    // 3. Horizontal Music Screen Volume Slider
    const mVol = el.musicVolSlider || getEl('music-vol-slider');
    if (mVol) {
      let lastSend = 0;
      function onHTouch(e, isFinal = false) {
        const rect = mVol.getBoundingClientRect();
        const clientX = e.touches ? e.touches[0].clientX : e.clientX;
        const relX = clientX - rect.left;
        let percent = Math.round((relX / rect.width) * 100);
        percent = Math.max(0, Math.min(100, percent));

        state.volume = percent;
        updateVolumeUI(percent);

        const now = Date.now();
        if (isFinal || now - lastSend > 50) {
          lastSend = now;
          sendMacAction('set_volume', { volume: percent });
        }
      }

      mVol.addEventListener('pointerdown', (e) => {
        isDraggingVolume = true;
        lastUserVolTime = Date.now();
        mVol.setPointerCapture(e.pointerId);
        onHTouch(e);

        function move(m) {
          lastUserVolTime = Date.now();
          onHTouch(m);
        }
        function up(u) {
          mVol.removeEventListener('pointermove', move);
          mVol.removeEventListener('pointerup', up);
          mVol.removeEventListener('pointercancel', up);
          onHTouch(u, true);
          isDraggingVolume = false;
          lastUserVolTime = Date.now();
        }

        mVol.addEventListener('pointermove', move);
        mVol.addEventListener('pointerup', up);
        mVol.addEventListener('pointercancel', up);
      });
    }
  }

  // ==========================================================================
  // 6. Adobe Illustrator Studio & Interactive Multi-Mode Color Engine
  // ==========================================================================
  // Adobe Illustrator Studio Integration - Cores Recentes do Arquivo Aberto
  // ==========================================================================
  const INITIAL_AI_RECENT_20 = [
    '#000000', '#FFFFFF', '#FF30C7', '#FF9500', '#FF3B30',
    '#34C759', '#007AFF', '#5856D6', '#AF52DE', '#FF2D55',
    '#FFCC00', '#5AC8FA', '#30B0C7', '#FF8A00', '#E0245E',
    '#17BF63', '#F45D22', '#1C1C1E', '#3A3A3C', '#8E8E93'
  ];

  let aiRecentColors = [];
  try {
    const saved = localStorage.getItem('ai_recent_colors_v4');
    if (saved) {
      aiRecentColors = JSON.parse(saved);
    }
  } catch(e){}
  if (!Array.isArray(aiRecentColors) || aiRecentColors.length === 0) {
    aiRecentColors = [...INITIAL_AI_RECENT_20];
  }

  let aiState = {
    active: false,
    pickerMode: localStorage.getItem('ai_color_picker_mode') || 'circle', // 'circle', 'triangle', 'square'
    colorTarget: 'fill', // 'fill' or 'stroke'
    currentHue: 36, // 0-360 degrees
    currentSat: 1.0, // 0-1
    currentVal: 0.98, // 0-1
    currentHex: '#FF8A00',
    lastColorSendTime: 0,
    userDismissedThisSession: false,
    lastFrontApp: ''
  };

  function setAiColorTarget(target) {
    aiState.colorTarget = target;
    const strokeBox = getEl('ai-stroke-box');
    const fillBox = getEl('ai-fill-box');
    if (fillBox && strokeBox) {
      if (target === 'fill') {
        fillBox.style.zIndex = '2';
        strokeBox.style.zIndex = '1';
        fillBox.style.borderColor = '#FFFFFF';
        strokeBox.style.borderColor = 'rgba(255, 255, 255, 0.4)';
      } else {
        strokeBox.style.zIndex = '2';
        fillBox.style.zIndex = '1';
        strokeBox.style.borderColor = '#FFFFFF';
        fillBox.style.borderColor = 'rgba(255, 255, 255, 0.4)';
      }
    }
    triggerHaptic();
    sendAiColor(aiState.currentHex, true);
  }
  window.setAiColorTarget = setAiColorTarget;

  function toggleIllustratorScreen(show) {
    triggerHaptic();
    if (show) {
      aiState.active = true;
      goToScreen(2);
    } else {
      aiState.active = false;
      goToScreen(1);
    }
  }
  window.toggleIllustratorScreen = toggleIllustratorScreen;

  function setColorPickerMode(mode) {
    if (!mode) return;
    aiState.pickerMode = mode;
    try {
      localStorage.setItem('ai_color_picker_mode', mode);
    } catch(e){}

    const modes = ['circle', 'triangle', 'square'];
    modes.forEach(m => {
      const btn = getEl(`ai-mode-${m}`);
      const vp = getEl(`ai-picker-${m}`);
      if (btn) {
        if (m === mode) btn.classList.add('active');
        else btn.classList.remove('active');
      }
      if (vp) {
        if (m === mode) vp.classList.add('active');
        else vp.classList.remove('active');
      }
    });

    triggerHaptic();
    if (mode === 'triangle') {
      drawTriangleCanvas();
    }
    updateCursorPosition();
  }
  window.setColorPickerMode = setColorPickerMode;

  // ==========================================================================
  // Illustrator Typography & 20 Recent Swatches Manager
  // ==========================================================================
  let textTarget = 'fill'; // 'fill' or 'stroke'

  function setTextTarget(target) {
    textTarget = target;
    const btnFill = getEl('ai-text-target-fill');
    const btnStroke = getEl('ai-text-target-stroke');
    if (btnFill && btnStroke) {
      if (target === 'fill') {
        btnFill.classList.add('active');
        btnStroke.classList.remove('active');
      } else {
        btnStroke.classList.add('active');
        btnFill.classList.remove('active');
      }
    }
    triggerHaptic();
  }
  window.setTextTarget = setTextTarget;

  function addRecentAiColor(hex, save = true) {
    if (!hex || typeof hex !== 'string') return;
    hex = hex.trim().toUpperCase();
    if (!hex.startsWith('#')) hex = '#' + hex;
    if (hex.length !== 7) return;

    // Remove duplicates
    aiRecentColors = aiRecentColors.filter(c => c.toUpperCase() !== hex);
    // Prepend
    aiRecentColors.unshift(hex);
    // Limit to 20 recent colors
    if (aiRecentColors.length > 20) {
      aiRecentColors = aiRecentColors.slice(0, 20);
    }
    if (save) {
      try {
        localStorage.setItem('ai_recent_colors_v4', JSON.stringify(aiRecentColors));
      } catch(e){}
      renderRecentSwatchesGrid();
      renderRecentIllustratorColors();
    }
  }
  window.addRecentAiColor = addRecentAiColor;

  function renderRecentIllustratorColors() {
    const row = getEl('ai-recent-colors-row');
    if (!row) return;
    row.innerHTML = '';

    if (aiRecentColors.length === 0) {
      const emptySpan = document.createElement('span');
      emptySpan.className = 'text-[10px] text-white/40 italic px-2 shrink-0';
      emptySpan.textContent = 'Sem cores';
      row.appendChild(emptySpan);
      return;
    }

    // Tela 1: Apenas 4 cores recentes
    aiRecentColors.slice(0, 4).forEach((hex) => {
      const btn = document.createElement('button');
      btn.className = 'ai-recent-color-btn';
      btn.style.setProperty('background-color', hex, 'important');
      btn.title = hex;
      if (aiState.currentHex && aiState.currentHex.toUpperCase() === hex.toUpperCase()) {
        btn.classList.add('active-color');
      }
      btn.onclick = () => {
        applyAiHex(hex);
      };
      row.appendChild(btn);
    });
  }
  window.renderRecentIllustratorColors = renderRecentIllustratorColors;

  function handleImportedAiColors(colors) {
    if (!Array.isArray(colors) || colors.length === 0) return;
    // Set up to 20 recent colors from Illustrator
    aiRecentColors = [];
    colors.slice(0, 20).forEach(c => addRecentAiColor(c, false));
    try {
      localStorage.setItem('ai_recent_colors_v4', JSON.stringify(aiRecentColors));
    } catch(e){}
    renderRecentSwatchesGrid();
    renderRecentIllustratorColors();
  }
  window.handleImportedAiColors = handleImportedAiColors;

  function extractIllustratorSwatches() {
    triggerHaptic();
    sendMacAction('illustrator_command', { command: 'get_recent_colors' });
  }
  window.extractIllustratorSwatches = extractIllustratorSwatches;

  function renderRecentSwatchesGrid() {
    const container = getEl('ai-swatch-grid-20') || getEl('ai-swatch-grid-10');
    if (!container) return;
    container.innerHTML = '';

    // Tela 2: 10 cores recentes (grade 5x2)
    aiRecentColors.slice(0, 10).forEach((hex) => {
      const btn = document.createElement('button');
      btn.className = 'ai-swatch-cell';
      btn.style.setProperty('--swatch-color', hex);
      btn.style.setProperty('background-color', hex, 'important');
      btn.title = hex;
      if (aiState.currentHex && aiState.currentHex.toUpperCase() === hex.toUpperCase()) {
        btn.classList.add('active-swatch');
      }
      btn.onclick = () => {
        applyPaletteColor(hex);
      };
      container.appendChild(btn);
    });
  }
  window.renderRecentSwatchesGrid = renderRecentSwatchesGrid;

  function applyPaletteColor(hex) {
    if (!hex) return;
    const preview = getEl('ai-text-color-preview');
    const label = getEl('ai-text-hex-label');
    if (preview) preview.style.backgroundColor = hex;
    if (label) label.textContent = hex.toUpperCase();

    addRecentAiColor(hex);

    // Keep chromatic wheel / controls in sync
    const hsv = hexToHsv(hex);
    aiState.currentHue = hsv.h;
    aiState.currentSat = hsv.s;
    aiState.currentVal = hsv.v;
    const rgb = hsvToRgb(aiState.currentHue / 360, aiState.currentSat, aiState.currentVal);
    updateColorDisplay(hex, rgb);
    updateCursorPosition();

    // Send Illustrator set color to Mac companion
    sendMacAction('illustrator_set_color', {
      hex: hex,
      target: textTarget
    });

    // Copy to clipboard
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(hex).catch(() => {});
    }

    triggerHaptic();
  }
  window.applyPaletteColor = applyPaletteColor;

  function toggleHyphenation(isChecked) {
    sendMacAction('illustrator_command', {
      command: 'toggle_hyphenation'
    });
    triggerHaptic();
  }
  window.toggleHyphenation = toggleHyphenation;

  function hsvToRgb(h, s, v) {
    let r, g, b;
    const i = Math.floor(h * 6);
    const f = h * 6 - i;
    const p = v * (1 - s);
    const q = v * (1 - f * s);
    const t = v * (1 - (1 - f) * s);
    switch (i % 6) {
      case 0: r = v; g = t; b = p; break;
      case 1: r = q; g = v; b = p; break;
      case 2: r = p; g = v; b = t; break;
      case 3: r = p; g = q; b = v; break;
      case 4: r = t; g = p; b = v; break;
      case 5: r = v; g = p; b = q; break;
      default: r = v; g = t; b = p; break;
    }
    return {
      r: Math.round(r * 255),
      g: Math.round(g * 255),
      b: Math.round(b * 255)
    };
  }

  function rgbToHex(r, g, b) {
    return '#' + [r, g, b].map(x => {
      const hex = Math.max(0, Math.min(255, x)).toString(16);
      return hex.length === 1 ? '0' + hex : hex;
    }).join('').toUpperCase();
  }

  function hexToHsv(hex) {
    let c = hex.replace('#', '');
    if (c.length === 3) c = c.split('').map(x => x + x).join('');
    const r = parseInt(c.substring(0, 2), 16) / 255;
    const g = parseInt(c.substring(2, 4), 16) / 255;
    const b = parseInt(c.substring(4, 6), 16) / 255;

    const max = Math.max(r, g, b), min = Math.min(r, g, b);
    let h, s, v = max;
    const d = max - min;
    s = max === 0 ? 0 : d / max;

    if (max === min) {
      h = 0;
    } else {
      switch (max) {
        case r: h = (g - b) / d + (g < b ? 6 : 0); break;
        case g: h = (b - r) / d + 2; break;
        case b: h = (r - g) / d + 4; break;
      }
      h /= 6;
    }
    return { h: h * 360, s: s, v: v };
  }

  function drawTriangleCanvas() {
    const canvas = getEl('ai-triangle-canvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const w = canvas.width;
    const h = canvas.height;
    ctx.clearRect(0, 0, w, h);

    const pureRgb = hsvToRgb(aiState.currentHue / 360, 1.0, 1.0);
    const pureHex = rgbToHex(pureRgb.r, pureRgb.g, pureRgb.b);

    const p1 = { x: w / 2, y: 8 };
    const p2 = { x: 10, y: h - 10 };
    const p3 = { x: w - 10, y: h - 10 };

    ctx.save();
    ctx.beginPath();
    ctx.moveTo(p1.x, p1.y);
    ctx.lineTo(p2.x, p2.y);
    ctx.lineTo(p3.x, p3.y);
    ctx.closePath();
    ctx.clip();

    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, w, h);

    const gradHue = ctx.createLinearGradient(p1.x, p1.y, p1.x, p2.y);
    gradHue.addColorStop(0, pureHex);
    gradHue.addColorStop(1, 'transparent');
    ctx.fillStyle = gradHue;
    ctx.fillRect(0, 0, w, h);

    const gradBlack = ctx.createLinearGradient(p1.x, p1.y, p1.x, p3.y);
    gradBlack.addColorStop(0, 'transparent');
    gradBlack.addColorStop(1, '#000000');
    ctx.fillStyle = gradBlack;
    ctx.fillRect(0, 0, w, h);

    ctx.restore();
  }

  function updateCursorPosition() {
    // 1. Circle Cursor
    const wheelCursor = getEl('ai-wheel-cursor');
    const wheelContainer = getEl('ai-wheel-container');
    if (wheelCursor && wheelContainer) {
      const rect = wheelContainer.getBoundingClientRect();
      if (rect.width > 0) {
        const radius = (rect.width / 2) * 0.82;
        const rad = (aiState.currentHue * Math.PI) / 180;
        const dist = Math.max(0, Math.min(1, aiState.currentSat)) * radius;
        const cx = rect.width / 2;
        const cy = rect.height / 2;
        const posX = cx + Math.sin(rad) * dist;
        const posY = cy - Math.cos(rad) * dist;
        wheelCursor.style.left = `${posX}px`;
        wheelCursor.style.top = `${posY}px`;
        wheelCursor.style.transform = 'translate(-50%, -50%)';
      }
    }

    // 2. Triangle / Pyramid Cursors
    const triCursor = getEl('ai-triangle-cursor');
    const ringCursor = getEl('ai-ring-cursor');
    const triRing = getEl('ai-triangle-ring');
    if (ringCursor && triRing) {
      const rect = triRing.getBoundingClientRect();
      if (rect.width > 0) {
        const radius = (rect.width / 2) * 0.90;
        const rad = (aiState.currentHue * Math.PI) / 180;
        const cx = rect.width / 2;
        const cy = rect.height / 2;
        ringCursor.style.left = `${cx + Math.sin(rad) * radius}px`;
        ringCursor.style.top = `${cy - Math.cos(rad) * radius}px`;
        ringCursor.style.transform = 'translate(-50%, -50%)';
      }
    }
    if (triCursor) {
      const sat = aiState.currentSat;
      const val = aiState.currentVal;
      // Barycentric mapping approximation
      const posY = (1 - val) * 75 + 15;
      const posX = 50 + (sat - 0.5) * (val * 50);
      triCursor.style.top = `${posY}%`;
      triCursor.style.left = `${posX}%`;
    }

    // 3. Square Cursor & Background
    const sqCursor = getEl('ai-square-cursor');
    const sqBg = getEl('ai-square-hue-bg');
    const pureRgb = hsvToRgb(aiState.currentHue / 360, 1.0, 1.0);
    const pureHex = rgbToHex(pureRgb.r, pureRgb.g, pureRgb.b);
    if (sqBg) sqBg.style.backgroundColor = pureHex;
    if (sqCursor) {
      sqCursor.style.left = `${aiState.currentSat * 100}%`;
      sqCursor.style.top = `${(1 - aiState.currentVal) * 100}%`;
    }
  }

  let colorSendTimer = null;
  let pendingColorHex = null;
  let lastColorSentTime = 0;
  const COLOR_SEND_THROTTLE_MS = 100; // Smooth ~10 updates/sec without lagging Illustrator

  function sendAiColor(hex, isFinal = false) {
    if (!hex) return;
    pendingColorHex = hex;

    if (isFinal) {
      if (colorSendTimer) {
        clearTimeout(colorSendTimer);
        colorSendTimer = null;
      }
      lastColorSentTime = Date.now();
      sendMacAction('illustrator_set_color', {
        hex: hex,
        target: aiState.colorTarget
      });
      return;
    }

    const now = Date.now();
    const elapsed = now - lastColorSentTime;

    if (elapsed >= COLOR_SEND_THROTTLE_MS) {
      lastColorSentTime = now;
      if (colorSendTimer) {
        clearTimeout(colorSendTimer);
        colorSendTimer = null;
      }
      sendMacAction('illustrator_set_color', {
        hex: hex,
        target: aiState.colorTarget
      });
    } else if (!colorSendTimer) {
      colorSendTimer = setTimeout(() => {
        colorSendTimer = null;
        lastColorSentTime = Date.now();
        if (pendingColorHex) {
          sendMacAction('illustrator_set_color', {
            hex: pendingColorHex,
            target: aiState.colorTarget
          });
        }
      }, COLOR_SEND_THROTTLE_MS - elapsed);
    }
  }

  function updateColorDisplay(hex, rgb) {
    aiState.currentHex = hex;
    
    const centerDot = getEl('ai-color-center-dot');
    if (centerDot) {
      centerDot.style.backgroundColor = hex;
      centerDot.style.boxShadow = `0 2px 14px ${hex}90`;
    }

    const fillBox = getEl('ai-fill-box');
    const strokeBox = getEl('ai-stroke-box');
    if (aiState.colorTarget === 'fill' && fillBox) {
      fillBox.style.backgroundColor = hex;
    } else if (aiState.colorTarget === 'stroke' && strokeBox) {
      strokeBox.style.backgroundColor = hex;
    }

    // Mini Sliders Labels & Thumbs
    const lblH = getEl('ai-label-h');
    const thumbH = getEl('ai-thumb-h');
    if (lblH) lblH.textContent = `${Math.round(aiState.currentHue)}°`;
    if (thumbH) thumbH.style.left = `${(aiState.currentHue / 360) * 100}%`;

    const lblS = getEl('ai-label-s');
    const thumbS = getEl('ai-thumb-s');
    const barS = getEl('ai-bar-s');
    const pureRgb = hsvToRgb(aiState.currentHue / 360, 1.0, 1.0);
    const pureHex = rgbToHex(pureRgb.r, pureRgb.g, pureRgb.b);
    if (lblS) lblS.textContent = `${Math.round(aiState.currentSat * 100)}%`;
    if (thumbS) thumbS.style.left = `${aiState.currentSat * 100}%`;
    if (barS) barS.style.background = `linear-gradient(to right, #E2E8F0, ${pureHex})`;

    const lblB = getEl('ai-label-b');
    const thumbB = getEl('ai-thumb-b');
    const barB = getEl('ai-bar-b');
    if (lblB) lblB.textContent = `${Math.round(aiState.currentVal * 100)}%`;
    if (thumbB) thumbB.style.left = `${aiState.currentVal * 100}%`;
    if (barB) barB.style.background = `linear-gradient(to right, #000000, ${pureHex})`;

    if (aiState.pickerMode === 'triangle') {
      drawTriangleCanvas();
    }
  }

  function applyAiHex(hex) {
    const hsv = hexToHsv(hex);
    aiState.currentHue = hsv.h;
    aiState.currentSat = hsv.s;
    aiState.currentVal = hsv.v;

    addRecentAiColor(hex);

    const rgb = hsvToRgb(aiState.currentHue / 360, aiState.currentSat, aiState.currentVal);
    updateColorDisplay(hex, rgb);
    updateCursorPosition();
    triggerHaptic();
    sendAiColor(hex, true);
  }
  window.applyAiHex = applyAiHex;

  function copyAiColor() {
    triggerHaptic();
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(aiState.currentHex);
    }
  }
  window.copyAiColor = copyAiColor;

  function initColorWheelEvents() {
    // 1. Circle Mode Picker Events
    const wheel = getEl('ai-wheel-container');
    if (wheel) {
      let isDraggingWheel = false;

      function handleWheelPick(e, isFinal = false) {
        const rect = wheel.getBoundingClientRect();
        const clientX = e.touches ? e.touches[0].clientX : e.clientX;
        const clientY = e.touches ? e.touches[0].clientY : e.clientY;

        const cx = rect.left + rect.width / 2;
        const cy = rect.top + rect.height / 2;
        const dx = clientX - cx;
        const dy = clientY - cy;
        const dist = Math.sqrt(dx * dx + dy * dy);
        const maxRadius = (rect.width / 2) * 0.85;

        let angle = Math.atan2(dx, -dy) * (180 / Math.PI);
        if (angle < 0) angle += 360;

        const sat = Math.min(1, Math.max(0.02, dist / maxRadius));
        aiState.currentHue = angle;
        aiState.currentSat = sat;

        const rgb = hsvToRgb(aiState.currentHue / 360, aiState.currentSat, aiState.currentVal);
        const hex = rgbToHex(rgb.r, rgb.g, rgb.b);

        updateColorDisplay(hex, rgb);
        updateCursorPosition();
        sendAiColor(hex, isFinal);
        if (isFinal) addRecentAiColor(hex);
      }

      wheel.addEventListener('pointerdown', (e) => {
        if (e.target.closest('#ai-color-center-dot')) return;
        isDraggingWheel = true;
        isInteractingWithColorPicker = true;
        wheel.setPointerCapture(e.pointerId);
        handleWheelPick(e);

        function move(m) {
          if (!isDraggingWheel) return;
          handleWheelPick(m);
        }
        function up(u) {
          if (!isDraggingWheel) return;
          isDraggingWheel = false;
          wheel.removeEventListener('pointermove', move);
          wheel.removeEventListener('pointerup', up);
          wheel.removeEventListener('pointercancel', up);
          handleWheelPick(u, true);
          setTimeout(() => { isInteractingWithColorPicker = false; }, 150);
        }

        wheel.addEventListener('pointermove', move);
        wheel.addEventListener('pointerup', up);
        wheel.addEventListener('pointercancel', up);
      });
    }

    // 2. Triangle Mode Picker Events
    const triCanvas = getEl('ai-triangle-canvas');
    const triRing = getEl('ai-triangle-ring');
    if (triRing) {
      let isDraggingRing = false;
      function handleRingPick(e, isFinal = false) {
        const rect = triRing.getBoundingClientRect();
        const clientX = e.touches ? e.touches[0].clientX : e.clientX;
        const clientY = e.touches ? e.touches[0].clientY : e.clientY;
        const dx = clientX - (rect.left + rect.width / 2);
        const dy = clientY - (rect.top + rect.height / 2);
        let angle = Math.atan2(dx, -dy) * (180 / Math.PI);
        if (angle < 0) angle += 360;
        aiState.currentHue = angle;
        const rgb = hsvToRgb(aiState.currentHue / 360, aiState.currentSat, aiState.currentVal);
        const hex = rgbToHex(rgb.r, rgb.g, rgb.b);
        updateColorDisplay(hex, rgb);
        updateCursorPosition();
        sendAiColor(hex, isFinal);
      }
      triRing.addEventListener('pointerdown', (e) => {
        if (e.target === triCanvas || e.target.closest('#ai-triangle-canvas')) return;
        isDraggingRing = true;
        isInteractingWithColorPicker = true;
        triRing.setPointerCapture(e.pointerId);
        handleRingPick(e);
        function move(m) { if (isDraggingRing) handleRingPick(m); }
        function up(u) {
          if (!isDraggingRing) return;
          isDraggingRing = false;
          triRing.removeEventListener('pointermove', move);
          triRing.removeEventListener('pointerup', up);
          triRing.removeEventListener('pointercancel', up);
          handleRingPick(u, true);
          setTimeout(() => { isInteractingWithColorPicker = false; }, 150);
        }
        triRing.addEventListener('pointermove', move);
        triRing.addEventListener('pointerup', up);
        triRing.addEventListener('pointercancel', up);
      });
    }

    if (triCanvas) {
      let isDraggingTri = false;
      function handleTriPick(e, isFinal = false) {
        const rect = triCanvas.getBoundingClientRect();
        const clientX = e.touches ? e.touches[0].clientX : e.clientX;
        const clientY = e.touches ? e.touches[0].clientY : e.clientY;
        const relX = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
        const relY = Math.max(0, Math.min(1, (clientY - rect.top) / rect.height));

        aiState.currentVal = Math.max(0, Math.min(1, 1 - relY));
        aiState.currentSat = Math.max(0, Math.min(1, relX));

        const rgb = hsvToRgb(aiState.currentHue / 360, aiState.currentSat, aiState.currentVal);
        const hex = rgbToHex(rgb.r, rgb.g, rgb.b);
        updateColorDisplay(hex, rgb);
        updateCursorPosition();
        sendAiColor(hex, isFinal);
        if (isFinal) addRecentAiColor(hex);
      }

      triCanvas.addEventListener('pointerdown', (e) => {
        isDraggingTri = true;
        isInteractingWithColorPicker = true;
        triCanvas.setPointerCapture(e.pointerId);
        handleTriPick(e);
        function move(m) { if (isDraggingTri) handleTriPick(m); }
        function up(u) {
          if (!isDraggingTri) return;
          isDraggingTri = false;
          triCanvas.removeEventListener('pointermove', move);
          triCanvas.removeEventListener('pointerup', up);
          triCanvas.removeEventListener('pointercancel', up);
          handleTriPick(u, true);
          setTimeout(() => { isInteractingWithColorPicker = false; }, 150);
        }
        triCanvas.addEventListener('pointermove', move);
        triCanvas.addEventListener('pointerup', up);
        triCanvas.addEventListener('pointercancel', up);
      });
    }

    // 3. Square Mode Picker Events
    const sqContainer = getEl('ai-square-container');
    if (sqContainer) {
      let isDraggingSq = false;
      function handleSqPick(e, isFinal = false) {
        const rect = sqContainer.getBoundingClientRect();
        const clientX = e.touches ? e.touches[0].clientX : e.clientX;
        const clientY = e.touches ? e.touches[0].clientY : e.clientY;

        const relX = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
        const relY = Math.max(0, Math.min(1, (clientY - rect.top) / rect.height));

        aiState.currentSat = relX;
        aiState.currentVal = 1 - relY;

        const rgb = hsvToRgb(aiState.currentHue / 360, aiState.currentSat, aiState.currentVal);
        const hex = rgbToHex(rgb.r, rgb.g, rgb.b);
        updateColorDisplay(hex, rgb);
        updateCursorPosition();
        sendAiColor(hex, isFinal);
        if (isFinal) addRecentAiColor(hex);
      }

      sqContainer.addEventListener('pointerdown', (e) => {
        isDraggingSq = true;
        isInteractingWithColorPicker = true;
        sqContainer.setPointerCapture(e.pointerId);
        handleSqPick(e);
        function move(m) { if (isDraggingSq) handleSqPick(m); }
        function up(u) {
          if (!isDraggingSq) return;
          isDraggingSq = false;
          sqContainer.removeEventListener('pointermove', move);
          sqContainer.removeEventListener('pointerup', up);
          sqContainer.removeEventListener('pointercancel', up);
          handleSqPick(u, true);
          setTimeout(() => { isInteractingWithColorPicker = false; }, 150);
        }
        sqContainer.addEventListener('pointermove', move);
        sqContainer.addEventListener('pointerup', up);
        sqContainer.addEventListener('pointercancel', up);
      });
    }

    // Mini Sliders H / S / B
    function initMiniSlider(barId, onSlide) {
      const bar = getEl(barId);
      if (!bar) return;
      function handleSlide(e, isFinal = false) {
        const rect = bar.getBoundingClientRect();
        const clientX = e.touches ? e.touches[0].clientX : e.clientX;
        const relX = clientX - rect.left;
        let pct = Math.max(0, Math.min(1, relX / rect.width));
        onSlide(pct, isFinal);
      }
      bar.addEventListener('pointerdown', (e) => {
        bar.setPointerCapture(e.pointerId);
        handleSlide(e);
        function move(m) { handleSlide(m); }
        function up(u) {
          bar.removeEventListener('pointermove', move);
          bar.removeEventListener('pointerup', up);
          bar.removeEventListener('pointercancel', up);
          handleSlide(u, true);
        }
        bar.addEventListener('pointermove', move);
        bar.addEventListener('pointerup', up);
        bar.addEventListener('pointercancel', up);
      });
    }

    // Slider H
    initMiniSlider('ai-bar-h', (pct, isFinal) => {
      aiState.currentHue = pct * 360;
      const rgb = hsvToRgb(aiState.currentHue / 360, aiState.currentSat, aiState.currentVal);
      const hex = rgbToHex(rgb.r, rgb.g, rgb.b);
      updateColorDisplay(hex, rgb);
      updateCursorPosition();
      sendAiColor(hex, isFinal);
      if (isFinal) addRecentAiColor(hex);
    });

    // Slider S
    initMiniSlider('ai-bar-s', (pct, isFinal) => {
      aiState.currentSat = pct;
      const rgb = hsvToRgb(aiState.currentHue / 360, aiState.currentSat, aiState.currentVal);
      const hex = rgbToHex(rgb.r, rgb.g, rgb.b);
      updateColorDisplay(hex, rgb);
      updateCursorPosition();
      sendAiColor(hex, isFinal);
      if (isFinal) addRecentAiColor(hex);
    });

    // Slider B
    initMiniSlider('ai-bar-b', (pct, isFinal) => {
      aiState.currentVal = pct;
      const rgb = hsvToRgb(aiState.currentHue / 360, aiState.currentSat, aiState.currentVal);
      const hex = rgbToHex(rgb.r, rgb.g, rgb.b);
      updateColorDisplay(hex, rgb);
      updateCursorPosition();
      sendAiColor(hex, isFinal);
      if (isFinal) addRecentAiColor(hex);
    });
  }

  // ==========================================================================
  // 6. Wireless Studio Microphone Controller (Android -> Mac 44.1kHz UDP)
  // ==========================================================================
  const micState = {
    isStreaming: false,
    isMuted: false,
    gain: 100, // 0 - 200%
    noiseReduction: true,
    level: 0
  };

  function updateMicUI() {
    // 1. Update Top Nav Pill
    const navPill = getEl('btn-nav-mic');
    const navLabel = getEl('mic-nav-label');
    if (navPill) {
      if (micState.isStreaming) {
        navPill.classList.add('streaming');
        if (micState.isMuted) {
          navPill.classList.add('muted');
          if (navLabel) navLabel.textContent = 'MUTE';
        } else {
          navPill.classList.remove('muted');
          if (navLabel) navLabel.textContent = 'LIVE';
        }
      } else {
        navPill.classList.remove('streaming', 'muted');
        if (navLabel) navLabel.textContent = 'MIC';
      }
    }

    // 2. Update Control Center Card
    const micCard = getEl('cc-mic-card');
    const btnText = getEl('cc-mic-btn-text');
    const statusLabel = getEl('cc-mic-status-label');
    const vuFill = getEl('cc-mic-vu-fill');
    const levelPct = getEl('cc-mic-level-pct');
    const btnMute = getEl('btn-cc-mic-mute');
    const muteIcon = getEl('cc-mic-mute-icon');
    const muteText = getEl('cc-mic-mute-text');

    if (micCard) {
      if (micState.isStreaming) {
        micCard.classList.add('streaming');
        if (btnText) btnText.textContent = 'Desligar';
        if (statusLabel) {
          if (micState.isMuted) {
            statusLabel.textContent = 'Áudio Mutado • Silêncio';
          } else {
            statusLabel.textContent = micState.noiseReduction ? '48 kHz • DeepFilterNet3 IA' : '48 kHz • Áudio Direto';
          }
        }
      } else {
        micCard.classList.remove('streaming');
        if (btnText) btnText.textContent = 'Ativar';
        if (statusLabel) statusLabel.textContent = '48.0 kHz • Estúdio Sem Fio';
      }
    }

    // VU meter bar
    if (vuFill) {
      const displayLevel = (!micState.isStreaming || micState.isMuted) ? 0 : micState.level;
      vuFill.style.width = `${displayLevel}%`;
    }
    if (levelPct) {
      if (!micState.isStreaming) {
        levelPct.textContent = 'OFF';
      } else if (micState.isMuted) {
        levelPct.textContent = 'MUTE';
      } else {
        levelPct.textContent = `${micState.level}%`;
      }
    }

    // Mute button chip
    if (btnMute) {
      if (micState.isMuted) {
        btnMute.classList.add('muted');
        if (muteIcon) muteIcon.textContent = '';
        if (muteText) muteText.textContent = 'Mutado';
      } else {
        btnMute.classList.remove('muted');
        if (muteIcon) muteIcon.textContent = '';
        if (muteText) muteText.textContent = 'Ao Vivo';
      }
    }
  }

  function toggleMicStream() {
    triggerHaptic();
    if (window.AndroidBridge && window.AndroidBridge.toggleMic) {
      const active = window.AndroidBridge.toggleMic();
      micState.isStreaming = active;
      updateMicUI();
      if (active) {
        showToast('Microfone Ativado (Streaming para o Mac)');
      } else {
        showToast('Microfone Desativado');
      }
    } else {
      // Browser simulation
      micState.isStreaming = !micState.isStreaming;
      updateMicUI();
      showToast(micState.isStreaming ? 'Microfone Ativado (Simulação)' : ' Microfone Desativado');
    }
  }
  window.toggleMicStream = toggleMicStream;

  function toggleMicMute() {
    triggerHaptic();
    if (window.AndroidBridge && window.AndroidBridge.toggleMicMute) {
      micState.isMuted = window.AndroidBridge.toggleMicMute();
    } else {
      micState.isMuted = !micState.isMuted;
    }
    updateMicUI();
    showToast(micState.isMuted ? ' Microfone Mutado' : 'Microfone Ao Vivo');
  }
  window.toggleMicMute = toggleMicMute;

  function onMicGainChange(val) {
    const gainNum = parseInt(val, 10) || 100;
    micState.gain = gainNum;
    const mult = gainNum / 100.0;
    if (window.AndroidBridge && window.AndroidBridge.setMicGain) {
      window.AndroidBridge.setMicGain(mult);
    }
    sendMacAction('set_mic_gain', { gain: mult });
    const valEl = getEl('cc-mic-gain-val');
    if (valEl) valEl.textContent = `${gainNum}%`;
  }
  window.onMicGainChange = onMicGainChange;

  function onNoiseReductionChange(enabled) {
    micState.noiseReduction = enabled;
    if (window.AndroidBridge && window.AndroidBridge.setNoiseReduction) {
      window.AndroidBridge.setNoiseReduction(enabled);
    }
    sendMacAction('set_mic_dsp', { enabled: enabled });
    updateMicUI();
    showToast(enabled ? 'DeepFilterNet3 IA Ativado no Mac' : 'Filtro DSP Desativado (Bypass)');
  }
  window.onNoiseReductionChange = onNoiseReductionChange;

  // Window callbacks called from Android Kotlin
  window.onMicLevelUpdate = function (level, isStreaming, isMuted) {
    micState.level = level;
    micState.isStreaming = isStreaming;
    micState.isMuted = isMuted;
    updateMicUI();
  };

  window.onMicStateChanged = function (isStreaming) {
    micState.isStreaming = isStreaming;
    if (!isStreaming) micState.level = 0;
    updateMicUI();
  };

  window.onMicPermissionResult = function (granted) {
    if (!granted) {
      showToast('Permissão de microfone necessária');
    } else {
      showToast('Microfone pronto e transmitindo!');
    }
  };

  // ==========================================================================
  // 5. Initialization & Events
  // ==========================================================================
  function bootstrap() {
    initElements();
    initSwipeGestures();
    initSliders();
    initScrubber();
    initColorWheelEvents();
    renderRecentSwatchesGrid();
    // Load persisted dock configuration if available
    try {
      const savedDeck = localStorage.getItem('mactouchbar_deck_config');
      if (savedDeck) {
        const parsed = JSON.parse(savedDeck);
        if (parsed.rows && parsed.cols) {
          state.deckRows = parsed.rows;
          state.deckCols = parsed.cols;
          const grid = el.deckGrid || getEl('deck-grid');
          if (grid) {
            grid.style.gridTemplateColumns = `repeat(${parsed.cols}, 1fr)`;
            grid.style.gridTemplateRows = `repeat(${parsed.rows}, 1fr)`;
          }
        }
        if (Array.isArray(parsed.buttons) && parsed.buttons.length > 0) {
          state.buttons = parsed.buttons;
          renderDeckButtons(state.buttons);
        } else {
          renderDeckButtons(DEFAULT_DECK);
        }
      } else {
        renderDeckButtons(DEFAULT_DECK);
      }
    } catch (e) {
      renderDeckButtons(DEFAULT_DECK);
    }

    // Listen for live dock updates from parent Mac app
    window.addEventListener('message', (event) => {
      if (!event.data) return;
      if (event.data.type === 'deck_config_update') {
        const data = event.data;
        if (data.rows && data.cols) {
          state.deckRows = data.rows;
          state.deckCols = data.cols;
          const grid = el.deckGrid || getEl('deck-grid');
          if (grid) {
            grid.style.gridTemplateColumns = `repeat(${data.cols}, 1fr)`;
            grid.style.gridTemplateRows = `repeat(${data.rows}, 1fr)`;
          }
        }
        if (Array.isArray(data.buttons) && data.buttons.length > 0) {
          state.buttons = data.buttons;
          renderDeckButtons(state.buttons);
          try {
            localStorage.setItem('mactouchbar_deck_config', JSON.stringify({
              rows: state.deckRows,
              cols: state.deckCols,
              buttons: state.buttons
            }));
          } catch(err) {}
        }
      }
    });
    renderRecentIllustratorColors();
    updateMicUI();
    initVerticalAddonScrollTracking();

    // Initialize preferred Color Picker Mode
    setColorPickerMode(aiState.pickerMode);

    const btnSettings = el.btnConnSettings || getEl('btn-conn-settings');
    if (btnSettings) {
      btnSettings.addEventListener('click', () => {
        triggerHaptic();
        const inpIp = el.inputIp || getEl('input-mac-ip');
        const inpPort = el.inputPort || getEl('input-mac-port');
        if (inpIp) inpIp.value = state.macIp;
        if (inpPort) inpPort.value = state.macPort;
        const modal = el.modalConn || getEl('modal-conn-setup');
        if (modal) modal.classList.add('active');
      });
    }

    const btnSave = el.btnSaveConnect || getEl('btn-save-connect');
    if (btnSave) {
      btnSave.addEventListener('click', () => {
        const inpIp = el.inputIp || getEl('input-mac-ip');
        const inpPort = el.inputPort || getEl('input-mac-port');
        const ip = inpIp ? inpIp.value.trim() : state.macIp;
        const port = inpPort ? inpPort.value.trim() : state.macPort;
        if (ip) {
          connectWebSocket(ip, port);
        }
      });
    }

    // Restore cached wallpaper if available
    const cachedWallpaper = localStorage.getItem('mac_touchbar_custom_wallpaper');
    if (cachedWallpaper) {
      setGlobalWallpaper(cachedWallpaper);
    }

    // Start on Screen 1 (Central Deck 2x6)
    goToScreen(1);

    // If running in Android, get IP from bridge if available
    if (window.AndroidBridge) {
      const bridgeIp = window.AndroidBridge.getMacIp ? window.AndroidBridge.getMacIp() : window.AndroidBridge.getSavedIp();
      if (bridgeIp && bridgeIp.length > 5 && bridgeIp !== '127.0.0.1') {
        state.macIp = bridgeIp;
      } else {
        state.macIp = '192.168.1.6';
      }
    }

    // Start WebSocket
    connectWebSocket();

    // Initialize local phone battery tracking
    initPhoneBattery();
  }

  function setGlobalWallpaper(bgUrl) {
    if (!bgUrl) return;
    document.documentElement.style.setProperty('--app-wallpaper', bgUrl);
    document.body.style.backgroundImage = bgUrl;
    const screenCc = getEl('screen-cc');
    if (screenCc) {
      screenCc.style.backgroundImage = bgUrl;
    }
    try {
      localStorage.setItem('mac_touchbar_custom_wallpaper', bgUrl);
    } catch (e) {}
  }
  window.setGlobalWallpaper = setGlobalWallpaper;

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bootstrap);
  } else {
    bootstrap();
  }

})();



  // =========================================================================
  // ETAPA 1: PRECISION SLIDERS & HAPTIC ROTARY JOG-WHEEL ENGINE
  // =========================================================================
  function triggerHaptic(type = 'selection') {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.macNative) {
        window.webkit.messageHandlers.macNative.postMessage({ action: 'haptic', type: type });
      } else if (window.AndroidBridge && window.AndroidBridge.vibrate) {
        window.AndroidBridge.vibrate(type === 'medium' ? 14 : 8);
      } else if (navigator.vibrate) {
        navigator.vibrate(type === 'medium' ? 12 : 6);
      }
    } catch (e) {}
  }
  window.triggerHaptic = triggerHaptic;

  let tactileSlidersState = {
    brush_size: { val: 32, min: 1, max: 128, step: 4, unit: 'px', lastHapticStep: 8 },
    opacity: { val: 100, min: 0, max: 100, step: 5, unit: '%', lastHapticStep: 20 },
    zoom: { val: 100, min: 25, max: 400, step: 15, unit: '%', lastHapticStep: 6 }
  };

  let activeSliderDrag = null;

  function initTactileSliders() {
    const wraps = document.querySelectorAll('.tactile-slider-wrap');
    wraps.forEach(wrap => {
      const param = wrap.dataset.param;
      if (!param || !tactileSlidersState[param]) return;

      const onPointerDown = (e) => {
        activeSliderDrag = {
          wrap: wrap,
          param: param,
          rect: wrap.getBoundingClientRect()
        };
        updateSliderFromPointer(e.clientX || (e.touches && e.touches[0].clientX));
        triggerHaptic('selection');
        e.preventDefault();
      };

      wrap.addEventListener('mousedown', onPointerDown);
      wrap.addEventListener('touchstart', onPointerDown, { passive: false });
    });

    window.addEventListener('mousemove', (e) => {
      if (activeSliderDrag) {
        updateSliderFromPointer(e.clientX);
        e.preventDefault();
      }
    });

    window.addEventListener('touchmove', (e) => {
      if (activeSliderDrag && e.touches && e.touches[0]) {
        updateSliderFromPointer(e.touches[0].clientX);
        e.preventDefault();
      }
    }, { passive: false });

    const onPointerUp = () => {
      if (activeSliderDrag) {
        triggerHaptic('light');
        activeSliderDrag = null;
      }
    };
    window.addEventListener('mouseup', onPointerUp);
    window.addEventListener('touchend', onPointerUp);
  }

  function updateSliderFromPointer(clientX) {
    if (!activeSliderDrag) return;
    const { wrap, param, rect } = activeSliderDrag;
    const cfg = tactileSlidersState[param];
    if (!cfg || !rect) return;

    let ratio = (clientX - rect.left) / rect.width;
    ratio = Math.max(0, Math.min(1, ratio));

    const rawVal = cfg.min + ratio * (cfg.max - cfg.min);
    const steppedVal = Math.round(rawVal / cfg.step) * cfg.step;
    const finalVal = Math.max(cfg.min, Math.min(cfg.max, steppedVal));

    // Check step crossing for haptic feedback
    const stepIndex = Math.floor(finalVal / cfg.step);
    if (stepIndex !== cfg.lastHapticStep) {
      cfg.lastHapticStep = stepIndex;
      triggerHaptic('selection');
    }

    setSliderValue(param, finalVal, false);
  }

  function setSliderValue(param, val, dispatchHaptic = true) {
    const cfg = tactileSlidersState[param];
    if (!cfg) return;
    cfg.val = Math.max(cfg.min, Math.min(cfg.max, val));

    const ratio = (cfg.val - cfg.min) / (cfg.max - cfg.min);
    const percent = Math.round(ratio * 100);

    // Update UI elements
    const capParam = param.charAt(0).toUpperCase() + param.slice(1);
    const camel = param.replace(/_([a-z])/g, g => g[1].toUpperCase());
    const camelCap = camel.charAt(0).toUpperCase() + camel.slice(1);

    const fill = document.getElementById(`sliderFill${camelCap}`);
    const thumb = document.getElementById(`sliderThumb${camelCap}`);
    const badge = document.getElementById(`val${camelCap}`);

    if (fill) fill.style.width = `${percent}%`;
    if (thumb) thumb.style.left = `${percent}%`;
    if (badge) badge.textContent = `${cfg.val} ${cfg.unit}`;

    if (dispatchHaptic) triggerHaptic('selection');

    // Dispatch WebSocket action to Mac
    if (typeof sendMacAction === 'function') {
      sendMacAction('illustrator_slider', { param: param, value: cfg.val, unit: cfg.unit });
    }
  }
  window.setSliderValue = setSliderValue;

  // Rotary Jog-Wheel Engine
  let currentJogAngle = 0;
  let isJogDragging = false;
  let jogLastHapticStep = 0;

  function initRotaryJogWheel() {
    const container = document.getElementById('rotaryWheelContainer');
    if (!container) return;

    const onStart = (e) => {
      isJogDragging = true;
      updateJogFromPointer(e.clientX || (e.touches && e.touches[0].clientX), e.clientY || (e.touches && e.touches[0].clientY));
      triggerHaptic('selection');
      e.preventDefault();
    };

    container.addEventListener('mousedown', onStart);
    container.addEventListener('touchstart', onStart, { passive: false });

    window.addEventListener('mousemove', (e) => {
      if (isJogDragging) {
        updateJogFromPointer(e.clientX, e.clientY);
        e.preventDefault();
      }
    });

    window.addEventListener('touchmove', (e) => {
      if (isJogDragging && e.touches && e.touches[0]) {
        updateJogFromPointer(e.touches[0].clientX, e.touches[0].clientY);
        e.preventDefault();
      }
    }, { passive: false });

    const onEnd = () => {
      if (isJogDragging) {
        isJogDragging = false;
        triggerHaptic('light');
      }
    };
    window.addEventListener('mouseup', onEnd);
    window.addEventListener('touchend', onEnd);
  }

  function updateJogFromPointer(clientX, clientY) {
    const container = document.getElementById('rotaryWheelContainer');
    if (!container) return;
    const rect = container.getBoundingClientRect();
    const cx = rect.left + rect.width / 2;
    const cy = rect.top + rect.height / 2;

    const dx = clientX - cx;
    const dy = clientY - cy;
    let rad = Math.atan2(dy, dx);
    let deg = Math.round(rad * (180 / Math.PI)) + 90;
    if (deg < 0) deg += 360;

    applyJogAngle(deg);
  }

  function applyJogAngle(deg, dispatchHaptic = true) {
    currentJogAngle = Math.round(deg) % 360;
    if (currentJogAngle < 0) currentJogAngle += 360;

    const ring = document.getElementById('rotaryWheelRing');
    const label = document.getElementById('rotaryAngleVal');

    if (ring) ring.style.transform = `rotate(${currentJogAngle}deg)`;
    if (label) label.textContent = `${currentJogAngle}°`;

    // 15° Detent Haptics
    const step15 = Math.floor(currentJogAngle / 15);
    if (step15 !== jogLastHapticStep) {
      jogLastHapticStep = step15;
      if (dispatchHaptic) triggerHaptic('selection');
    }

    if (typeof sendMacAction === 'function') {
      sendMacAction('illustrator_jog_wheel', { angle: currentJogAngle });
    }
  }

  function stepJogWheel(delta) {
    applyJogAngle(currentJogAngle + delta);
    triggerHaptic('medium');
  }
  window.stepJogWheel = stepJogWheel;

  function resetJogWheel() {
    applyJogAngle(0);
    triggerHaptic('medium');
  }
  window.resetJogWheel = resetJogWheel;

  // Photoshop Blend Modes UI Active Toggle
  function setPsBlendActive(btn) {
    if (!btn) return;
    const pills = document.querySelectorAll('.ps-blend-pill');
    pills.forEach(p => p.classList.remove('active'));
    btn.classList.add('active');
  }
  window.setPsBlendActive = setPsBlendActive;

  // Auto-init tactile sliders & jog-wheel
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      if (typeof initTactileSliders === 'function') initTactileSliders();
      if (typeof initRotaryJogWheel === 'function') initRotaryJogWheel();
    });
  } else {
    if (typeof initTactileSliders === 'function') initTactileSliders();
    if (typeof initRotaryJogWheel === 'function') initRotaryJogWheel();
  }

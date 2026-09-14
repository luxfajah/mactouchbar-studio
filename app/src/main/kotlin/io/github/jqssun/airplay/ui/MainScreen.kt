package io.github.jqssun.airplay.ui

import android.app.Activity
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.view.View
import android.view.WindowManager
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn as AndroidxOptIn
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Article
import androidx.compose.material.icons.automirrored.rounded.VolumeDown
import androidx.compose.material.icons.automirrored.rounded.VolumeOff
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.github.jqssun.airplay.R
import io.github.jqssun.airplay.service.AirPlayService.ServerState
import io.github.jqssun.airplay.ui.gestures.*
import io.github.jqssun.airplay.ui.theme.*
import io.github.jqssun.airplay.viewmodel.DebugInfo
import io.github.jqssun.airplay.viewmodel.MainViewModel
import kotlinx.coroutines.delay
import kotlin.math.abs

enum class Tab(val label: String, val icon: ImageVector) {
    OVERVIEW("Transmissão", Icons.Rounded.Cast),
    DIAGNOSTICS("Diagnóstico", Icons.Rounded.Analytics),
    SETTINGS("Ajustes", Icons.Rounded.Settings),
    LOGS("Console", Icons.AutoMirrored.Filled.Article)
}

@Composable
fun MainScreen(
    viewModel: MainViewModel,
    isInPip: Boolean = false,
    onSurfaceAvailable: (android.view.Surface) -> Unit,
    onSurfaceDestroyed: (android.view.Surface) -> Unit,
    onPip: () -> Unit = {}
) {
    var currentTab by remember { mutableStateOf(Tab.OVERVIEW) }
    var userExitedFullscreen by remember { mutableStateOf(false) }
    val pin by viewModel.pinCode.collectAsState()
    val connections by viewModel.connectionCount.collectAsState()
    val audioOnly by viewModel.audioOnly.collectAsState()
    val videoPlaybackActive by viewModel.videoPlaybackActive.collectAsState()
    val videoSessionPending by viewModel.videoSessionPending.collectAsState()
    val mirroringActive by viewModel.mirroringActive.collectAsState()
    val serverState by viewModel.serverState.collectAsState()

    val video: @Composable () -> Unit = {
        val aspect by viewModel.videoAspect.collectAsState()
        VideoSurfaceView(
            onSurfaceAvailable = onSurfaceAvailable,
            onSurfaceDestroyed = onSurfaceDestroyed,
            aspectRatio = aspect
        )
    }

    // Reset userExitedFullscreen when connections drop to 0
    LaunchedEffect(connections) {
        if (connections == 0) userExitedFullscreen = false
    }

    val isMirroring = serverState == ServerState.RUNNING && mirroringActive && !audioOnly && connections > 0
    val showFullscreenMirroring = isMirroring && !userExitedFullscreen && pin == null

    val activity = LocalContext.current as? Activity
    val videoScreen = videoPlaybackActive || videoSessionPending || showFullscreenMirroring

    // Force hide system bars and caption bar on DeX
    LaunchedEffect(videoScreen, showFullscreenMirroring) {
        val window = activity?.window ?: return@LaunchedEffect
        window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller.hide(
            WindowInsetsCompat.Type.systemBars() or
            WindowInsetsCompat.Type.captionBar() or
            WindowInsetsCompat.Type.statusBars() or
            WindowInsetsCompat.Type.navigationBars()
        )
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE

        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            or View.SYSTEM_UI_FLAG_FULLSCREEN
            or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
            or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        )
    }

    // HLS / Video file streaming mode
    if (videoPlaybackActive || videoSessionPending) {
        val videoPlaybackAspect by viewModel.videoPlaybackAspect.collectAsState()
        val playback: @Composable () -> Unit = {
            VideoSurfaceView(
                onSurfaceAvailable = { viewModel.onVideoPlaybackSurfaceAvailable(it) },
                onSurfaceDestroyed = { viewModel.onVideoPlaybackSurfaceDestroyed(it) },
                aspectRatio = videoPlaybackAspect
            )
        }
        if (isInPip) {
            Box(
                modifier = Modifier.fillMaxSize().background(Color.Black),
                contentAlignment = Alignment.Center
            ) {
                playback()
            }
            return
        }
        val overlayTick by viewModel.videoOverlayTick.collectAsState()
        val playing by viewModel.videoPlaying.collectAsState()
        val positionMs by viewModel.videoPositionMs.collectAsState()
        val durationMs by viewModel.videoDurationMs.collectAsState()
        val scrubPositionMs by viewModel.videoScrubPositionMs.collectAsState()
        val downloadProgress by viewModel.videoDownloadProgress.collectAsState()
        val scrubbing = scrubPositionMs != null
        val downloading = downloadProgress != null
        var overlayVisible by remember { mutableStateOf(false) }
        LaunchedEffect(overlayTick, playing, scrubbing, downloading, videoPlaybackActive) {
            if (!videoPlaybackActive) {
                overlayVisible = true
            } else if (overlayTick == 0L) {
                overlayVisible = false
            } else {
                overlayVisible = true
                if (playing && !scrubbing && !downloading) {
                    delay(VIDEO_OVERLAY_HIDE_MS)
                    overlayVisible = false
                }
            }
        }
        val gestureScope = rememberCoroutineScope()
        val tapGestureState = remember(viewModel) { TapGestureState(viewModel, gestureScope) }
        val seekGestureState = remember(viewModel) { SeekGestureState(viewModel) }
        val context = LocalContext.current
        val volumeState = remember { VolumeState(context) }
        val brightnessState = remember(activity) { activity?.window?.let { BrightnessState(it) } }
        val volumeAndBrightnessGestureState = remember(volumeState, brightnessState) {
            VolumeAndBrightnessGestureState(volumeState, brightnessState, gestureScope)
        }
        val zoomState = remember(viewModel) { ZoomState(viewModel, gestureScope) }
        var controlsLocked by remember { mutableStateOf(false) }
        DisposableEffect(volumeState) { volumeState.handleLifecycle(this) }
        LaunchedEffect(overlayTick) {
            if (overlayTick == 0L) {
                zoomState.reset()
                controlsLocked = false
            }
        }
        DisposableEffect(brightnessState) {
            onDispose { brightnessState?.clearOverride() }
        }
        LaunchedEffect(videoPlaybackAspect) {
            activity?.requestedOrientation = if (videoPlaybackAspect < 1f) {
                ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
            } else {
                ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            }
        }
        DisposableEffect(activity) {
            onDispose { activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED }
        }
        val videoPlaybackSize by viewModel.videoPlaybackSize.collectAsState()
        val buffering by viewModel.videoBuffering.collectAsState()
        val rootFocusRequester = remember { FocusRequester() }
        val playPauseFocusRequester = remember { FocusRequester() }
        val unlockFocusRequester = remember { FocusRequester() }
        var isPlayPauseFocused by remember { mutableStateOf(false) }
        var isUnlockFocused by remember { mutableStateOf(false) }
        var showSpeedSelector by remember { mutableStateOf(false) }
        val speed by viewModel.videoSpeed.collectAsState()
        val videoTitle by viewModel.videoTitle.collectAsState()
        val videoLocation by viewModel.videoLocation.collectAsState()
        val isPipSupported = remember {
            android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O &&
                context.packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)
        }

        var dpadSeekActive by remember { mutableStateOf(false) }
        var dpadSeekOffsetMs by remember { mutableLongStateOf(0L) }
        var dpadSeekTargetMs by remember { mutableLongStateOf(0L) }
        var dpadSeekTick by remember { mutableIntStateOf(0) }
        LaunchedEffect(dpadSeekTick) {
            if (!dpadSeekActive) return@LaunchedEffect
            delay(1000)
            dpadSeekActive = false
        }
        val showDpadSeekFeedback: (Long) -> Unit = { deltaMs ->
            if (!dpadSeekActive) dpadSeekOffsetMs = 0L
            dpadSeekOffsetMs += deltaMs
            dpadSeekTargetMs = (dpadSeekTargetMs.takeIf { dpadSeekActive } ?: positionMs).plus(deltaMs)
                .coerceIn(0L, if (durationMs > 0) durationMs else Long.MAX_VALUE)
            dpadSeekActive = true
            dpadSeekTick++
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black)
                .focusRequester(rootFocusRequester)
                .focusable()
                .onPreviewKeyEvent { keyEvent ->
                    if (showSpeedSelector) {
                        false
                    } else {
                        handlePlayerKeyEvent(
                            keyEvent = keyEvent,
                            controlsVisible = overlayVisible,
                            controlsLocked = controlsLocked,
                            isPlayPauseFocused = isPlayPauseFocused,
                            seekIncrementMs = TapGestureState.SEEK_INCREMENT_MS,
                            viewModel = viewModel,
                            showControls = { viewModel.showVideoOverlay() },
                            unlockControls = {
                                controlsLocked = false
                                viewModel.showVideoOverlay()
                            },
                            onDpadSeek = showDpadSeekFeedback,
                        )
                    }
                },
            contentAlignment = Alignment.Center
        ) {
            VideoContentFrame(
                aspect = videoPlaybackAspect,
                videoSizePx = videoPlaybackSize,
                contentScale = zoomState.contentScale,
                zoom = zoomState.zoom
            ) { sizeModifier ->
                VideoSurfaceView(
                    onSurfaceAvailable = { viewModel.onVideoPlaybackSurfaceAvailable(it) },
                    onSurfaceDestroyed = { viewModel.onVideoPlaybackSurfaceDestroyed(it) },
                    applyAspectRatio = false,
                    modifier = sizeModifier
                )
            }
            VideoPlayerGestures(
                enabled = videoPlaybackActive,
                locked = controlsLocked,
                onTap = {
                    if (!videoPlaybackActive) return@VideoPlayerGestures
                    if (overlayVisible) overlayVisible = false else viewModel.showVideoOverlay()
                },
                tapGestureState = tapGestureState,
                seekGestureState = seekGestureState,
                volumeAndBrightnessGestureState = volumeAndBrightnessGestureState,
                zoomState = zoomState
            )
            androidx.compose.animation.AnimatedVisibility(
                visible = overlayVisible && videoPlaybackActive && !controlsLocked,
                enter = androidx.compose.animation.fadeIn(),
                exit = androidx.compose.animation.fadeOut()
            ) {
                Box(modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.3f)))
            }
            if (buffering) {
                CircularProgressIndicator(modifier = Modifier.align(Alignment.Center).size(72.dp), color = AppleSystemBlue)
            }
            DoubleTapIndicator(tapGestureState = tapGestureState)
            val seekAmountMs = seekGestureState.seekAmountMs
            when {
                seekAmountMs != null -> GestureInfoText(
                    info = "${if (seekAmountMs < 0) "-" else "+"}${formatVideoTime(abs(seekAmountMs))}\n" +
                        "[${formatVideoTime(seekGestureState.targetPositionMs ?: 0)}]",
                    modifier = Modifier.align(Alignment.Center)
                )
                zoomState.isZooming -> GestureInfoText(
                    info = "${(zoomState.zoom * 100).toInt()}%",
                    modifier = Modifier.align(Alignment.Center)
                )
                zoomState.showContentScaleIndicator -> GestureInfoText(
                    info = stringResource(zoomState.contentScale.nameRes()),
                    modifier = Modifier.align(Alignment.Center)
                )
                else -> androidx.compose.animation.AnimatedVisibility(
                    visible = overlayVisible && videoPlaybackActive && !controlsLocked,
                    enter = androidx.compose.animation.fadeIn(),
                    exit = androidx.compose.animation.fadeOut(),
                    modifier = Modifier.align(Alignment.Center)
                ) {
                    PlayPauseButton(
                        playing = playing,
                        onClick = { viewModel.toggleVideoPlayPause() },
                        modifier = Modifier
                            .focusRequester(playPauseFocusRequester)
                            .onFocusChanged { isPlayPauseFocused = it.hasFocus }
                    )
                }
            }
            DpadSeekIndicator(
                visible = dpadSeekActive && dpadSeekOffsetMs != 0L,
                offsetMs = dpadSeekOffsetMs,
                positionMs = dpadSeekTargetMs
            )
            androidx.compose.animation.AnimatedVisibility(
                visible = volumeAndBrightnessGestureState.activeGesture == VerticalGesture.VOLUME,
                enter = androidx.compose.animation.fadeIn(),
                exit = androidx.compose.animation.fadeOut(),
                modifier = Modifier.align(Alignment.CenterStart).padding(24.dp)
            ) {
                VerticalProgressIndicator(value = volumeState.percentage, icon = Icons.AutoMirrored.Rounded.VolumeUp)
            }
            androidx.compose.animation.AnimatedVisibility(
                visible = volumeAndBrightnessGestureState.activeGesture == VerticalGesture.BRIGHTNESS,
                enter = androidx.compose.animation.fadeIn(),
                exit = androidx.compose.animation.fadeOut(),
                modifier = Modifier.align(Alignment.CenterEnd).padding(24.dp)
            ) {
                VerticalProgressIndicator(value = brightnessState?.percentage ?: 0, icon = Icons.Rounded.BrightnessHigh)
            }
            if (controlsLocked) {
                if (overlayVisible) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .safeDrawingPadding()
                            .padding(top = 24.dp)
                    ) {
                        UnlockButton(
                            onClick = {
                                controlsLocked = false
                                viewModel.showVideoOverlay()
                            },
                            modifier = Modifier
                                .focusRequester(unlockFocusRequester)
                                .onFocusChanged { isUnlockFocused = it.hasFocus }
                        )
                    }
                }
            } else {
                androidx.compose.animation.AnimatedVisibility(
                    visible = overlayVisible,
                    enter = androidx.compose.animation.fadeIn(),
                    exit = androidx.compose.animation.fadeOut(),
                    modifier = Modifier.align(Alignment.TopCenter)
                ) {
                    VideoControlsTop(
                        title = videoTitle,
                        videoUrl = videoLocation,
                        downloadProgress = downloadProgress,
                        showDownload = durationMs > 0,
                        onBackClick = { viewModel.stopVideoPlayback() },
                        onSpeedClick = {
                            overlayVisible = false
                            showSpeedSelector = true
                        },
                        onDownloadClick = { viewModel.toggleVideoDownload() }
                    )
                }
                androidx.compose.animation.AnimatedVisibility(
                    visible = overlayVisible,
                    enter = androidx.compose.animation.fadeIn(),
                    exit = androidx.compose.animation.fadeOut(),
                    modifier = Modifier.align(Alignment.BottomCenter)
                ) {
                    VideoControlsBottom(
                        positionMs = scrubPositionMs ?: positionMs,
                        durationMs = durationMs,
                        contentScale = zoomState.contentScale,
                        isPipSupported = isPipSupported,
                        onRotateClick = {
                            activity?.let {
                                it.requestedOrientation =
                                    if (it.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE) {
                                        ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
                                    } else {
                                        ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                                    }
                            }
                        },
                        onLockClick = {
                            viewModel.showVideoOverlay()
                            controlsLocked = true
                        },
                        onContentScaleClick = {
                            viewModel.showVideoOverlay()
                            zoomState.switchToNextContentScale()
                        },
                        onPipClick = onPip,
                        onSeek = { seekGestureState.onSeek(it) },
                        onSeekEnd = { seekGestureState.onSeekEnd() },
                        seekBarModifier = Modifier
                            .focusProperties { up = playPauseFocusRequester }
                            .dpadAdjust(
                                onLeft = {
                                    viewModel.seekVideoBy(-TapGestureState.SEEK_INCREMENT_MS)
                                    viewModel.showVideoOverlay()
                                },
                                onRight = {
                                    viewModel.seekVideoBy(TapGestureState.SEEK_INCREMENT_MS)
                                    viewModel.showVideoOverlay()
                                }
                            )
                    )
                }
            }
            val skipSilence by viewModel.videoSkipSilence.collectAsState()
            PlaybackSpeedSelector(
                show = showSpeedSelector,
                speed = speed,
                skipSilence = skipSilence,
                onSpeedChange = { viewModel.setVideoSpeed(it) },
                onSkipSilenceChange = { viewModel.setVideoSkipSilence(it) },
                onDismiss = { showSpeedSelector = false }
            )
        }
        return
    }

    if (isInPip) {
        Box(
            modifier = Modifier.fillMaxSize().background(Color.Black),
            contentAlignment = Alignment.Center
        ) {
            video()
        }
        return
    }

    // Direct Edge-to-Edge Fullscreen Mirroring (No borders, no bars)
    if (showFullscreenMirroring) {
        BackHandler { userExitedFullscreen = true }
        FullscreenMirroring(
            viewModel = viewModel,
            video = video,
            onExitFullscreen = { userExitedFullscreen = true },
            onPip = onPip
        )
        return
    }

    // Standard iPadOS Minimalist Screen for DeX
    val configuration = LocalConfiguration.current
    val isWideScreen = configuration.screenWidthDp >= 600

    if (isWideScreen) {
        // Ultra-Minimal Dual Column Layout (No Borders)
        Row(modifier = Modifier.fillMaxSize().background(AppleLightBg)) {
            AppleSidebar(
                currentTab = currentTab,
                onTabSelected = { currentTab = it },
                viewModel = viewModel,
                modifier = Modifier.width(280.dp).fillMaxHeight()
            )

            // Main Content Area (Borderless White Surface)
            Surface(
                color = AppleCardBg,
                shape = RoundedCornerShape(20.dp),
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .padding(top = 10.dp, end = 10.dp, bottom = 10.dp)
            ) {
                Column(modifier = Modifier.fillMaxSize()) {
                    AppleWindowHeader(
                        tab = currentTab,
                        viewModel = viewModel,
                        onFullscreen = { userExitedFullscreen = false },
                        onPip = onPip
                    )
                    Box(modifier = Modifier.weight(1f)) {
                        when (currentTab) {
                            Tab.OVERVIEW -> AppleOverviewContent(
                                viewModel = viewModel,
                                video = video,
                                onFullscreen = { userExitedFullscreen = false },
                                onPip = onPip
                            )
                            Tab.DIAGNOSTICS -> AppleDiagnosticsScreen(viewModel)
                            Tab.SETTINGS -> SettingsScreen(viewModel)
                            Tab.LOGS -> LogsScreen(viewModel)
                        }
                    }
                }
            }
        }
    } else {
        // Adaptive Compact Layout
        Scaffold(
            containerColor = AppleLightBg,
            bottomBar = {
                NavigationBar(
                    containerColor = AppleCardBg,
                    tonalElevation = 0.dp
                ) {
                    Tab.entries.forEach { t ->
                        NavigationBarItem(
                            selected = currentTab == t,
                            onClick = { currentTab = t },
                            icon = { Icon(t.icon, contentDescription = t.label) },
                            label = { Text(t.label, fontSize = 11.sp, fontWeight = FontWeight.Medium) },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = AppleSystemBlue,
                                selectedTextColor = AppleSystemBlue,
                                unselectedIconColor = AppleLabelSecondary,
                                unselectedTextColor = AppleLabelSecondary,
                                indicatorColor = AppleSystemBlue.copy(alpha = 0.12f)
                            )
                        )
                    }
                }
            }
        ) { padding ->
            Box(modifier = Modifier.fillMaxSize().padding(padding)) {
                when (currentTab) {
                    Tab.OVERVIEW -> AppleOverviewContent(
                        viewModel = viewModel,
                        video = video,
                        onFullscreen = { userExitedFullscreen = false },
                        onPip = onPip
                    )
                    Tab.DIAGNOSTICS -> AppleDiagnosticsScreen(viewModel)
                    Tab.SETTINGS -> SettingsScreen(viewModel)
                    Tab.LOGS -> LogsScreen(viewModel)
                }
            }
        }
    }

    if (pin != null) {
        AlertDialog(
            onDismissRequest = { viewModel.dismissPin() },
            containerColor = AppleCardBg,
            shape = RoundedCornerShape(22.dp),
            title = {
                Text(
                    "Código de Pareamento AirPlay",
                    style = MaterialTheme.typography.titleMedium,
                    color = AppleLabelPrimary,
                    fontWeight = FontWeight.Bold
                )
            },
            text = {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                    Text("Digite o código abaixo no seu dispositivo Apple:", color = AppleLabelSecondary, fontSize = 14.sp)
                    Spacer(Modifier.height(16.dp))
                    Surface(
                        color = AppleLightBg,
                        shape = RoundedCornerShape(14.dp),
                        modifier = Modifier.padding(8.dp)
                    ) {
                        Text(
                            text = pin!!,
                            style = MaterialTheme.typography.displayMedium,
                            fontWeight = FontWeight.Bold,
                            color = AppleSystemBlue,
                            letterSpacing = 6.sp,
                            modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp)
                        )
                    }
                }
            },
            confirmButton = {
                Button(
                    onClick = { viewModel.dismissPin() },
                    colors = ButtonDefaults.buttonColors(containerColor = AppleSystemBlue),
                    shape = RoundedCornerShape(10.dp)
                ) {
                    Text("OK", color = Color.White, fontWeight = FontWeight.SemiBold)
                }
            }
        )
    }
}

@Composable
private fun AppleSidebar(
    currentTab: Tab,
    onTabSelected: (Tab) -> Unit,
    viewModel: MainViewModel,
    modifier: Modifier = Modifier
) {
    val state by viewModel.serverState.collectAsState()
    val connections by viewModel.connectionCount.collectAsState()
    val serverName by viewModel.serverName.collectAsState()
    val serverPort by viewModel.serverPort.collectAsState()
    val videoResolution by viewModel.videoResolution.collectAsState()

    Column(
        modifier = modifier
            .background(AppleSidebarBg)
            .padding(16.dp)
    ) {
        // App Header
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(vertical = 12.dp, horizontal = 4.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(
                        Brush.linearGradient(
                            listOf(AppleSystemBlue, AppleSystemIndigo)
                        )
                    ),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Rounded.Airplay,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(22.dp)
                )
            }
            Spacer(Modifier.width(12.dp))
            Column {
                Text(
                    text = "DeXPlay",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppleLabelPrimary
                )
                Text(
                    text = "AirPlay 2 Receiver",
                    fontSize = 12.sp,
                    color = AppleLabelSecondary
                )
            }
        }

        Spacer(Modifier.height(14.dp))

        // Minimalist Live Activity Capsule
        LiveActivityStatusCapsule(
            state = state,
            connections = connections,
            resolution = if (videoResolution.isNotEmpty()) videoResolution else "4K HighDPI"
        )

        Spacer(Modifier.height(16.dp))

        // Navigation Items
        Tab.entries.forEach { tab ->
            val isSelected = currentTab == tab
            val bgModifier = if (isSelected) {
                Modifier.background(AppleSystemBlue, RoundedCornerShape(12.dp))
            } else {
                Modifier.background(Color.Transparent)
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(44.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .then(bgModifier)
                    .clickable { onTabSelected(tab) }
                    .padding(horizontal = 14.dp)
            ) {
                Icon(
                    imageVector = tab.icon,
                    contentDescription = tab.label,
                    tint = if (isSelected) Color.White else AppleLabelSecondary,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(Modifier.width(12.dp))
                Text(
                    text = tab.label,
                    fontSize = 14.sp,
                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Medium,
                    color = if (isSelected) Color.White else AppleLabelPrimary
                )
            }
            Spacer(Modifier.height(4.dp))
        }

        Spacer(Modifier.weight(1f))

        // Bottom Server Status Lockup (Clean White Card)
        Surface(
            color = AppleCardBg,
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(
                                when (state) {
                                    ServerState.RUNNING -> AppleSystemGreen
                                    ServerState.ERROR -> AppleSystemRed
                                    ServerState.STOPPED -> AppleLabelTertiary
                                }
                            )
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = when (state) {
                            ServerState.RUNNING -> "Receptor Ativo"
                            ServerState.ERROR -> "Erro de Inicialização"
                            ServerState.STOPPED -> "Receptor Inativo"
                        },
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = when (state) {
                            ServerState.RUNNING -> AppleSystemGreen
                            ServerState.ERROR -> AppleSystemRed
                            ServerState.STOPPED -> AppleLabelSecondary
                        }
                    )
                }

                Spacer(Modifier.height(4.dp))
                Text(
                    text = "$serverName • Porta $serverPort",
                    fontSize = 11.sp,
                    color = AppleLabelSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )

                Spacer(Modifier.height(10.dp))

                Button(
                    onClick = {
                        if (state == ServerState.RUNNING) viewModel.stopServer()
                        else viewModel.startServer()
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (state == ServerState.RUNNING) AppleSystemRed.copy(alpha = 0.1f) else AppleSystemBlue.copy(alpha = 0.1f),
                        contentColor = if (state == ServerState.RUNNING) AppleSystemRed else AppleSystemBlue
                    ),
                    shape = RoundedCornerShape(10.dp),
                    contentPadding = PaddingValues(vertical = 8.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = if (state == ServerState.RUNNING) "Interromper" else "Iniciar Receptor",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
        }
    }
}

@Composable
private fun LiveActivityStatusCapsule(
    state: ServerState,
    connections: Int,
    resolution: String
) {
    val infiniteTransition = rememberInfiniteTransition(label = "pulse_capsule")
    val pulseAlpha by infiniteTransition.animateFloat(
        initialValue = 0.4f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1200, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulseAlpha"
    )

    Surface(
        color = AppleCardBg,
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(
                        if (state == ServerState.RUNNING) {
                            if (connections > 0) AppleSystemGreen else AppleSystemBlue.copy(alpha = pulseAlpha)
                        } else AppleLabelTertiary
                    )
            )
            Spacer(Modifier.width(8.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = when {
                        connections > 0 -> "Transmitindo Agora"
                        state == ServerState.RUNNING -> "Pronto • Bonjour Ativo"
                        else -> "Servidor Desligado"
                    },
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (connections > 0) AppleSystemGreen else AppleLabelPrimary
                )
                Text(
                    text = if (connections > 0) resolution else "HighDpi 4K @ 60 FPS",
                    fontSize = 10.sp,
                    color = AppleLabelSecondary
                )
            }
            if (connections > 0) {
                Surface(
                    color = AppleSystemGreen.copy(alpha = 0.15f),
                    shape = RoundedCornerShape(6.dp)
                ) {
                    Text(
                        text = "LIVE",
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        color = AppleSystemGreen,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                    )
                }
            }
        }
    }
}

@Composable
private fun AppleWindowHeader(
    tab: Tab,
    viewModel: MainViewModel,
    onFullscreen: () -> Unit,
    onPip: () -> Unit
) {
    val connections by viewModel.connectionCount.collectAsState()
    val mirroringActive by viewModel.mirroringActive.collectAsState()

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column {
            Text(
                text = tab.label,
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = AppleLabelPrimary
            )
            Text(
                text = if (connections > 0) "1 dispositivo conectado • Transmitindo em 4K" else "Aguardando transmissões AirPlay",
                fontSize = 12.sp,
                color = if (connections > 0) AppleSystemGreen else AppleLabelSecondary
            )
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            if (mirroringActive) {
                FilledTonalIconButton(
                    onClick = onPip,
                    colors = IconButtonDefaults.filledTonalIconButtonColors(
                        containerColor = AppleLightBg,
                        contentColor = AppleLabelPrimary
                    )
                ) {
                    Icon(painterResource(R.drawable.ic_pip), contentDescription = "PiP", modifier = Modifier.size(18.dp))
                }
                Spacer(Modifier.width(8.dp))
                FilledTonalIconButton(
                    onClick = onFullscreen,
                    colors = IconButtonDefaults.filledTonalIconButtonColors(
                        containerColor = AppleSystemBlue,
                        contentColor = Color.White
                    )
                ) {
                    Icon(Icons.Rounded.Fullscreen, contentDescription = "Tela Cheia", modifier = Modifier.size(20.dp))
                }
            }
        }
    }
}

@Composable
private fun AppleOverviewContent(
    viewModel: MainViewModel,
    video: @Composable () -> Unit,
    onFullscreen: () -> Unit,
    onPip: () -> Unit
) {
    val state by viewModel.serverState.collectAsState()
    val connections by viewModel.connectionCount.collectAsState()
    val serverName by viewModel.serverName.collectAsState()
    val audioOnly by viewModel.audioOnly.collectAsState()

    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        if (audioOnly && connections > 0) {
            NowPlayingContent(viewModel)
        } else {
            // Apple iPadOS Idle Ready Screen (Ultra Minimalist)
            AppleHeroIdleCard(serverName = serverName, state = state)
        }
    }
}

@Composable
private fun AppleHeroIdleCard(serverName: String, state: ServerState) {
    val infiniteTransition = rememberInfiniteTransition(label = "pulse_hero")
    val pulseScale by infiniteTransition.animateFloat(
        initialValue = 0.95f,
        targetValue = 1.05f,
        animationSpec = infiniteRepeatable(
            animation = tween(2200, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulseScale"
    )

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
    ) {
        // Concentric Apple Target Glow Rings
        Box(
            modifier = Modifier
                .size(104.dp)
                .scale(if (state == ServerState.RUNNING) pulseScale else 1f)
                .clip(CircleShape)
                .background(AppleSystemBlue.copy(alpha = 0.08f)),
            contentAlignment = Alignment.Center
        ) {
            Box(
                modifier = Modifier
                    .size(72.dp)
                    .clip(CircleShape)
                    .background(AppleSystemBlue.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Rounded.Airplay,
                    contentDescription = null,
                    tint = AppleSystemBlue,
                    modifier = Modifier.size(36.dp)
                )
            }
        }

        Spacer(Modifier.height(20.dp))

        Text(
            text = if (state == ServerState.RUNNING) "Pronto para Transmitir" else "Receptor AirPlay Parado",
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            color = AppleLabelPrimary
        )

        Spacer(Modifier.height(8.dp))

        Surface(
            color = AppleSystemBlue.copy(alpha = 0.1f),
            shape = RoundedCornerShape(10.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp)
            ) {
                Icon(Icons.Rounded.DesktopMac, contentDescription = null, tint = AppleSystemBlue, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text(
                    text = serverName,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppleSystemBlue
                )
            }
        }

        Spacer(Modifier.height(14.dp))

        Text(
            text = "No seu Mac, iPhone ou iPad, abra a Central de Controle, clique em Espelhamento de Tela e selecione este monitor para transmissão em 4K @ 60 FPS.",
            fontSize = 13.sp,
            color = AppleLabelSecondary,
            textAlign = TextAlign.Center,
            modifier = Modifier.widthIn(max = 440.dp)
        )

        Spacer(Modifier.height(24.dp))

        // Minimalist Feature Badges (Flat Pills)
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(horizontal = 8.dp)
        ) {
            AppleFeatureBadge(Icons.Rounded.Monitor, "4K HighDPI")
            AppleFeatureBadge(Icons.Rounded.Speed, "60 FPS")
            AppleFeatureBadge(Icons.Rounded.Headphones, "Oboe Audio")
            AppleFeatureBadge(Icons.Rounded.Tv, "Zero Overscan")
        }
    }
}

@Composable
private fun AppleFeatureBadge(icon: ImageVector, label: String) {
    Surface(
        color = ApplePillBg,
        shape = RoundedCornerShape(10.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp)
        ) {
            Icon(icon, contentDescription = null, tint = AppleSystemBlue, modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(6.dp))
            Text(label, fontSize = 11.sp, fontWeight = FontWeight.Medium, color = AppleLabelPrimary)
        }
    }
}

@Composable
private fun AppleDiagnosticsScreen(viewModel: MainViewModel) {
    val debugInfo by viewModel.debugInfo.collectAsState()
    val videoResolution by viewModel.videoResolution.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
    ) {
        Text("Telemetria e Desempenho", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = AppleLabelPrimary)
        Spacer(Modifier.height(16.dp))

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            AppleTelemetryCard("Resolução", if (videoResolution.isNotEmpty()) "$videoResolution (Retina)" else "3840x2160 (4K HighDPI)", Icons.Rounded.Monitor, AppleSystemBlue, Modifier.weight(1f))
            AppleTelemetryCard("Taxa de Quadros", "${debugInfo.videoFps} FPS", Icons.Rounded.Speed, AppleSystemGreen, Modifier.weight(1f))
        }

        Spacer(Modifier.height(12.dp))

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            AppleTelemetryCard("Bitrate", debugInfo.bitrateStr, Icons.Rounded.NetworkCheck, AppleSystemIndigo, Modifier.weight(1f))
            AppleTelemetryCard("Latência NTP / Jitter", debugInfo.jitterStr, Icons.Rounded.Timer, AppleSystemOrange, Modifier.weight(1f))
        }

        Spacer(Modifier.height(12.dp))

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            AppleTelemetryCard("Codec Ativo", if (debugInfo.videoCodec.isNotEmpty()) debugInfo.videoCodec else "H.264 / H.265 Hardware", Icons.Rounded.VideoLibrary, AppleSystemTeal, Modifier.weight(1f))
            AppleTelemetryCard("Frames Perdidos", "${debugInfo.droppedFrames}", Icons.Rounded.Warning, if (debugInfo.droppedFrames > 0) AppleSystemRed else AppleSystemGreen, Modifier.weight(1f))
        }
    }
}

@Composable
private fun AppleTelemetryCard(
    title: String,
    value: String,
    icon: ImageVector,
    accentColor: Color,
    modifier: Modifier = Modifier
) {
    Surface(
        color = AppleSecondaryCardBg,
        shape = RoundedCornerShape(16.dp),
        modifier = modifier
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(title, fontSize = 12.sp, color = AppleLabelSecondary, fontWeight = FontWeight.Medium)
                Icon(icon, contentDescription = null, tint = accentColor, modifier = Modifier.size(18.dp))
            }
            Spacer(Modifier.height(8.dp))
            Text(value, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = AppleLabelPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

private const val VIDEO_OVERLAY_HIDE_MS = 4000L

/**
 * Total Fullscreen Mirroring View (100% Screen, Edge-to-Edge, Zero Margins, Zero Borders)
 */
@Composable
private fun FullscreenMirroring(
    viewModel: MainViewModel,
    video: @Composable () -> Unit,
    onExitFullscreen: () -> Unit,
    onPip: () -> Unit
) {
    val videoResolution by viewModel.videoResolution.collectAsState()
    val debugEnabled by viewModel.debugEnabled.collectAsState()
    val debugInfo by viewModel.debugInfo.collectAsState()

    var controlsVisible by remember { mutableStateOf(false) }
    var tapTick by remember { mutableIntStateOf(0) }
    LaunchedEffect(tapTick) {
        if (tapTick > 0) {
            controlsVisible = true
            delay(4000)
            controlsVisible = false
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .pointerInput(Unit) { detectTapGestures { tapTick++ } },
        contentAlignment = Alignment.Center
    ) {
        // Fullscreen edge-to-edge video canvas
        video()

        // Sleek floating macOS glass pill controls (Auto-hides)
        androidx.compose.animation.AnimatedVisibility(
            visible = controlsVisible,
            enter = fadeIn() + slideInVertically { it / 2 },
            exit = fadeOut() + slideOutVertically { it / 2 },
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 24.dp)
        ) {
            Surface(
                color = Color.Black.copy(alpha = 0.75f),
                shape = RoundedCornerShape(24.dp),
                modifier = Modifier.padding(horizontal = 8.dp)
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (videoResolution.isNotEmpty()) {
                        Text(
                            text = videoResolution,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = AppleSystemTeal
                        )
                        Spacer(Modifier.width(12.dp))
                    }
                    IconButton(onClick = onPip, modifier = Modifier.size(36.dp)) {
                        Icon(painterResource(R.drawable.ic_pip), contentDescription = "PiP", tint = Color.White, modifier = Modifier.size(18.dp))
                    }
                    Spacer(Modifier.width(8.dp))
                    IconButton(onClick = onExitFullscreen, modifier = Modifier.size(36.dp)) {
                        Icon(Icons.Default.FullscreenExit, contentDescription = "Sair da Tela Cheia", tint = Color.White, modifier = Modifier.size(20.dp))
                    }
                }
            }
        }

        if (debugEnabled) {
            DebugOverlay(debugInfo, Modifier.align(Alignment.TopStart).padding(8.dp))
        }
    }
}

@Composable
private fun HoldScanButton(
    icon: ImageVector,
    contentDescription: String,
    onBegin: () -> Unit,
    onEnd: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .size(48.dp)
            .clip(CircleShape)
            .pointerInput(Unit) {
                detectTapGestures(onPress = {
                    onBegin()
                    try {
                        awaitRelease()
                    } finally {
                        onEnd()
                    }
                })
            },
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, contentDescription)
    }
}

@Composable
@AndroidxOptIn(androidx.media3.common.util.UnstableApi::class)
private fun NowPlayingContent(viewModel: MainViewModel) {
    val track by viewModel.trackInfo.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(
            modifier = Modifier
                .weight(1f, fill = false)
                .aspectRatio(1f)
                .fillMaxWidth(0.65f)
                .clip(RoundedCornerShape(20.dp))
                .background(AppleSecondaryCardBg),
            contentAlignment = Alignment.Center
        ) {
            if (track.coverArt != null) {
                Image(
                    bitmap = track.coverArt!!.asImageBitmap(),
                    contentDescription = stringResource(R.string.cd_cover_art),
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop
                )
            } else {
                Icon(
                    Icons.Default.MusicNote,
                    contentDescription = null,
                    modifier = Modifier.size(64.dp),
                    tint = AppleLabelSecondary.copy(alpha = 0.4f)
                )
            }
        }

        Spacer(Modifier.height(20.dp))

        Text(
            text = track.title.ifEmpty { stringResource(R.string.unknown_track) },
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = AppleLabelPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        if (track.artist.isNotEmpty()) {
            Text(
                text = track.artist,
                style = MaterialTheme.typography.bodyMedium,
                color = AppleLabelSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        if (track.album.isNotEmpty()) {
            Text(
                text = track.album,
                style = MaterialTheme.typography.bodySmall,
                color = AppleLabelTertiary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        Spacer(Modifier.height(16.dp))

        val player = viewModel.dacpPlayer
        if (player != null) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                androidx.media3.ui.compose.material3.indicator.PositionText(player, Modifier.padding(end = 8.dp))
                Box(modifier = Modifier.weight(1f)) { androidx.media3.ui.compose.material3.indicator.ProgressSlider(player) }
                androidx.media3.ui.compose.material3.indicator.DurationText(player, Modifier.padding(start = 8.dp))
            }

            Spacer(Modifier.height(8.dp))

            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                HoldScanButton(
                    icon = Icons.Default.FastRewind,
                    contentDescription = stringResource(R.string.cd_rewind),
                    onBegin = { viewModel.audioScanBegin(false) },
                    onEnd = { viewModel.audioScanEnd() }
                )
                androidx.media3.ui.compose.material3.buttons.PreviousButton(player, modifier = Modifier.dpadFocus())
                androidx.media3.ui.compose.material3.buttons.PlayPauseButton(
                    player,
                    modifier = Modifier.size(63.dp).dpadFocus(CircleShape),
                    iconSize = 40.dp
                )
                androidx.media3.ui.compose.material3.buttons.NextButton(player, modifier = Modifier.dpadFocus())
                HoldScanButton(
                    icon = Icons.Default.FastForward,
                    contentDescription = stringResource(R.string.cd_fast_forward),
                    onBegin = { viewModel.audioScanBegin(true) },
                    onEnd = { viewModel.audioScanEnd() }
                )
            }

            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                IconButton(onClick = { viewModel.audioVolumeDown() }, modifier = Modifier.dpadFocus()) {
                    Icon(Icons.AutoMirrored.Rounded.VolumeDown, stringResource(R.string.cd_volume_down), tint = AppleLabelPrimary)
                }
                IconButton(onClick = { viewModel.audioMuteToggle() }, modifier = Modifier.dpadFocus()) {
                    Icon(Icons.AutoMirrored.Rounded.VolumeOff, stringResource(R.string.cd_mute), tint = AppleLabelPrimary)
                }
                IconButton(onClick = { viewModel.audioVolumeUp() }, modifier = Modifier.dpadFocus()) {
                    Icon(Icons.AutoMirrored.Rounded.VolumeUp, stringResource(R.string.cd_volume_up), tint = AppleLabelPrimary)
                }
            }
        }
    }
}

@Composable
private fun DebugOverlay(info: DebugInfo, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .background(Color.Black.copy(alpha = 0.7f), RoundedCornerShape(8.dp))
            .padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        val style = MaterialTheme.typography.labelSmall
        val headingStyle = style.copy(fontWeight = FontWeight.Bold)
        val color = Color.White.copy(alpha = 0.9f)
        val headingColor = Color(0xFF80D8FF)
        val context = LocalContext.current
        debugOverlaySections(context, info).forEachIndexed { i, section ->
            if (i > 0) Spacer(Modifier.height(6.dp))
            Text(section.title.uppercase(), style = headingStyle, color = headingColor)
            section.lines.forEach { Text(it, style = style, color = color) }
        }
    }
}

private data class DebugSection(val title: String, val lines: List<String>)

private fun debugOverlaySections(androidContext: android.content.Context, info: DebugInfo): List<DebugSection> = buildList {
    buildList {
        if (info.videoCodec.isNotEmpty()) {
            add(androidContext.getString(R.string.debug_video, info.videoCodec, info.videoRes))
            add(androidContext.getString(R.string.debug_fps_bitrate, info.videoFps, info.bitrateStr))
            add(androidContext.getString(R.string.debug_frames_drops, info.videoFrames, info.droppedFrames))
            add(androidContext.getString(R.string.debug_jitter, info.jitterStr))
        }
    }.takeIf { it.isNotEmpty() }?.let { add(DebugSection(androidContext.getString(R.string.debug_section_video), it)) }

    buildList {
        if (info.audioCodec.isNotEmpty()) add(androidContext.getString(R.string.debug_audio, info.audioCodec, info.audioVolume))
        info.audio?.let { a ->
            add(androidContext.getString(R.string.debug_audio_buffer, a.backlogMs, a.tunedCushionMs))
            add(androidContext.getString(R.string.debug_audio_glitch, a.trims, a.drops, a.silences, a.underruns, a.xrun))
            add(androidContext.getString(R.string.debug_audio_decode, formatDecode(a.decodeMeanUs, a.decodeMaxUs, a.decodeHeld, a.decodeErrors)))
        }
    }.takeIf { it.isNotEmpty() }?.let { add(DebugSection(androidContext.getString(R.string.debug_section_audio), it)) }

    add(DebugSection(androidContext.getString(R.string.debug_section_network), listOf(androidContext.getString(R.string.debug_clients, info.connections))))
}

private fun formatDecode(meanUs: Int, maxUs: Int, held: Int, errors: Int): String =
    (if (meanUs == 0) "held=$held"
    else "%.1f/%.1f ms held=%d".format(meanUs / 1000.0, maxUs / 1000.0, held)) + " errs=$errors"

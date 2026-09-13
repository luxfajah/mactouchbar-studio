package io.github.luxfajah.touchbar.ui

import android.graphics.BitmapFactory
import android.graphics.Color.parseColor
import android.util.Base64
import android.view.HapticFeedbackConstants
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.luxfajah.touchbar.network.DeckButtonItem
import io.github.luxfajah.touchbar.network.TouchbarClient
import io.github.luxfajah.touchbar.network.TouchbarMediaInfo
import io.github.luxfajah.touchbar.ui.theme.ActiveBlue
import io.github.luxfajah.touchbar.ui.theme.ConnectedGreen
import io.github.luxfajah.touchbar.ui.theme.DisconnectedRed
import io.github.luxfajah.touchbar.ui.theme.TouchBarBackground
import io.github.luxfajah.touchbar.ui.theme.TouchBarButtonBorder
import io.github.luxfajah.touchbar.ui.theme.TouchBarFontFamily
import io.github.luxfajah.touchbar.ui.theme.TouchBarTextSecondary
import kotlinx.coroutines.launch

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun TouchbarScreen(
    client: TouchbarClient,
    modifier: Modifier = Modifier
) {
    val state by client.state.collectAsState()
    val pagerState = rememberPagerState(pageCount = { 4 })
    val coroutineScope = rememberCoroutineScope()

    val view = LocalView.current
    fun haptic() {
        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(TouchBarBackground)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 10.dp, vertical = 6.dp),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            // Top Navigation Bar
            TopNavigationBar(
                currentPage = pagerState.currentPage,
                onPageSelected = { page ->
                    haptic()
                    coroutineScope.launch { pagerState.animateScrollToPage(page) }
                },
                isConnected = state.isConnected,
                macName = state.macName,
                frontmostApp = state.frontmostApp,
                onReconnect = {
                    haptic()
                    client.startDiscovery()
                }
            )

            // Horizontal Swipeable Pages (4 Screens)
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(vertical = 4.dp)
            ) {
                HorizontalPager(
                    state = pagerState,
                    modifier = Modifier.fillMaxSize()
                ) { page ->
                    when (page) {
                        0 -> ShortcutsDeckScreen(
                            buttons = state.deckButtons,
                            onButtonClicked = { item ->
                                haptic()
                                client.executeDeckButton(item)
                            }
                        )
                        1 -> MacOSControlCenterScreen(
                            client = client,
                            volume = state.volume,
                            isMuted = state.isMuted,
                            brightness = state.brightness,
                            battery = state.battery,
                            isWifiEnabled = state.isWifiEnabled,
                            isBluetoothEnabled = state.isBluetoothEnabled,
                            isAirDropEnabled = state.isAirDropEnabled,
                            isFocusSleepEnabled = state.isFocusSleepEnabled,
                            isStageManagerEnabled = state.isStageManagerEnabled,
                            media = state.media,
                            onHaptic = { haptic() }
                        )
                        2 -> DedicatedMusicScreen(
                            media = state.media,
                            volume = state.volume,
                            isMuted = state.isMuted,
                            client = client,
                            onHaptic = { haptic() }
                        )
                        3 -> AppleEmojiKeyboardScreen(
                            onEmojiSelected = { emoji ->
                                haptic()
                                client.typeEmoji(emoji)
                            }
                        )
                    }
                }
            }

            // Bottom Dots Indicator
            BottomPageDots(
                pageCount = 4,
                currentPage = pagerState.currentPage,
                onDotClick = { page ->
                    haptic()
                    coroutineScope.launch { pagerState.animateScrollToPage(page) }
                }
            )
        }
    }
}

// MARK: - 1. Top Navigation Bar
@Composable
fun TopNavigationBar(
    currentPage: Int,
    onPageSelected: (Int) -> Unit,
    isConnected: Boolean,
    macName: String,
    frontmostApp: String,
    onReconnect: () -> Unit
) {
    val pageTitles = listOf("⚡️ Apps 2x6", "🎛️ Central de Controle", "🎵 Música", "😀 Emojis")

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 6.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.clickable(onClick = onReconnect)
        ) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(if (isConnected) ConnectedGreen else DisconnectedRed)
            )
            Spacer(modifier = Modifier.width(6.dp))
            Text(
                text = if (isConnected) "$macName • $frontmostApp" else "Buscando Mac...",
                color = TouchBarTextSecondary,
                fontSize = 11.sp,
                fontFamily = TouchBarFontFamily,
                fontWeight = FontWeight.Medium
            )
        }

        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            pageTitles.forEachIndexed { index, title ->
                val isSelected = (currentPage == index)
                Surface(
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .clickable { onPageSelected(index) },
                    color = if (isSelected) Color(0xFF2C2C2E) else Color(0xFF141416),
                    border = androidx.compose.foundation.BorderStroke(
                        1.dp,
                        if (isSelected) ActiveBlue else TouchBarButtonBorder
                    )
                ) {
                    Text(
                        text = title,
                        color = if (isSelected) Color.White else TouchBarTextSecondary,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Medium,
                        fontFamily = TouchBarFontFamily,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)
                    )
                }
            }
        }
    }
}

// MARK: - 2. Page 1: Shortcuts Deck Screen with Native Mac App Icons (2x6 Grid = 12 Buttons)
@Composable
fun ShortcutsDeckScreen(
    buttons: List<DeckButtonItem>,
    onButtonClicked: (DeckButtonItem) -> Unit
) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(6),
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 4.dp, vertical = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        items(buttons.take(12)) { item ->
            DeckGridButton(item = item, onClick = { onButtonClicked(item) })
        }
    }
}

@Composable
fun DeckGridButton(
    item: DeckButtonItem,
    onClick: () -> Unit
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()

    val customColor = remember(item.colorHex) {
        try {
            Color(parseColor(item.colorHex))
        } catch (_: Exception) {
            Color(0xFF1F1F24)
        }
    }

    val appIconBitmap = remember(item.iconBase64) {
        if (item.iconBase64.isNotEmpty()) {
            try {
                val decodedBytes = Base64.decode(item.iconBase64, Base64.DEFAULT)
                val bitmap = BitmapFactory.decodeByteArray(decodedBytes, 0, decodedBytes.size)
                bitmap?.asImageBitmap()
            } catch (_: Exception) {
                null
            }
        } else null
    }

    val bg = if (isPressed) Color(0xFF333338) else customColor

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(118.dp)
            .clip(RoundedCornerShape(14.dp))
            .border(1.dp, TouchBarButtonBorder, RoundedCornerShape(14.dp))
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick
            ),
        color = bg
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(8.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            if (appIconBitmap != null) {
                Image(
                    bitmap = appIconBitmap,
                    contentDescription = item.label,
                    modifier = Modifier
                        .size(56.dp)
                        .clip(RoundedCornerShape(12.dp))
                )
            } else {
                Text(
                    text = item.icon,
                    fontSize = 32.sp,
                    textAlign = TextAlign.Center
                )
            }
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = item.label,
                color = Color.White,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                fontFamily = TouchBarFontFamily,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center
            )
        }
    }
}

// MARK: - 3. Page 2: macOS Control Center Screen
@Composable
fun MacOSControlCenterScreen(
    client: TouchbarClient,
    volume: Int,
    isMuted: Boolean,
    brightness: Int,
    battery: Int,
    isWifiEnabled: Boolean,
    isBluetoothEnabled: Boolean,
    isAirDropEnabled: Boolean,
    isFocusSleepEnabled: Boolean,
    isStageManagerEnabled: Boolean,
    media: TouchbarMediaInfo,
    onHaptic: () -> Unit
) {
    var volumeSlider by remember(volume) { mutableStateOf(volume.toFloat()) }
    var brightnessSlider by remember(brightness) { mutableStateOf(brightness.toFloat()) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .clip(RoundedCornerShape(16.dp))
            .background(
                Brush.verticalGradient(
                    colors = listOf(Color(0xFF26201D), Color(0xFF1E1917), Color(0xFF151312))
                )
            )
            .border(1.dp, Color(0xFF3D342F), RoundedCornerShape(16.dp))
            .padding(10.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxSize(),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            // Column 1: Connectivity & Battery
            Column(
                modifier = Modifier
                    .weight(1.1f)
                    .fillMaxHeight(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1.3f)
                        .clip(RoundedCornerShape(14.dp)),
                    color = Color(0x33FFFFFF)
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(8.dp),
                        verticalArrangement = Arrangement.SpaceAround
                    ) {
                        ControlCenterToggleRow(
                            icon = "📶",
                            title = "Wi-Fi (HeliPort)",
                            subtitle = if (isWifiEnabled) "Conectado" else "Desativado",
                            isActive = isWifiEnabled,
                            activeColor = ActiveBlue,
                            onClick = { onHaptic(); client.toggleWifi() }
                        )
                        ControlCenterToggleRow(
                            icon = "🔵",
                            title = "Bluetooth",
                            subtitle = if (isBluetoothEnabled) "Ativado" else "Desativado",
                            isActive = isBluetoothEnabled,
                            activeColor = ActiveBlue,
                            onClick = { onHaptic(); client.toggleBluetooth() }
                        )
                        ControlCenterToggleRow(
                            icon = "📡",
                            title = "AirDrop",
                            subtitle = if (isAirDropEnabled) "Todos" else "Desativado",
                            isActive = isAirDropEnabled,
                            activeColor = ActiveBlue,
                            onClick = { onHaptic(); client.toggleAirDrop() }
                        )
                    }
                }

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(0.7f),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Surface(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .clip(RoundedCornerShape(12.dp)),
                        color = Color(0x33FFFFFF)
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(horizontal = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center
                        ) {
                            Text("⚡️", fontSize = 14.sp)
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("100%", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                    Surface(
                        modifier = Modifier
                            .weight(1.3f)
                            .fillMaxHeight()
                            .clip(RoundedCornerShape(12.dp))
                            .clickable { onHaptic(); client.systemAction("spotlight") },
                        color = Color(0x33FFFFFF)
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(horizontal = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center
                        ) {
                            Text("📻", fontSize = 14.sp)
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("Reconhecer", color = Color.White, fontSize = 11.sp, maxLines = 1)
                        }
                    }
                }
            }

            // Column 2: Sono & Visual Toggles
            Column(
                modifier = Modifier
                    .weight(0.9f)
                    .fillMaxHeight(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .clip(RoundedCornerShape(14.dp))
                        .clickable { onHaptic(); client.toggleFocusSleep() },
                    color = Color(0x33FFFFFF)
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            modifier = Modifier
                                .size(34.dp)
                                .clip(CircleShape)
                                .background(if (isFocusSleepEnabled) Color(0xFF5E5CE6) else Color(0x44FFFFFF)),
                            contentAlignment = Alignment.Center
                        ) {
                            Text("🛏️", fontSize = 16.sp)
                        }
                        Spacer(modifier = Modifier.width(8.dp))
                        Column {
                            Text("Sono", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                            Text(if (isFocusSleepEnabled) "Ativado" else "Desativado", color = TouchBarTextSecondary, fontSize = 11.sp)
                        }
                    }
                }

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Surface(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .clip(RoundedCornerShape(14.dp))
                            .clickable { onHaptic(); client.toggleStageManager() },
                        color = Color(0x33FFFFFF)
                    ) {
                        Column(
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(8.dp),
                            verticalArrangement = Arrangement.Center,
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text("🪟", fontSize = 20.sp)
                            Spacer(modifier = Modifier.height(4.dp))
                            Text("Organizador", color = Color.White, fontSize = 10.sp, maxLines = 1)
                        }
                    }
                    Surface(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .clip(RoundedCornerShape(14.dp))
                            .clickable { onHaptic(); client.toggleScreenMirror() },
                        color = Color(0x33FFFFFF)
                    ) {
                        Column(
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(8.dp),
                            verticalArrangement = Arrangement.Center,
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text("🖥️", fontSize = 20.sp)
                            Spacer(modifier = Modifier.height(4.dp))
                            Text("Espelhar", color = Color.White, fontSize = 10.sp, maxLines = 1)
                        }
                    }
                }
            }

            // Column 3: Sliders & Mini Player
            Column(
                modifier = Modifier
                    .weight(1.4f)
                    .fillMaxHeight(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(48.dp)
                        .clip(RoundedCornerShape(12.dp)),
                    color = Color(0x33FFFFFF)
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("☀️", fontSize = 14.sp)
                        Slider(
                            value = brightnessSlider,
                            onValueChange = {
                                brightnessSlider = it
                                client.setBrightness(it.toInt())
                            },
                            valueRange = 0f..100f,
                            modifier = Modifier
                                .weight(1f)
                                .padding(horizontal = 6.dp),
                            colors = SliderDefaults.colors(
                                thumbColor = Color.White,
                                activeTrackColor = Color.White,
                                inactiveTrackColor = Color(0x33FFFFFF)
                            )
                        )
                        Text("${brightnessSlider.toInt()}%", color = Color.White, fontSize = 11.sp)
                    }
                }

                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(48.dp)
                        .clip(RoundedCornerShape(12.dp)),
                    color = Color(0x33FFFFFF)
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(if (isMuted) "🔇" else "🔊", fontSize = 14.sp)
                        Slider(
                            value = volumeSlider,
                            onValueChange = {
                                volumeSlider = it
                                client.setVolume(it.toInt())
                            },
                            valueRange = 0f..100f,
                            modifier = Modifier
                                .weight(1f)
                                .padding(horizontal = 6.dp),
                            colors = SliderDefaults.colors(
                                thumbColor = Color.White,
                                activeTrackColor = Color.White,
                                inactiveTrackColor = Color(0x33FFFFFF)
                            )
                        )
                        Box(
                            modifier = Modifier
                                .size(24.dp)
                                .clip(CircleShape)
                                .background(ActiveBlue)
                                .clickable { onHaptic(); client.toggleMute() },
                            contentAlignment = Alignment.Center
                        ) {
                            Text("􀑪", fontSize = 10.sp, color = Color.White)
                        }
                    }
                }

                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .clip(RoundedCornerShape(12.dp)),
                    color = Color(0x33FFFFFF)
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.weight(1f)
                        ) {
                            Surface(
                                modifier = Modifier
                                    .size(36.dp)
                                    .clip(RoundedCornerShape(6.dp)),
                                color = Color(0xFF333336)
                            ) {
                                Box(contentAlignment = Alignment.Center) {
                                    Text("🎵", fontSize = 18.sp)
                                }
                            }
                            Spacer(modifier = Modifier.width(8.dp))
                            Column {
                                Text(
                                    text = media.title.ifEmpty { "Nenhuma música" },
                                    color = Color.White,
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = media.artist.ifEmpty { "Mac Conectado" },
                                    color = TouchBarTextSecondary,
                                    fontSize = 11.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }

                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Box(
                                modifier = Modifier
                                    .size(32.dp)
                                    .clip(CircleShape)
                                    .background(Color(0x33FFFFFF))
                                    .clickable { onHaptic(); client.mediaPlayPause() },
                                contentAlignment = Alignment.Center
                            ) {
                                Text(if (media.state == "playing") "⏸" else "▶", color = Color.White, fontSize = 14.sp)
                            }
                            Box(
                                modifier = Modifier
                                    .size(32.dp)
                                    .clip(CircleShape)
                                    .background(Color(0x33FFFFFF))
                                    .clickable { onHaptic(); client.mediaNext() },
                                contentAlignment = Alignment.Center
                            ) {
                                Text("⏭", color = Color.White, fontSize = 14.sp)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun ControlCenterToggleRow(
    icon: String,
    title: String,
    subtitle: String,
    isActive: Boolean,
    activeColor: Color,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .clickable(onClick = onClick)
            .padding(4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(CircleShape)
                .background(if (isActive) activeColor else Color(0x33FFFFFF)),
            contentAlignment = Alignment.Center
        ) {
            Text(icon, fontSize = 13.sp)
        }
        Spacer(modifier = Modifier.width(8.dp))
        Column {
            Text(title, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            Text(subtitle, color = TouchBarTextSecondary, fontSize = 10.sp)
        }
    }
}

// MARK: - 4. Page 3: Dedicated Music Screen
@Composable
fun DedicatedMusicScreen(
    media: TouchbarMediaInfo,
    volume: Int,
    isMuted: Boolean,
    client: TouchbarClient,
    onHaptic: () -> Unit
) {
    var volumeSlider by remember(volume) { mutableStateOf(volume.toFloat()) }

    Row(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(24.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Surface(
            modifier = Modifier
                .size(190.dp)
                .clip(RoundedCornerShape(16.dp))
                .border(1.dp, Color(0xFF333336), RoundedCornerShape(16.dp)),
            color = Color(0xFF1E1E22)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Text("🎵", fontSize = 64.sp)
            }
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxHeight(),
            verticalArrangement = Arrangement.SpaceAround
        ) {
            Column {
                Text(
                    text = media.title.ifEmpty { "Mac Audio Player" },
                    color = Color.White,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = TouchBarFontFamily,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = media.artist.ifEmpty { "Pronto para tocar Spotify ou Apple Music" },
                    color = TouchBarTextSecondary,
                    fontSize = 14.sp,
                    fontFamily = TouchBarFontFamily,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Column {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(4.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(Color(0xFF333336))
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(0.45f)
                            .height(4.dp)
                            .background(ActiveBlue)
                    )
                }
                Spacer(modifier = Modifier.height(4.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text("1:28", color = TouchBarTextSecondary, fontSize = 11.sp)
                    Text("3:42", color = TouchBarTextSecondary, fontSize = 11.sp)
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceAround,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("􀊝", fontSize = 20.sp, color = TouchBarTextSecondary, modifier = Modifier.clickable { onHaptic(); client.sendHotkey("s", listOf("command")) })
                Text("⏮", fontSize = 26.sp, color = Color.White, modifier = Modifier.clickable { onHaptic(); client.mediaPrev() })
                Box(
                    modifier = Modifier
                        .size(54.dp)
                        .clip(CircleShape)
                        .background(ActiveBlue)
                        .clickable { onHaptic(); client.mediaPlayPause() },
                    contentAlignment = Alignment.Center
                ) {
                    Text(if (media.state == "playing") "⏸" else "▶", color = Color.White, fontSize = 24.sp)
                }
                Text("⏭", fontSize = 26.sp, color = Color.White, modifier = Modifier.clickable { onHaptic(); client.mediaNext() })
                Text("❤️", fontSize = 20.sp, color = TouchBarTextSecondary, modifier = Modifier.clickable { onHaptic(); client.sendHotkey("l", listOf("command")) })
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(if (isMuted) "🔇" else "🔈", fontSize = 14.sp)
                Slider(
                    value = volumeSlider,
                    onValueChange = {
                        volumeSlider = it
                        client.setVolume(it.toInt())
                    },
                    valueRange = 0f..100f,
                    modifier = Modifier
                        .weight(1f)
                        .padding(horizontal = 8.dp),
                    colors = SliderDefaults.colors(
                        thumbColor = Color.White,
                        activeTrackColor = ActiveBlue,
                        inactiveTrackColor = Color(0xFF333336)
                    )
                )
                Text("${volumeSlider.toInt()}%", color = Color.White, fontSize = 12.sp)
            }
        }
    }
}

// MARK: - 5. Page 4: Apple Emoji Keyboard Screen
@Composable
fun AppleEmojiKeyboardScreen(
    onEmojiSelected: (String) -> Unit
) {
    val categories = listOf(
        "😀 Recentes" to listOf("👍", "❤️", "🔥", "😂", "🚀", "🎉", "👀", "✨", "💯", "🙌", "👏", "😎", "🤔", "💡", "☕️", "🍺", "⚡️", "🛠️", "✅", "❌", "🎨", "💻", "", "🌟"),
        "😀 Carinhas" to listOf("😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "🥹", "☺️", "😊", "😇", "🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😗", "😙", "😚", "😋", "😛"),
        "👍 Gestos" to listOf("👋", "🤚", "🖐️", "✋", "🖖", "🫱", "🫲", "🫳", "🫴", "👌", "🤌", "🤏", "✌️", "🤞", "🫰", "🤟", "🤘", "🤙", "👈", "👉", "👆", "🖕", "👇", "☝️"),
        "🍕 Comidas" to listOf("🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🥑", "🥦", "🥬", "🥒", "🌶️", "🫑"),
        "💻 Objetos" to listOf("⌚️", "📱", "📲", "💻", "⌨️", "🖥️", "🖨️", "🖱️", "trackball", "🕹️", "🗜️", "💾", "💿", "📀", "📼", "📷", "📸", "📹", "🎥", "📽️", "🎞️", "📞", "☎️", "📟")
    )

    var selectedCategoryIndex by remember { mutableStateOf(0) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 8.dp),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        LazyRow(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            items(categories.size) { idx ->
                val (catTitle, _) = categories[idx]
                val isSelected = (idx == selectedCategoryIndex)
                Surface(
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .clickable { selectedCategoryIndex = idx },
                    color = if (isSelected) Color(0xFF2C2C2E) else Color(0xFF141416),
                    border = androidx.compose.foundation.BorderStroke(
                        1.dp,
                        if (isSelected) ActiveBlue else TouchBarButtonBorder
                    )
                ) {
                    Text(
                        text = catTitle,
                        color = if (isSelected) Color.White else TouchBarTextSecondary,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Medium,
                        fontFamily = TouchBarFontFamily,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                    )
                }
            }
        }

        val currentEmojis = categories[selectedCategoryIndex].second
        LazyVerticalGrid(
            columns = GridCells.Fixed(8),
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            items(currentEmojis) { emoji ->
                Surface(
                    modifier = Modifier
                        .height(44.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .clickable { onEmojiSelected(emoji) },
                    color = Color(0xFF1E1E22),
                    border = androidx.compose.foundation.BorderStroke(1.dp, TouchBarButtonBorder)
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(text = emoji, fontSize = 20.sp)
                    }
                }
            }
        }
    }
}

// MARK: - 6. Bottom Pager Dots Indicator
@Composable
fun BottomPageDots(
    pageCount: Int,
    currentPage: Int,
    onDotClick: (Int) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        for (i in 0 until pageCount) {
            val isSelected = (i == currentPage)
            Box(
                modifier = Modifier
                    .padding(horizontal = 4.dp)
                    .size(if (isSelected) 18.dp to 6.dp else 6.dp to 6.dp)
                    .clip(CircleShape)
                    .background(if (isSelected) ActiveBlue else Color(0xFF3A3A3C))
                    .clickable { onDotClick(i) }
            )
        }
    }
}

private fun Modifier.size(sizePair: Pair<androidx.compose.ui.unit.Dp, androidx.compose.ui.unit.Dp>): Modifier {
    return this
        .width(sizePair.first)
        .height(sizePair.second)
}

package io.github.luxfajah.touchbar.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily

// Apple Touch Bar OLED Black & Surfaces
val TouchBarBackground = Color(0xFF000000)
val TouchBarButtonFill = Color(0xFF222224)
val TouchBarButtonPressed = Color(0xFF38383A)
val TouchBarButtonBorder = Color(0xFF2F2F32)
val TouchBarDivider = Color(0xFF28282B)

val TouchBarTextPrimary = Color(0xFFF5F5F7)
val TouchBarTextSecondary = Color(0xFF8E8E93)

// Apple Vibrant Semantic Accents
val ActiveBlue = Color(0xFF0A84FF)
val ConnectedGreen = Color(0xFF30D158)
val DisconnectedRed = Color(0xFFFF453A)
val SiriPurple = Color(0xFFBF5AF2)
val SpotifyGreen = Color(0xFF1DB954)
val FigmaPurple = Color(0xFF7B61FF)

val TouchBarFontFamily = FontFamily.SansSerif

private val TouchBarColorScheme = darkColorScheme(
    primary = ActiveBlue,
    onPrimary = Color.White,
    secondary = SiriPurple,
    onSecondary = Color.White,
    background = TouchBarBackground,
    onBackground = Color.White,
    surface = TouchBarButtonFill,
    onSurface = Color.White,
    error = DisconnectedRed,
    onError = Color.White
)

@Composable
fun TouchBarTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = TouchBarColorScheme,
        content = content
    )
}

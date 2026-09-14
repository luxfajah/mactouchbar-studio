package io.github.jqssun.airplay.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Apple iPadOS & macOS HIG System Colors (Light Mode)
val AppleSystemBlue = Color(0xFF007AFF)
val AppleSystemIndigo = Color(0xFF5856D6)
val AppleSystemPurple = Color(0xFFAF52DE)
val AppleSystemGreen = Color(0xFF34C759)
val AppleSystemOrange = Color(0xFFFF9500)
val AppleSystemRed = Color(0xFFFF3B30)
val AppleSystemTeal = Color(0xFF30B0C7)
val AppleSystemGray = Color(0xFF8E8E93)

// Ultra-Minimal Surfaces (Borderless, Clean, Soft)
val AppleLightBg = Color(0xFFF2F2F7) // Pure Apple System Grouped Background
val AppleSidebarBg = Color(0xFFF8F8FA) // Clean Inset Sidebar
val AppleCardBg = Color(0xFFFFFFFF) // Pure White Surface
val AppleSecondaryCardBg = Color(0xFFF7F7F9)
val ApplePillBg = Color(0xFFE9E9EE)

// Minimalist Text Colors
val AppleLabelPrimary = Color(0xFF1C1C1E)
val AppleLabelSecondary = Color(0xFF6E6E73)
val AppleLabelTertiary = Color(0xFF8E8E93)
val AppleLabelQuaternary = Color(0xFFC7C7CC)

val AppleLightColorScheme = lightColorScheme(
    primary = AppleSystemBlue,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFEBF3FF),
    onPrimaryContainer = AppleSystemBlue,
    secondary = AppleSystemIndigo,
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFF0F0FF),
    onSecondaryContainer = AppleSystemIndigo,
    tertiary = AppleSystemTeal,
    background = AppleLightBg,
    onBackground = AppleLabelPrimary,
    surface = AppleCardBg,
    onSurface = AppleLabelPrimary,
    surfaceVariant = AppleSecondaryCardBg,
    onSurfaceVariant = AppleLabelSecondary,
    outline = Color.Transparent,
    outlineVariant = Color.Transparent,
    error = AppleSystemRed,
    onError = Color.White
)

@Composable
fun AirPlayTheme(
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = AppleLightColorScheme,
        content = content
    )
}

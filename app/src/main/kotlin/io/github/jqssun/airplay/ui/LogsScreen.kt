package io.github.jqssun.airplay.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.jqssun.airplay.R
import io.github.jqssun.airplay.ui.theme.*
import io.github.jqssun.airplay.viewmodel.MainViewModel

@Composable
fun LogsScreen(viewModel: MainViewModel) {
    val logs by viewModel.logs.collectAsState()
    val listState = rememberLazyListState()

    LaunchedEffect(logs.size) {
        if (logs.isNotEmpty()) listState.animateScrollToItem(logs.size - 1)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Console do Sistema",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = AppleLabelPrimary,
                modifier = Modifier.weight(1f)
            )
            FilledTonalButton(
                onClick = { viewModel.exportLogs() },
                colors = ButtonDefaults.filledTonalButtonColors(
                    containerColor = AppleLightBg,
                    contentColor = AppleSystemBlue
                ),
                shape = RoundedCornerShape(10.dp),
                modifier = Modifier.dpadFocus()
            ) {
                Text(stringResource(R.string.btn_export), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            }
            Spacer(Modifier.width(8.dp))
            FilledTonalButton(
                onClick = { viewModel.clearLogs() },
                colors = ButtonDefaults.filledTonalButtonColors(
                    containerColor = AppleLightBg,
                    contentColor = AppleSystemRed
                ),
                shape = RoundedCornerShape(10.dp),
                modifier = Modifier.dpadFocus()
            ) {
                Text(stringResource(R.string.btn_clear), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            }
        }

        Surface(
            color = AppleSecondaryCardBg,
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxSize()
        ) {
            SelectionContainer {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(12.dp)
                ) {
                    if (logs.isEmpty()) {
                        item {
                            Text(
                                text = "Nenhum log registrado ainda.",
                                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                                color = AppleLabelTertiary,
                                modifier = Modifier.padding(8.dp)
                            )
                        }
                    } else {
                        items(logs) { line ->
                            Text(
                                text = line,
                                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace, fontSize = 11.sp),
                                color = when {
                                    line.contains("ERROR", ignoreCase = true) || line.contains("failed", ignoreCase = true) -> AppleSystemRed
                                    line.contains("SUCCESS", ignoreCase = true) || line.contains("started", ignoreCase = true) -> AppleSystemGreen
                                    line.contains("DEBUG", ignoreCase = true) -> AppleSystemIndigo
                                    else -> AppleLabelPrimary
                                },
                                modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp)
                            )
                        }
                    }
                }
            }
        }
    }
}

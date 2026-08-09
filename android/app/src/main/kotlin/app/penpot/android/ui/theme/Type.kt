package app.penpot.android.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import app.penpot.android.R

// Work Sans ships real faces per weight (custom fonts don't synthesize weights),
// mirroring Typography.swift.
val WorkSans = FontFamily(
    Font(R.font.work_sans_regular, FontWeight.Normal),
    Font(R.font.work_sans_medium, FontWeight.Medium),
    Font(R.font.work_sans_semibold, FontWeight.SemiBold),
    Font(R.font.work_sans_bold, FontWeight.Bold),
)

// Role mapping from the iOS text styles (Typography.swift):
// largeTitle 34 / title 28 / title2 22 / title3 20 / headline 17 semibold /
// body 17 / callout 16 / subheadline 15 / footnote 13 / caption 12 / caption2 11.
val PenpotTypography = Typography(
    headlineLarge = TextStyle(fontFamily = WorkSans, fontWeight = FontWeight.Bold, fontSize = 34.sp),
    headlineMedium = TextStyle(fontFamily = WorkSans, fontWeight = FontWeight.Bold, fontSize = 28.sp),
    headlineSmall = TextStyle(fontFamily = WorkSans, fontWeight = FontWeight.SemiBold, fontSize = 22.sp),
    titleLarge = TextStyle(fontFamily = WorkSans, fontWeight = FontWeight.Bold, fontSize = 20.sp),
    titleMedium = TextStyle(fontFamily = WorkSans, fontWeight = FontWeight.SemiBold, fontSize = 17.sp),
    titleSmall = TextStyle(fontFamily = WorkSans, fontWeight = FontWeight.SemiBold, fontSize = 15.sp),
    bodyLarge = TextStyle(fontFamily = WorkSans, fontWeight = FontWeight.Normal, fontSize = 17.sp),
    bodyMedium = TextStyle(fontFamily = WorkSans, fontWeight = FontWeight.Normal, fontSize = 16.sp),
    bodySmall = TextStyle(fontFamily = WorkSans, fontWeight = FontWeight.Normal, fontSize = 15.sp),
    labelLarge = TextStyle(fontFamily = WorkSans, fontWeight = FontWeight.Medium, fontSize = 17.sp),
    labelMedium = TextStyle(fontFamily = WorkSans, fontWeight = FontWeight.Normal, fontSize = 13.sp),
    labelSmall = TextStyle(fontFamily = WorkSans, fontWeight = FontWeight.Normal, fontSize = 11.sp),
)

// iOS styles with no direct Material3 slot.
val FootnoteStyle = TextStyle(fontFamily = WorkSans, fontWeight = FontWeight.Normal, fontSize = 13.sp)
val CaptionStyle = TextStyle(fontFamily = WorkSans, fontWeight = FontWeight.Normal, fontSize = 12.sp)
val Caption2Style = TextStyle(fontFamily = WorkSans, fontWeight = FontWeight.Normal, fontSize = 11.sp)

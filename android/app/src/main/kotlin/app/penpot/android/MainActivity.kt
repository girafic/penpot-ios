package app.penpot.android

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.penpot.android.app.AppPhase
import app.penpot.android.app.PenpotThemeSetting
import app.penpot.android.common.LoadingState
import app.penpot.android.features.auth.LoginScreen
import app.penpot.android.nav.PenpotNavHost
import app.penpot.android.ui.theme.PenpotTheme

/**
 * Single activity. AppCompat (not plain ComponentActivity) so per-app locales work
 * below Android 13 via `AppCompatDelegate.setApplicationLocales`.
 */
class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val graph = (application as PenpotApplication).graph
        setContent {
            val darkTheme = when (graph.settings.theme) {
                PenpotThemeSetting.SYSTEM -> isSystemInDarkTheme()
                PenpotThemeSetting.LIGHT -> false
                PenpotThemeSetting.DARK -> true
            }
            PenpotTheme(darkTheme = darkTheme) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    RootView(graph)
                }
            }
        }
    }
}

/**
 * The 3-way phase switch (loading / login / authenticated) — the app's only root
 * navigation. A locale change must not remount this tree (it would drop the user
 * back to the dashboard); resource resolution updates strings in place.
 */
@Composable
private fun RootView(graph: AppGraph) {
    val appState = graph.appState
    LaunchedEffect(Unit) {
        if (appState.phase == AppPhase.LOADING) appState.bootstrap()
    }
    when (appState.phase) {
        AppPhase.LOADING -> LoadingState(stringResource(R.string.connecting))
        AppPhase.LOGIN -> LoginScreen(graph)
        AppPhase.AUTHENTICATED -> PenpotNavHost(graph)
    }
}

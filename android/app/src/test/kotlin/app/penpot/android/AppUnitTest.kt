package app.penpot.android

import app.penpot.android.app.FilesLayout
import app.penpot.android.app.PenpotThemeSetting
import app.penpot.android.common.initials
import app.penpot.android.common.penpotExportFilename
import app.penpot.android.features.auth.normalizeServerUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Pure app-layer logic (port of the iOS AppSettingsTests plus helpers). */
class AppUnitTest {

    @Test
    fun themeSettingRoundTripsAndDefaults() {
        assertEquals(PenpotThemeSetting.DARK, PenpotThemeSetting.fromRaw("dark"))
        assertEquals(PenpotThemeSetting.SYSTEM, PenpotThemeSetting.fromRaw(null))
        assertEquals(PenpotThemeSetting.SYSTEM, PenpotThemeSetting.fromRaw("bogus"))
    }

    @Test
    fun filesLayoutTogglesAndDefaults() {
        assertEquals(FilesLayout.GRID, FilesLayout.fromRaw(null))
        assertEquals(FilesLayout.LIST, FilesLayout.GRID.toggled)
        assertEquals(FilesLayout.GRID, FilesLayout.LIST.toggled)
    }

    @Test
    fun serverUrlNormalization() {
        assertEquals("https://design.penpot.app/", normalizeServerUrl(" design.penpot.app ").toString())
        assertEquals("https://design.penpot.app/", normalizeServerUrl("https://design.penpot.app///").toString())
        assertEquals("http://localhost:9001/", normalizeServerUrl("http://localhost:9001").toString())
        assertNull(normalizeServerUrl(""))
        assertNull(normalizeServerUrl("https://"))
    }

    @Test
    fun initialsFollowPenpotConvention() {
        assertEquals("AL", initials("Ada Lovelace"))
        assertEquals("AC", initials("Ada B. Countess"))   // first + last word
        assertEquals("A", initials("ada@example.com"))
        assertNull(initials("  "))
        assertNull(initials(null))
    }

    @Test
    fun exportFilenameSanitized() {
        assertEquals("My File-v2.penpot", penpotExportFilename("My File/v2"))
        assertEquals("a-b-c.penpot", penpotExportFilename("a\\b:c"))
    }
}

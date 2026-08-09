# Keep kotlinx.serialization models (release builds are not minified today;
# these rules make a future isMinifyEnabled=true safe).
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class app.penpot.core.** {
    *** Companion;
}
-keepclasseswithmembers class app.penpot.core.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Whether eReaderDS takes the volume keys (on a Surface Duo: volume down is
# next page, volume up previous). MainActivity reads it; Lua sets it through
# JNI (app/android.lua) on a Duo only, so GammaOS and others keep their volume.
.class public Lcom/casualducko/ereaderds/Volume;
.super Ljava/lang/Object;

.field public static on:Z

.method public static take(Landroid/app/Activity;)V
    .registers 2
    const/4 v0, 0x1
    sput-boolean v0, Lcom/casualducko/ereaderds/Volume;->on:Z
    return-void
.end method

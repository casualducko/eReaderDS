# Keeps eReaderDS's window in the device's own orientation: the Surface Duo
# spanned across both screens stays one wide two-page spread, and turning the
# phone doesn't make it a tall window (which only asks to open the Duo).
# Android's "no sensor" mode: the physical orientation sensor is ignored.
# Called from Lua through JNI (app/android.lua) on a Duo only; the manifest
# stays unspecified, as GammaOS's DualStack needs. Run on Android's UI thread.
.class public Lcom/casualducko/ereaderds/Orient;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;

.field private final activity:Landroid/app/Activity;

.method public constructor <init>(Landroid/app/Activity;)V
    .registers 2
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    iput-object p1, p0, Lcom/casualducko/ereaderds/Orient;->activity:Landroid/app/Activity;
    return-void
.end method

.method public static lock(Landroid/app/Activity;)V
    .registers 2
    new-instance v0, Lcom/casualducko/ereaderds/Orient;
    invoke-direct {v0, p0}, Lcom/casualducko/ereaderds/Orient;-><init>(Landroid/app/Activity;)V
    invoke-virtual {p0, v0}, Landroid/app/Activity;->runOnUiThread(Ljava/lang/Runnable;)V
    return-void
.end method

.method public run()V
    .registers 3
    iget-object v0, p0, Lcom/casualducko/ereaderds/Orient;->activity:Landroid/app/Activity;
    const/4 v1, 0x5
    invoke-virtual {v0, v1}, Landroid/app/Activity;->setRequestedOrientation(I)V
    return-void
.end method

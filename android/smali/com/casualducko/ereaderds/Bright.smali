# Sets the brightness of eReaderDS's own window (Android lets any app do this
# for its window, without a permission): 0..1, or -1 for the system's own.
# Called from Lua through JNI (app/android.lua); the change is made on
# Android's UI thread, as window changes must be.
.class public Lcom/casualducko/ereaderds/Bright;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;

.field private final activity:Landroid/app/Activity;
.field private final value:F

.method public constructor <init>(Landroid/app/Activity;F)V
    .registers 3
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    iput-object p1, p0, Lcom/casualducko/ereaderds/Bright;->activity:Landroid/app/Activity;
    iput p2, p0, Lcom/casualducko/ereaderds/Bright;->value:F
    return-void
.end method

.method public static set(Landroid/app/Activity;F)V
    .registers 3
    new-instance v0, Lcom/casualducko/ereaderds/Bright;
    invoke-direct {v0, p0, p1}, Lcom/casualducko/ereaderds/Bright;-><init>(Landroid/app/Activity;F)V
    invoke-virtual {p0, v0}, Landroid/app/Activity;->runOnUiThread(Ljava/lang/Runnable;)V
    return-void
.end method

.method public run()V
    .registers 4
    iget-object v0, p0, Lcom/casualducko/ereaderds/Bright;->activity:Landroid/app/Activity;
    invoke-virtual {v0}, Landroid/app/Activity;->getWindow()Landroid/view/Window;
    move-result-object v0
    if-eqz v0, :done
    invoke-virtual {v0}, Landroid/view/Window;->getAttributes()Landroid/view/WindowManager$LayoutParams;
    move-result-object v1
    iget v2, p0, Lcom/casualducko/ereaderds/Bright;->value:F
    iput v2, v1, Landroid/view/WindowManager$LayoutParams;->screenBrightness:F
    invoke-virtual {v0, v1}, Landroid/view/Window;->setAttributes(Landroid/view/WindowManager$LayoutParams;)V
    :done
    return-void
.end method

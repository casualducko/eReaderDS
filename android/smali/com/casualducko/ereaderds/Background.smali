# Sends eReaderDS to the background, as pressing Home does: the app stays in
# Android's recent apps (the window, the span and the reading place all as they
# were) instead of closing. Called from Lua through JNI (app/android.lua) by the
# three-finger tap. Run on Android's UI thread.
.class public Lcom/casualducko/ereaderds/Background;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;

.field private final activity:Landroid/app/Activity;

.method public constructor <init>(Landroid/app/Activity;)V
    .registers 2
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    iput-object p1, p0, Lcom/casualducko/ereaderds/Background;->activity:Landroid/app/Activity;
    return-void
.end method

.method public static hide(Landroid/app/Activity;)V
    .registers 2
    new-instance v0, Lcom/casualducko/ereaderds/Background;
    invoke-direct {v0, p0}, Lcom/casualducko/ereaderds/Background;-><init>(Landroid/app/Activity;)V
    invoke-virtual {p0, v0}, Landroid/app/Activity;->runOnUiThread(Ljava/lang/Runnable;)V
    return-void
.end method

.method public run()V
    .registers 3
    iget-object v0, p0, Lcom/casualducko/ereaderds/Background;->activity:Landroid/app/Activity;
    const/4 v1, 0x1
    invoke-virtual {v0, v1}, Landroid/app/Activity;->moveTaskToBack(Z)Z
    return-void
.end method

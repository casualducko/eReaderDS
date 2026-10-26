# LÖVE's game activity, with the volume keys let through to the app when
# Volume.on is set. SDL hands them back to Android ("ignore certain special
# keys"), so the app never sees them; here they're turned into Page Down
# (volume down) and Page Up (volume up) key events for SDL, which the reader
# already turns into next and previous page, and consumed, so Android shows
# no volume bar. Everything else goes to LÖVE's own code.
.class public Lcom/casualducko/ereaderds/MainActivity;
.super Lorg/love2d/android/GameActivity;

.method public constructor <init>()V
    .registers 1
    invoke-direct {p0}, Lorg/love2d/android/GameActivity;-><init>()V
    return-void
.end method

.method public dispatchKeyEvent(Landroid/view/KeyEvent;)Z
    .registers 6
    sget-boolean v0, Lcom/casualducko/ereaderds/Volume;->on:Z
    if-eqz v0, :pass
    invoke-virtual {p1}, Landroid/view/KeyEvent;->getKeyCode()I
    move-result v0
    const/16 v1, 0x19
    if-ne v0, v1, :not_down
    const/16 v2, 0x5d
    goto :send
    :not_down
    const/16 v1, 0x18
    if-ne v0, v1, :pass
    const/16 v2, 0x5c
    :send
    invoke-virtual {p1}, Landroid/view/KeyEvent;->getAction()I
    move-result v0
    if-nez v0, :not_press
    invoke-static {v2}, Lorg/libsdl/app/SDLActivity;->onNativeKeyDown(I)V
    goto :done
    :not_press
    const/4 v1, 0x1
    if-ne v0, v1, :done
    invoke-static {v2}, Lorg/libsdl/app/SDLActivity;->onNativeKeyUp(I)V
    :done
    const/4 v0, 0x1
    return v0
    :pass
    invoke-super {p0, p1}, Lorg/love2d/android/GameActivity;->dispatchKeyEvent(Landroid/view/KeyEvent;)Z
    move-result v0
    return v0
.end method

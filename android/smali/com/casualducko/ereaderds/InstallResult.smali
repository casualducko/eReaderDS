# Android's answer to Install's session: written to the status file as
# "<status> <message>" (0 = installed, -1 = Android wants the reader to
# confirm, which then opens its own screen for that; others are failures).
.class public Lcom/casualducko/ereaderds/InstallResult;
.super Landroid/content/BroadcastReceiver;

.field private final status:Ljava/lang/String;

.method public constructor <init>(Ljava/lang/String;)V
    .registers 2
    invoke-direct {p0}, Landroid/content/BroadcastReceiver;-><init>()V
    iput-object p1, p0, Lcom/casualducko/ereaderds/InstallResult;->status:Ljava/lang/String;
    return-void
.end method

.method public onReceive(Landroid/content/Context;Landroid/content/Intent;)V
    .registers 8
    const-string v0, "android.content.pm.extra.STATUS"
    const/16 v1, -0x3e7
    invoke-virtual {p2, v0, v1}, Landroid/content/Intent;->getIntExtra(Ljava/lang/String;I)I
    move-result v0
    const-string v1, "android.content.pm.extra.STATUS_MESSAGE"
    invoke-virtual {p2, v1}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v1

    new-instance v2, Ljava/lang/StringBuilder;
    invoke-direct {v2}, Ljava/lang/StringBuilder;-><init>()V
    invoke-virtual {v2, v0}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
    const-string v3, " "
    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v2}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v2
    iget-object v3, p0, Lcom/casualducko/ereaderds/InstallResult;->status:Ljava/lang/String;
    invoke-static {v3, v2}, Lcom/casualducko/ereaderds/Install;->write(Ljava/lang/String;Ljava/lang/String;)V

    # -1: Android's own "update this app?" screen (and its answer comes here
    # later). Anything else is the end: stop listening, so a retry's answer
    # isn't also handled by this one.
    const/4 v2, -0x1
    if-eq v0, v2, :confirm
    :try_unregister
    invoke-virtual {p1}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
    move-result-object v2
    invoke-virtual {v2, p0}, Landroid/content/Context;->unregisterReceiver(Landroid/content/BroadcastReceiver;)V
    :try_unregister_end
    .catch Ljava/lang/Throwable; {:try_unregister .. :try_unregister_end} :done
    goto :done
    :confirm
    :try_start
    const-string v2, "android.intent.extra.INTENT"
    invoke-virtual {p2, v2}, Landroid/content/Intent;->getParcelableExtra(Ljava/lang/String;)Landroid/os/Parcelable;
    move-result-object v2
    check-cast v2, Landroid/content/Intent;
    if-eqz v2, :done
    const/high16 v3, 0x10000000
    invoke-virtual {v2, v3}, Landroid/content/Intent;->addFlags(I)Landroid/content/Intent;
    invoke-virtual {p1, v2}, Landroid/content/Context;->startActivity(Landroid/content/Intent;)V
    :try_end
    .catch Ljava/lang/Throwable; {:try_start .. :try_end} :done
    :done
    return-void
.end method

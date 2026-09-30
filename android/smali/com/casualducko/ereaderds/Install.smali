# Installs an update of eReaderDS (a newer APK signed with the same key)
# through Android's PackageInstaller, without root. It asks Android not to
# confirm, which Android allows for an app updating itself when it holds
# UPDATE_PACKAGES_WITHOUT_USER_ACTION; if Android wants a confirmation after
# all, InstallResult shows Android's own screen. Runs on its own thread; how it
# went is written to a status file for the app (app/android.lua). Installing
# stops the app.
.class public Lcom/casualducko/ereaderds/Install;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;

.field private final context:Landroid/content/Context;
.field private final path:Ljava/lang/String;
.field private final status:Ljava/lang/String;

.method public constructor <init>(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)V
    .registers 4
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    iput-object p1, p0, Lcom/casualducko/ereaderds/Install;->context:Landroid/content/Context;
    iput-object p2, p0, Lcom/casualducko/ereaderds/Install;->path:Ljava/lang/String;
    iput-object p3, p0, Lcom/casualducko/ereaderds/Install;->status:Ljava/lang/String;
    return-void
.end method

# start(activity, APK path, status file path)
.method public static start(Landroid/app/Activity;Ljava/lang/String;Ljava/lang/String;)V
    .registers 5
    new-instance v0, Lcom/casualducko/ereaderds/Install;
    invoke-virtual {p0}, Landroid/app/Activity;->getApplicationContext()Landroid/content/Context;
    move-result-object v1
    invoke-direct {v0, v1, p1, p2}, Lcom/casualducko/ereaderds/Install;-><init>(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)V
    new-instance v1, Ljava/lang/Thread;
    invoke-direct {v1, v0}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
    invoke-virtual {v1}, Ljava/lang/Thread;->start()V
    return-void
.end method

# write(path, text): the whole file.
.method public static write(Ljava/lang/String;Ljava/lang/String;)V
    .registers 4
    :try_start
    new-instance v0, Ljava/io/FileOutputStream;
    invoke-direct {v0, p0}, Ljava/io/FileOutputStream;-><init>(Ljava/lang/String;)V
    invoke-virtual {p1}, Ljava/lang/String;->getBytes()[B
    move-result-object v1
    invoke-virtual {v0, v1}, Ljava/io/FileOutputStream;->write([B)V
    invoke-virtual {v0}, Ljava/io/FileOutputStream;->close()V
    :try_end
    .catch Ljava/lang/Exception; {:try_start .. :try_end} :failed
    return-void
    :failed
    return-void
.end method

.method public run()V
    .registers 20
    move-object/from16 v12, p0
    iget-object v0, v12, Lcom/casualducko/ereaderds/Install;->context:Landroid/content/Context;
    :try_start
    invoke-virtual {v0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
    move-result-object v1
    invoke-virtual {v0}, Landroid/content/Context;->getPackageManager()Landroid/content/pm/PackageManager;
    move-result-object v2
    invoke-virtual {v2}, Landroid/content/pm/PackageManager;->getPackageInstaller()Landroid/content/pm/PackageInstaller;
    move-result-object v2

    # A session for the whole app (this one), asking for no confirmation.
    new-instance v3, Landroid/content/pm/PackageInstaller$SessionParams;
    const/4 v4, 0x1
    invoke-direct {v3, v4}, Landroid/content/pm/PackageInstaller$SessionParams;-><init>(I)V
    invoke-virtual {v3, v1}, Landroid/content/pm/PackageInstaller$SessionParams;->setAppPackageName(Ljava/lang/String;)V
    const/4 v4, 0x2
    invoke-virtual {v3, v4}, Landroid/content/pm/PackageInstaller$SessionParams;->setRequireUserAction(I)V
    invoke-virtual {v2, v3}, Landroid/content/pm/PackageInstaller;->createSession(Landroid/content/pm/PackageInstaller$SessionParams;)I
    move-result v3
    invoke-virtual {v2, v3}, Landroid/content/pm/PackageInstaller;->openSession(I)Landroid/content/pm/PackageInstaller$Session;
    move-result-object v2

    # The APK into it.
    new-instance v4, Ljava/io/File;
    iget-object v5, v12, Lcom/casualducko/ereaderds/Install;->path:Ljava/lang/String;
    invoke-direct {v4, v5}, Ljava/io/File;-><init>(Ljava/lang/String;)V
    invoke-virtual {v4}, Ljava/io/File;->length()J
    move-result-wide v17
    const-string v14, "base.apk"
    const-wide/16 v15, 0x0
    move-object v13, v2
    # openWrite(name, offset 0, length)
    invoke-virtual/range {v13 .. v18}, Landroid/content/pm/PackageInstaller$Session;->openWrite(Ljava/lang/String;JJ)Ljava/io/OutputStream;
    move-result-object v7
    new-instance v8, Ljava/io/FileInputStream;
    invoke-direct {v8, v4}, Ljava/io/FileInputStream;-><init>(Ljava/io/File;)V
    const/high16 v9, 0x10000
    new-array v9, v9, [B
    :copy
    invoke-virtual {v8, v9}, Ljava/io/FileInputStream;->read([B)I
    move-result v10
    if-lez v10, :copied
    const/4 v11, 0x0
    invoke-virtual {v7, v9, v11, v10}, Ljava/io/OutputStream;->write([BII)V
    goto :copy
    :copied
    invoke-virtual {v8}, Ljava/io/FileInputStream;->close()V
    invoke-virtual {v2, v7}, Landroid/content/pm/PackageInstaller$Session;->fsync(Ljava/io/OutputStream;)V
    invoke-virtual {v7}, Ljava/io/OutputStream;->close()V

    # Android's answer goes to InstallResult (registered here, not exported).
    new-instance v4, Ljava/lang/StringBuilder;
    invoke-direct {v4}, Ljava/lang/StringBuilder;-><init>()V
    invoke-virtual {v4, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    const-string v5, ".INSTALL_RESULT"
    invoke-virtual {v4, v5}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v4}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v4
    new-instance v5, Lcom/casualducko/ereaderds/InstallResult;
    iget-object v6, v12, Lcom/casualducko/ereaderds/Install;->status:Ljava/lang/String;
    invoke-direct {v5, v6}, Lcom/casualducko/ereaderds/InstallResult;-><init>(Ljava/lang/String;)V
    new-instance v6, Landroid/content/IntentFilter;
    invoke-direct {v6, v4}, Landroid/content/IntentFilter;-><init>(Ljava/lang/String;)V
    const/4 v7, 0x4
    invoke-virtual {v0, v5, v6, v7}, Landroid/content/Context;->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;I)Landroid/content/Intent;
    new-instance v5, Landroid/content/Intent;
    invoke-direct {v5, v4}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
    invoke-virtual {v5, v1}, Landroid/content/Intent;->setPackage(Ljava/lang/String;)Landroid/content/Intent;
    # FLAG_UPDATE_CURRENT | FLAG_MUTABLE (Android adds the result to it)
    const/high16 v6, 0xa000000
    invoke-static {v0, v3, v5, v6}, Landroid/app/PendingIntent;->getBroadcast(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;
    move-result-object v5
    invoke-virtual {v5}, Landroid/app/PendingIntent;->getIntentSender()Landroid/content/IntentSender;
    move-result-object v5
    iget-object v6, v12, Lcom/casualducko/ereaderds/Install;->status:Ljava/lang/String;
    const-string v7, "committed"
    invoke-static {v6, v7}, Lcom/casualducko/ereaderds/Install;->write(Ljava/lang/String;Ljava/lang/String;)V
    invoke-virtual {v2, v5}, Landroid/content/pm/PackageInstaller$Session;->commit(Landroid/content/IntentSender;)V
    invoke-virtual {v2}, Landroid/content/pm/PackageInstaller$Session;->close()V
    :try_end
    .catch Ljava/lang/Throwable; {:try_start .. :try_end} :failed
    return-void

    :failed
    move-exception v1
    iget-object v2, v12, Lcom/casualducko/ereaderds/Install;->status:Ljava/lang/String;
    new-instance v3, Ljava/lang/StringBuilder;
    invoke-direct {v3}, Ljava/lang/StringBuilder;-><init>()V
    const-string v4, "error "
    invoke-virtual {v3, v4}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v1}, Ljava/lang/Throwable;->toString()Ljava/lang/String;
    move-result-object v1
    invoke-virtual {v3, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v3}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v1
    invoke-static {v2, v1}, Lcom/casualducko/ereaderds/Install;->write(Ljava/lang/String;Ljava/lang/String;)V
    return-void
.end method

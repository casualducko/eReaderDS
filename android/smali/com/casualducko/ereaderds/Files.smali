# Opens Android's "Allow access to manage all files" page for eReaderDS, where
# the reader switches it on (a phone without GammaOS has no other way to give
# the Ebook folder to the app). Called from Lua through JNI (app/android.lua).
.class public Lcom/casualducko/ereaderds/Files;
.super Ljava/lang/Object;

.method public static open(Landroid/app/Activity;)V
    .registers 3
    new-instance v0, Landroid/content/Intent;
    const-string v1, "android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION"
    invoke-direct {v0, v1}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
    const-string v1, "package:com.casualducko.ereaderds"
    invoke-static {v1}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;
    move-result-object v1
    invoke-virtual {v0, v1}, Landroid/content/Intent;->setData(Landroid/net/Uri;)Landroid/content/Intent;
    invoke-virtual {p0, v0}, Landroid/app/Activity;->startActivity(Landroid/content/Intent;)V
    return-void
.end method


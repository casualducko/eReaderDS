#!/usr/bin/env python3
"""Turn LÖVE 11.5's Android manifest (decoded by apktool) into eReaderDS's:
its own package, name and version; one launcher entry; all-files access for
the Ebook folder; and no fixed orientation, so GammaOS's DualStack can give
it both screens as one tall window.

    patch_manifest.py DECODED_DIR VERSION VERSION_CODE
"""
import re
import sys

PACKAGE = "com.casualducko.ereaderds"
LOVE = "org.love2d.android"

root, version, code = sys.argv[1], sys.argv[2], sys.argv[3]

path = root + "/AndroidManifest.xml"
s = open(path, encoding="utf-8").read()


def sub(pattern, repl, text, count=1, flags=0):
    new, n = re.subn(pattern, repl, text, count=count, flags=flags)
    if n == 0:
        sys.exit("patch_manifest: no match for " + pattern)
    return new


# The package (the app's identity); activity and service class names are
# written out in full, so the code keeps working. The permission and the
# provider are named after the package, and must be, or they'd clash with
# LÖVE's own app.
s = sub(r'package="org\.love2d\.android"', 'package="%s"' % PACKAGE, s)
s = s.replace(LOVE + ".DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION",
              PACKAGE + ".DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION")
s = s.replace(LOVE + ".androidx-startup", PACKAGE + ".androidx-startup")

# Name everywhere.
s = s.replace('android:label="LÖVE for Android"', 'android:label="eReaderDS"')

# Only the game itself in app lists: LÖVE's loader (for picking .love files)
# would show up as a second, broken "eReaderDS".
s = sub(r'(<activity[^>]*SelectorActivity.*?)<category android:name="android.intent.category.LAUNCHER"/>\s*',
        r'\1', s, flags=re.S)
# Nor open .love files from other apps.
s = sub(r'(<activity[^>]*GameActivity[^>]*>)(.*?)(<intent-filter>\s*<action android:name="android.intent.action.MAIN"/>)',
        r'\1\n            \3', s, flags=re.S)

# Any orientation and resizable: DualStack makes the window 1024x1536.
s = sub(r'android:resizeableActivity="false"', 'android:resizeableActivity="true"', s)
s = sub(r'android:screenOrientation="landscape"', 'android:screenOrientation="unspecified"', s)

# All-files access: books live in /sdcard/Ebook, where people copy them.
s = sub(r'(<uses-permission android:name="android.permission.INTERNET"/>)',
        r'\1\n    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>', s)
# Installing its own updates, without the reader confirming each one
# (android/smali/.../Install): Android allows that for an app updating itself.
s = sub(r'(<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>)',
        r'\1\n    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>'
        r'\n    <uses-permission android:name="android.permission.UPDATE_PACKAGES_WITHOUT_USER_ACTION"/>', s)
# (No microphone or Bluetooth needed.)
s = s.replace('    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n', "")

open(path, "w", encoding="utf-8").write(s)

# LÖVE's switch for a game packed inside the app (assets/game.love); off,
# it's the LÖVE player and shows "no game".
bools = root + "/res/values/bools.xml"
b = open(bools, encoding="utf-8").read()
b = sub(r'<bool name="embed">false</bool>', '<bool name="embed">true</bool>', b)
open(bools, "w", encoding="utf-8").write(b)

yml = root + "/apktool.yml"
y = open(yml, encoding="utf-8").read()
y = sub(r"versionCode: \S+", "versionCode: %s" % code, y)
y = sub(r"versionName: \S+", "versionName: %s" % version, y)
y = y.replace("apkFileName: love-11.5-android.apk", "apkFileName: eReaderDS.apk")
# The game is stored as it is (it's a zip already): LÖVE opens it in place
# instead of reading it all into memory first, which fails for a big one.
# Files that are compressed already aren't squeezed again (the rest are: the
# app reads fonts and the dictionary whole, so compression costs nothing).
for ext in ("dz", "png", "jpg"):
    if ("\n- " + ext + "\n") not in y:
        y = sub(r"doNotCompress:\n", "doNotCompress:\n- " + ext + "\n", y)
open(yml, "w", encoding="utf-8").write(y)
print("manifest: %s %s (%s)" % (PACKAGE, version, code))

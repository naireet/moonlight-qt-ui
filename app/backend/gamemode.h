#pragma once

#include "nvcomputer.h"

// File-based contract with the Decky "Moonlight Game Mode" plugin. Everything
// lives in $HOME/.local/share/moonlight-stream/ regardless of portable mode:
// - host-apps.json: every paired host's app list, written by us
// - plugin.json: written by the plugin; its presence enables our menu items
// - requests/<uuid>.json: one "add" request per app, consumed by the plugin
// - last-session.json: the last streamed app, written by us
// - stream-state.json and control/: see streaming/streamcontrol.h
namespace GameMode
{
    // $HOME/.local/share/moonlight-stream
    QString dataDir();

    // Removes the zero-width characters some hosts put in app names
    QString stripZeroWidth(QString text);

    // True if the plugin is installed and we're running under SteamOS/gamescope
    bool isAvailable();

    // Merges this host's app list into host-apps.json (Linux only). Safe to
    // call from any thread; skips the write if nothing changed.
    void writeHostApps(NvComputer* computer);

    // Writes one add request per app and returns how many were written
    int requestAdd(NvComputer* computer, const QVector<NvApp>& apps, bool bulk);

    // Records the last streamed app in last-session.json (Linux only), so the
    // plugin can show "Resume" while the app is still running on the host
    void writeLastSession(NvComputer* computer, const NvApp& app, bool hostAppRunning);

    // Sets hostAppRunning to false if last-session.json is for this host
    void markHostAppEnded(NvComputer* computer);
}

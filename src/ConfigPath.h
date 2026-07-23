#pragma once
#include <QString>
#include <QStandardPaths>
#include <QDir>
#include <QFileInfo>

// Single source of the settings file location, shared by the consuming app's
// Settings and by ThemeController so they write ONE file instead of two.
//
// The kit does not hardcode an app identity: the consuming application names
// its config ONCE at startup via UnisicKit::setConfigName("unisic-studio"),
// before any Settings/ThemeController is constructed. Everything derives from
// that name — ~/.config/<name>/<name>.conf. The default is "unisic", so an app
// that never calls setConfigName keeps Unisic's historical path unchanged.
namespace UnisicKit {

// The app config identity. inline so the ONE definition is shared across every
// translation unit that includes this header (C++17 inline variable) — a
// per-TU static would let different TUs disagree on the path.
inline QString &configNameRef()
{
    static QString name = QStringLiteral("unisic");
    return name;
}

// Call once at startup, before constructing anything that reads a setting.
// `name` is both the directory under ~/.config and the .conf basename, e.g.
// setConfigName("unisic-studio") -> ~/.config/unisic-studio/unisic-studio.conf.
// An empty name is ignored so a stray call can't blank the identity.
inline void setConfigName(const QString &name)
{
    if (!name.isEmpty())
        configNameRef() = name;
}

inline QString configName()
{
    return configNameRef();
}

// Optional FULL-PATH override for apps whose historical config file name does
// not follow the <name>/<name>.conf derivation (Unisic keeps unisic.conf as
// the basename even in its "unisic-dev" dev-build dir). When set, it wins over
// the derived path; configDir() follows the override's directory so ancillary
// folders (themes/) stay next to the config file.
inline QString &configFileOverrideRef()
{
    static QString path;
    return path;
}

inline void setConfigFilePath(const QString &path)
{
    configFileOverrideRef() = path;
}

inline QString configDir()
{
    if (!configFileOverrideRef().isEmpty()) {
        const QString dir = QFileInfo(configFileOverrideRef()).absolutePath();
        QDir().mkpath(dir);
        return dir;
    }
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
                        + QLatin1Char('/') + configName();
    QDir().mkpath(dir);
    return dir;
}

inline QString filePath()
{
    if (!configFileOverrideRef().isEmpty())
        return configFileOverrideRef();
    return configDir() + QLatin1Char('/') + configName() + QStringLiteral(".conf");
}

} // namespace UnisicKit

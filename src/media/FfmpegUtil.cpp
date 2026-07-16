#include "FfmpegUtil.h"
#include <QProcess>
#include <QFileInfo>
#include <QTimer>

namespace FfmpegUtil {

// The ffmpeg found in PATH varies: some builds ship one without GPL
// x264. Probe the available video encoders once so both the lossless
// intermediate and the MP4 output can pick a working fallback. An empty set
// means the probe itself failed (no ffmpeg) — callers keep their preferred
// encoder and the existing "ffmpeg could not be started" path reports it.
static QSet<QString> probeFfmpegEncoders()
{
    QSet<QString> found;
    QProcess p;
    p.start(QStringLiteral("ffmpeg"),
            {QStringLiteral("-hide_banner"), QStringLiteral("-encoders")});
    if (p.waitForFinished(5000)) {
        const QList<QByteArray> lines = p.readAllStandardOutput().split('\n');
        for (const QByteArray &line : lines) {
            // " V....D libx264rgb   libx264 H.264 ... (codec h264)"
            // (skip the legend line " V..... = Video")
            const QList<QByteArray> cols = line.simplified().split(' ');
            if (cols.size() >= 2 && cols[0].startsWith('V') && cols[1] != "=")
                found.insert(QString::fromLatin1(cols[1]));
        }
    }
    return found;
}

// Magic-static: the first caller runs the probe, later callers get the cache,
// concurrent callers block until the probe finishes — which makes the warm-up
// from a worker thread in the constructor safe.
const QSet<QString> &encoders()
{
    static const QSet<QString> cached = probeFfmpegEncoders();
    return cached;
}

bool encoderUsable(const QString &name)
{
    return encoders().contains(name) || encoders().isEmpty();
}

QString gifPaletteGenFilter(int quality)
{
    const int q = qBound(0, quality, 2);
    return QStringLiteral("palettegen=stats_mode=%1")
        .arg(q == 2 ? QStringLiteral("diff") : QStringLiteral("full"));
}

QString gifPaletteUseFilter(int quality)
{
    const int q = qBound(0, quality, 2);
    const QString dither = q == 0 ? QStringLiteral("bayer:bayer_scale=3")
                                  : (q == 1 ? QStringLiteral("bayer:bayer_scale=5")
                                            : QStringLiteral("sierra2_4a"));
    return QStringLiteral("paletteuse=dither=%1:diff_mode=rectangle").arg(dither);
}

bool hardwareEncoderAvailable(const QString &id)
{
    if (id == QLatin1String("vaapi"))
        return encoders().contains(QStringLiteral("h264_vaapi"))
               && QFileInfo::exists(QStringLiteral("/dev/dri/renderD128"));
    if (id == QLatin1String("nvenc"))
        return encoders().contains(QStringLiteral("h264_nvenc"));
    return false;
}

void stopProcess(QProcess *&process)
{
    if (!process)
        return;
    QProcess *p = process;
    process = nullptr;
    // Standalone: the recorder version disconnected only p->this; with no owner
    // here, drop ALL of p's connections so a queued signal can't reach a
    // now-irrelevant slot before the self-reaping deleteLater below runs.
    QObject::disconnect(p, nullptr, nullptr, nullptr);
    if (p->state() == QProcess::NotRunning) {
        p->deleteLater();
        return;
    }
    // Non-blocking escalation: the old terminate + waitForFinished(1000) +
    // kill + waitForFinished(3000) froze the GUI for up to 4 s per process on
    // every cancel/failure (ffmpeg can be slow to flush after SIGTERM). The
    // detached process reaps itself via finished -> deleteLater; removing the
    // temp files right after stays correct on Linux (ffmpeg keeps writing to
    // the unlinked inode, the space is reclaimed when it exits). The singleShot
    // is parented to p, so it auto-cancels if the process dies sooner.
    QObject::connect(p, &QProcess::finished, p, &QObject::deleteLater);
    p->closeWriteChannel();
    p->terminate();
    QTimer::singleShot(1000, p, [p] {
        if (p->state() != QProcess::NotRunning)
            p->kill();
    });
}

} // namespace FfmpegUtil

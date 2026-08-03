#include "FfmpegUtil.h"
#include <QBuffer>
#include <QDebug>
#include <QFileInfo>
#include <QHash>
#include <QImage>
#include <QMutex>
#include <QProcess>
#include <QStringList>
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

QByteArray encodeStillGif(const QImage &image, int quality)
{
    if (image.isNull())
        return {};
    // PNG on ffmpeg's stdin, GIF back on its stdout: no temp file to name, to
    // clean up, or to leave behind when this fails halfway.
    QByteArray png;
    {
        QBuffer buf(&png);
        buf.open(QIODevice::WriteOnly);
        if (!image.save(&buf, "PNG"))
            return {};
    }

    const int q = qBound(1, quality, 100);
    // A GIF has no quality scale, so the setting buys palette entries instead,
    // and the dither follows the palette. Dither DIRECTION matters here in a
    // way it does not for a photo format: every dither pattern is noise, and
    // noise is what LZW cannot compress. Measured on a 3840x2160 frame -
    // 64 colours cost 287 kB undithered and 312 kB with sierra2_4a, while 256
    // colours cost 386 kB and 416 kB. So the cheap end skips the dither
    // outright (which also suits a screenshot: flat UI colours band far less
    // than a photograph would, and undithered text stays crisp), and only the
    // full palette pays for error diffusion. Sizes then rise with the setting,
    // which is the one thing a quality slider must never get backwards.
    const int colors = q < 40 ? 64 : (q < 75 ? 128 : 256);
    const QString dither = q < 40 ? QStringLiteral("none")
                                  : (q < 75 ? QStringLiteral("bayer:bayer_scale=5")
                                            : QStringLiteral("sierra2_4a"));
    // alpha_threshold keeps GIF's single transparent entry: without it a
    // partly transparent capture composites onto black.
    const QString graph =
        QStringLiteral("split[a][b];[a]palettegen=max_colors=%1[p];[b][p]paletteuse=dither=%2"
                       ":alpha_threshold=128")
            .arg(colors)
            .arg(dither);

    QProcess ff;
    ff.start(QStringLiteral("ffmpeg"),
             {QStringLiteral("-hide_banner"), QStringLiteral("-y"),
              QStringLiteral("-nostats"), QStringLiteral("-loglevel"), QStringLiteral("error"),
              QStringLiteral("-f"), QStringLiteral("image2pipe"), QStringLiteral("-i"),
              QStringLiteral("-"), QStringLiteral("-vf"), graph,
              QStringLiteral("-frames:v"), QStringLiteral("1"),
              QStringLiteral("-f"), QStringLiteral("gif"), QStringLiteral("-")});
    if (!ff.waitForStarted(5000)) {
        qWarning() << "FfmpegUtil: still GIF encode could not start ffmpeg";
        return {};
    }
    ff.write(png);
    ff.closeWriteChannel();
    // 20 s covers a 4K frame with a wide margin (~0.5 s measured) and still
    // returns rather than hanging the caller if ffmpeg wedges.
    if (!ff.waitForFinished(20000)) {
        qWarning() << "FfmpegUtil: still GIF encode timed out";
        ff.kill();
        ff.waitForFinished(1000);
        return {};
    }
    if (ff.exitStatus() != QProcess::NormalExit || ff.exitCode() != 0) {
        qWarning() << "FfmpegUtil: still GIF encode failed:"
                   << ff.readAllStandardError().right(400).trimmed();
        return {};
    }
    return ff.readAllStandardOutput();
}

bool hardwareEncoderAvailable(const QString &id)
{
    if (id == QLatin1String("vaapi"))
        return encoders().contains(QStringLiteral("h264_vaapi"))
               && QFileInfo::exists(QStringLiteral("/dev/dri/renderD128"));
    if (id == QLatin1String("nvenc"))
        return encoders().contains(QStringLiteral("h264_nvenc"));
    // AV1 NVENC (RTX 40+) — the only hardware encoder a WebM can carry here.
    if (id == QLatin1String("av1-nvenc"))
        return encoders().contains(QStringLiteral("av1_nvenc"));
    return false;
}

bool hardwareEncoderWorks(const QString &id)
{
    // The cache is read from the GUI thread (diagnostics, dev buttons) and
    // from pool-thread encoder resolution — guard the hash, but run the
    // probe itself outside the lock (a concurrent duplicate probe is harmless,
    // both sides insert the same answer; holding the lock through it would
    // block a GUI caller for the probe's full 8 s instead).
    static QMutex cacheMutex;
    static QHash<QString, bool> cache;
    {
        QMutexLocker lock(&cacheMutex);
        const auto it = cache.constFind(id);
        if (it != cache.constEnd())
            return *it;
    }
    if (!hardwareEncoderAvailable(id)) {
        QMutexLocker lock(&cacheMutex);
        cache.insert(id, false);
        return false;
    }
    QStringList args{QStringLiteral("-hide_banner"), QStringLiteral("-loglevel"),
                     QStringLiteral("error"), QStringLiteral("-y")};
    if (id == QLatin1String("vaapi")) {
        args << QStringLiteral("-vaapi_device") << QStringLiteral("/dev/dri/renderD128")
             << QStringLiteral("-f") << QStringLiteral("lavfi")
             << QStringLiteral("-i") << QStringLiteral("testsrc2=size=320x240:rate=30:duration=0.1")
             << QStringLiteral("-vf") << QStringLiteral("format=nv12,hwupload")
             << QStringLiteral("-c:v") << QStringLiteral("h264_vaapi");
    } else {
        args << QStringLiteral("-f") << QStringLiteral("lavfi")
             << QStringLiteral("-i") << QStringLiteral("testsrc2=size=320x240:rate=30:duration=0.1")
             << QStringLiteral("-c:v")
             << (id == QLatin1String("av1-nvenc") ? QStringLiteral("av1_nvenc")
                                                  : QStringLiteral("h264_nvenc"))
             << QStringLiteral("-pix_fmt") << QStringLiteral("yuv420p");
    }
    args << QStringLiteral("-f") << QStringLiteral("null") << QStringLiteral("-");
    QProcess probe;
    probe.setProcessChannelMode(QProcess::MergedChannels);
    probe.start(QStringLiteral("ffmpeg"), args);
    const bool ok = probe.waitForFinished(8000) && probe.exitStatus() == QProcess::NormalExit
                    && probe.exitCode() == 0;
    if (!ok) {
        // Log WHY: "works=n" alone is undiagnosable in the field (session limits,
        // driver mismatch, a missing device node all look identical without it).
        const QString why = QString::fromUtf8(probe.readAll()).right(400).trimmed();
        qInfo().noquote() << "FfmpegUtil: hardware encoder" << id
                          << "is listed but does not encode here"
                          << (why.isEmpty() ? QString() : QStringLiteral("- %1").arg(why));
    }
    QMutexLocker lock(&cacheMutex);
    cache.insert(id, ok);
    return ok;
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

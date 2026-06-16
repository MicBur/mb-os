#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QObject>
#include <QTimer>
#include <QFile>
#include <QDir>
#include <QTextStream>
#include <QStringList>
#include <QDebug>
#include <QProcess>
#include <QRegularExpression>
#include <QVariantList>
#include "ThemeManager.h"

class SystemMonitor : public QObject {
    Q_OBJECT
    Q_PROPERTY(double cpuUsage READ cpuUsage NOTIFY cpuUsageChanged)
    Q_PROPERTY(double memUsage READ memUsage NOTIFY memUsageChanged)
    Q_PROPERTY(double gpuUsage READ gpuUsage NOTIFY gpuUsageChanged)
    Q_PROPERTY(double gpuMemUsage READ gpuMemUsage NOTIFY gpuMemUsageChanged)
    Q_PROPERTY(QString gpuName READ gpuName NOTIFY gpuNameChanged)
    Q_PROPERTY(QVariantList coreUsages READ coreUsages NOTIFY coreUsagesChanged)
    Q_PROPERTY(int coreCount READ coreCount NOTIFY coreCountChanged)
    Q_PROPERTY(double cpuTempC READ cpuTempC NOTIFY cpuTempChanged)
    // Battery
    Q_PROPERTY(int batteryLevel READ batteryLevel NOTIFY batteryChanged)
    Q_PROPERTY(bool batteryCharging READ batteryCharging NOTIFY batteryChanged)
    Q_PROPERTY(bool batteryPresent READ batteryPresent NOTIFY batteryChanged)
    // WiFi
    Q_PROPERTY(QString wifiName READ wifiName NOTIFY wifiChanged)
    Q_PROPERTY(int wifiStrength READ wifiStrength NOTIFY wifiChanged)
    Q_PROPERTY(bool wifiConnected READ wifiConnected NOTIFY wifiChanged)
    // Volume
    Q_PROPERTY(int volumeLevel READ volumeLevel NOTIFY volumeChanged)
    Q_PROPERTY(bool volumeMuted READ volumeMuted NOTIFY volumeChanged)
    // Brightness
    Q_PROPERTY(int brightnessLevel READ brightnessLevel NOTIFY brightnessChanged)

public:
    SystemMonitor(QObject *parent = nullptr) : QObject(parent), m_cpuUsage(0), m_memUsage(0),
        m_gpuUsage(0), m_gpuMemUsage(0), m_cpuTemp(0) {
        detectCoreCount();
        detectGpuName();
        m_timer = new QTimer(this);
        connect(m_timer, &QTimer::timeout, this, &SystemMonitor::updateStats);
        m_timer->start(1000);
        updateStats();
    }

    double cpuUsage() const { return m_cpuUsage; }
    double memUsage() const { return m_memUsage; }
    double gpuUsage() const { return m_gpuUsage; }
    double gpuMemUsage() const { return m_gpuMemUsage; }
    QString gpuName() const { return m_gpuName; }
    int coreCount() const { return m_coreCount; }
    double cpuTempC() const { return m_cpuTemp; }
    QVariantList coreUsages() const { return m_coreUsagesList; }
    // Battery
    int batteryLevel() const { return m_batteryLevel; }
    bool batteryCharging() const { return m_batteryCharging; }
    bool batteryPresent() const { return m_batteryPresent; }
    // WiFi
    QString wifiName() const { return m_wifiName; }
    int wifiStrength() const { return m_wifiStrength; }
    bool wifiConnected() const { return m_wifiConnected; }
    // Volume
    int volumeLevel() const { return m_volumeLevel; }
    bool volumeMuted() const { return m_volumeMuted; }
    // Brightness
    int brightnessLevel() const { return m_brightnessLevel; }

    Q_INVOKABLE void launchApp(const QString &command) {
        qDebug() << "Launching app:" << command;
        QStringList args = QProcess::splitCommand(command);
        if (!args.isEmpty()) {
            QString program = args.takeFirst();
            QProcess::startDetached(program, args);
        }
    }

    Q_INVOKABLE void powerOff() {
        qDebug() << "Powering off system...";
        QProcess::startDetached("sudo", QStringList() << "poweroff");
    }

    Q_INVOKABLE void reboot() {
        qDebug() << "Rebooting system...";
        QProcess::startDetached("sudo", QStringList() << "reboot");
    }

    Q_INVOKABLE void setVolume(int level) {
        QProcess::startDetached("wpctl", QStringList() << "set-volume" << "@DEFAULT_AUDIO_SINK@" << QString::number(level / 100.0));
    }
    Q_INVOKABLE void toggleMute() {
        QProcess::startDetached("wpctl", QStringList() << "set-mute" << "@DEFAULT_AUDIO_SINK@" << "toggle");
    }
    Q_INVOKABLE void setBrightness(int level) {
        // Find backlight device and set brightness
        QDir dir("/sys/class/backlight");
        QStringList devices = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        if (!devices.isEmpty()) {
            QString dev = devices.first();
            QFile fMax("/sys/class/backlight/" + dev + "/max_brightness");
            if (fMax.open(QIODevice::ReadOnly)) {
                int maxB = QTextStream(&fMax).readAll().trimmed().toInt();
                fMax.close();
                int val = maxB * level / 100;
                QProcess::startDetached("bash", QStringList() << "-c" << QString("echo %1 | sudo tee /sys/class/backlight/%2/brightness").arg(val).arg(dev));
            }
        }
    }

signals:
    void cpuUsageChanged();
    void memUsageChanged();
    void gpuUsageChanged();
    void gpuMemUsageChanged();
    void gpuNameChanged();
    void coreUsagesChanged();
    void coreCountChanged();
    void cpuTempChanged();
    void batteryChanged();
    void wifiChanged();
    void volumeChanged();
    void brightnessChanged();

private:
    double m_cpuUsage;
    double m_memUsage;
    double m_gpuUsage;
    double m_gpuMemUsage;
    double m_cpuTemp;
    int m_coreCount = 0;
    QString m_gpuName = "N/A";
    QTimer *m_timer;
    // Battery
    int m_batteryLevel = -1;
    bool m_batteryCharging = false;
    bool m_batteryPresent = false;
    // WiFi
    QString m_wifiName = "";
    int m_wifiStrength = 0;
    bool m_wifiConnected = false;
    // Volume
    int m_volumeLevel = 50;
    bool m_volumeMuted = false;
    // Brightness
    int m_brightnessLevel = 100;
    int m_slowTick = 0; // Update battery/wifi every 5s
    QVariantList m_coreUsagesList;

    // Per-core tracking
    struct CpuSnap {
        unsigned long long active = 0;
        unsigned long long total = 0;
    };
    QVector<CpuSnap> m_lastSnap; // index 0 = aggregate, 1..N = cores

    void detectCoreCount() {
        QFile f("/proc/stat");
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return;
        QTextStream in(&f);
        int count = 0;
        while (!in.atEnd()) {
            QString line = in.readLine();
            if (line.startsWith("cpu") && !line.startsWith("cpu ")) count++;
        }
        f.close();
        m_coreCount = count;
        m_lastSnap.resize(count + 1);
        emit coreCountChanged();
    }

    void detectGpuName() {
        // Try Intel
        QFile f("/sys/class/drm/card0/device/vendor");
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QString vendor = QTextStream(&f).readAll().trimmed();
            f.close();
            if (vendor == "0x8086") m_gpuName = "Intel HD Graphics";
            else if (vendor == "0x10de") m_gpuName = "NVIDIA GPU";
            else if (vendor == "0x1002") m_gpuName = "AMD GPU";
            else m_gpuName = "GPU";
            emit gpuNameChanged();
        }
    }

    void updateStats() {
        updateCpuCores();
        updateMem();
        updateGpu();
        updateCpuTemp();
        // Slow-tick updates (every 5 seconds to save CPU)
        if (++m_slowTick >= 5) {
            m_slowTick = 0;
            updateBattery();
            updateWifi();
            updateVolume();
            updateBrightness();
        }
    }

    void updateCpuCores() {
        QFile file("/proc/stat");
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return;

        QTextStream in(&file);
        int idx = 0;
        QVariantList newCoreUsages;

        while (!in.atEnd()) {
            QString line = in.readLine();
            bool isAggregate = line.startsWith("cpu ");
            bool isCore = line.startsWith("cpu") && !isAggregate;
            if (!isAggregate && !isCore) break;

            QStringList parts = line.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
            if (parts.size() >= 5) {
                unsigned long long user = parts[1].toULongLong();
                unsigned long long nice = parts[2].toULongLong();
                unsigned long long sys = parts[3].toULongLong();
                unsigned long long idle = parts[4].toULongLong();
                unsigned long long iowait = parts.size() > 5 ? parts[5].toULongLong() : 0;

                unsigned long long active = user + nice + sys;
                unsigned long long total = active + idle + iowait;

                double usage = 0;
                if (idx < m_lastSnap.size() && total > m_lastSnap[idx].total) {
                    double aDelta = active - m_lastSnap[idx].active;
                    double tDelta = total - m_lastSnap[idx].total;
                    usage = (aDelta / tDelta) * 100.0;
                }

                if (idx >= m_lastSnap.size()) m_lastSnap.resize(idx + 1);
                m_lastSnap[idx].active = active;
                m_lastSnap[idx].total = total;

                if (isAggregate) {
                    m_cpuUsage = usage;
                    emit cpuUsageChanged();
                } else {
                    newCoreUsages.append(usage);
                }
            }
            idx++;
        }
        file.close();

        m_coreUsagesList = newCoreUsages;
        emit coreUsagesChanged();
    }

    void updateMem() {
        QFile file("/proc/meminfo");
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return;

        QTextStream in(&file);
        unsigned long long memTotal = 0;
        unsigned long long memAvailable = 0;

        while (!in.atEnd()) {
            QString line = in.readLine();
            if (line.startsWith("MemTotal:")) {
                QStringList parts = line.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
                if (parts.size() >= 2) memTotal = parts[1].toULongLong();
            } else if (line.startsWith("MemAvailable:")) {
                QStringList parts = line.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
                if (parts.size() >= 2) memAvailable = parts[1].toULongLong();
            }
        }
        file.close();

        if (memTotal > 0) {
            double used = memTotal - memAvailable;
            m_memUsage = (used / memTotal) * 100.0;
            emit memUsageChanged();
        }
    }

    void updateGpu() {
        // Intel i915 GPU utilization
        QFile f("/sys/class/drm/card0/gt/gt0/rps_act_freq_mhz");
        QFile fMax("/sys/class/drm/card0/gt/gt0/rps_max_freq_mhz");
        if (f.open(QIODevice::ReadOnly) && fMax.open(QIODevice::ReadOnly)) {
            double act = QTextStream(&f).readAll().trimmed().toDouble();
            double max = QTextStream(&fMax).readAll().trimmed().toDouble();
            f.close(); fMax.close();
            if (max > 0) {
                m_gpuUsage = (act / max) * 100.0;
                emit gpuUsageChanged();
            }
            return;
        }
        // Fallback: try nvidia-smi
        QFile nv("/sys/class/drm/card0/device/gpu_busy_percent");
        if (nv.open(QIODevice::ReadOnly)) {
            m_gpuUsage = QTextStream(&nv).readAll().trimmed().toDouble();
            nv.close();
            emit gpuUsageChanged();
        }
    }

    void updateCpuTemp() {
        // Try hwmon thermal zones
        for (int i = 0; i < 10; i++) {
            QFile f(QString("/sys/class/thermal/thermal_zone%1/temp").arg(i));
            if (f.open(QIODevice::ReadOnly)) {
                double temp = QTextStream(&f).readAll().trimmed().toDouble() / 1000.0;
                f.close();
                if (temp > 0 && temp < 150) {
                    m_cpuTemp = temp;
                    emit cpuTempChanged();
                    return;
                }
            }
        }
    }

    void updateBattery() {
        // Check /sys/class/power_supply/BATx
        QStringList batNames = {"BAT0", "BAT1", "BATT", "battery"};
        for (const auto &name : batNames) {
            QString base = "/sys/class/power_supply/" + name;
            QFile cap(base + "/capacity");
            if (cap.open(QIODevice::ReadOnly)) {
                m_batteryPresent = true;
                m_batteryLevel = QTextStream(&cap).readAll().trimmed().toInt();
                cap.close();
                QFile stat(base + "/status");
                if (stat.open(QIODevice::ReadOnly)) {
                    QString s = QTextStream(&stat).readAll().trimmed();
                    m_batteryCharging = (s == "Charging" || s == "Full");
                    stat.close();
                }
                emit batteryChanged();
                return;
            }
        }
        m_batteryPresent = false;
        emit batteryChanged();
    }

    void updateWifi() {
        // Use iwgetid to get SSID
        QProcess proc;
        proc.start("iwgetid", QStringList() << "-r");
        proc.waitForFinished(500);
        QString ssid = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
        m_wifiConnected = !ssid.isEmpty();
        m_wifiName = ssid;

        // Read signal strength from /proc/net/wireless
        QFile f("/proc/net/wireless");
        if (f.open(QIODevice::ReadOnly)) {
            QTextStream in(&f);
            while (!in.atEnd()) {
                QString line = in.readLine().trimmed();
                if (line.contains("wl")) {
                    // Format: wlan0: STATUS LINK LEVEL NOISE ...
                    QStringList parts = line.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
                    if (parts.size() >= 4) {
                        double level = parts[3].remove('.').toDouble();
                        // level is in dBm or relative; normalize to 0-100
                        if (level > 0) {
                            m_wifiStrength = qBound(0, (int)level, 100);
                        } else {
                            // dBm: -30 = excellent, -90 = terrible
                            m_wifiStrength = qBound(0, (int)(2 * (level + 100)), 100);
                        }
                    }
                }
            }
            f.close();
        }
        emit wifiChanged();
    }

    void updateVolume() {
        QProcess proc;
        proc.start("wpctl", QStringList() << "get-volume" << "@DEFAULT_AUDIO_SINK@");
        proc.waitForFinished(500);
        QString out = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
        // Output: "Volume: 0.50" or "Volume: 0.50 [MUTED]"
        m_volumeMuted = out.contains("[MUTED]");
        QRegularExpression rx("Volume:\\s+([0-9.]+)");
        auto match = rx.match(out);
        if (match.hasMatch()) {
            m_volumeLevel = (int)(match.captured(1).toDouble() * 100);
        }
        emit volumeChanged();
    }

    void updateBrightness() {
        QDir dir("/sys/class/backlight");
        QStringList devices = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        if (!devices.isEmpty()) {
            QString dev = devices.first();
            QFile fCur("/sys/class/backlight/" + dev + "/brightness");
            QFile fMax("/sys/class/backlight/" + dev + "/max_brightness");
            if (fCur.open(QIODevice::ReadOnly) && fMax.open(QIODevice::ReadOnly)) {
                int cur = QTextStream(&fCur).readAll().trimmed().toInt();
                int max = QTextStream(&fMax).readAll().trimmed().toInt();
                fCur.close(); fMax.close();
                if (max > 0) {
                    m_brightnessLevel = (cur * 100) / max;
                    emit brightnessChanged();
                }
            }
        }
    }
};

int main(int argc, char *argv[]) {
    // Avoid drawing window decorations for the main desktop shell window
    qputenv("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1");

    QGuiApplication app(argc, argv);

    SystemMonitor monitor;
    ThemeManager themeManager;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("systemMonitor", &monitor);
    engine.rootContext()->setContextProperty("themeManager", &themeManager);

    const QUrl url(u"qrc:/main.qml"_qs);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}

#include "main.moc"

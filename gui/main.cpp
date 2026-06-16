#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QObject>
#include <QTimer>
#include <QFile>
#include <QTextStream>
#include <QStringList>
#include <QDebug>
#include <QProcess>
#include <QRegularExpression>
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

signals:
    void cpuUsageChanged();
    void memUsageChanged();
    void gpuUsageChanged();
    void gpuMemUsageChanged();
    void gpuNameChanged();
    void coreUsagesChanged();
    void coreCountChanged();
    void cpuTempChanged();

private:
    double m_cpuUsage;
    double m_memUsage;
    double m_gpuUsage;
    double m_gpuMemUsage;
    double m_cpuTemp;
    int m_coreCount = 0;
    QString m_gpuName = "N/A";
    QTimer *m_timer;
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

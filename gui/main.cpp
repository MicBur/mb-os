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

public:
    SystemMonitor(QObject *parent = nullptr) : QObject(parent), m_cpuUsage(0), m_memUsage(0) {
        m_timer = new QTimer(this);
        connect(m_timer, &QTimer::timeout, this, &SystemMonitor::updateStats);
        m_timer->start(1000);
        updateStats();
    }

    double cpuUsage() const { return m_cpuUsage; }
    double memUsage() const { return m_memUsage; }

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

private:
    double m_cpuUsage;
    double m_memUsage;
    QTimer *m_timer;
    
    unsigned long long m_lastTotalUser = 0;
    unsigned long long m_lastTotalUserLow = 0;
    unsigned long long m_lastTotalSys = 0;
    unsigned long long m_lastTotalIdle = 0;

    void updateStats() {
        updateCpu();
        updateMem();
    }

    void updateCpu() {
        QFile file("/proc/stat");
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return;
        
        QTextStream in(&file);
        QString line = in.readLine();
        file.close();

        if (line.startsWith("cpu ")) {
            QStringList parts = line.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
            if (parts.size() >= 5) {
                unsigned long long user = parts[1].toULongLong();
                unsigned long long nice = parts[2].toULongLong();
                unsigned long long sys = parts[3].toULongLong();
                unsigned long long idle = parts[4].toULongLong();

                unsigned long long totalActive = user + nice + sys;
                unsigned long long total = totalActive + idle;

                unsigned long long lastTotalActive = m_lastTotalUser + m_lastTotalUserLow + m_lastTotalSys;
                unsigned long long lastTotal = lastTotalActive + m_lastTotalIdle;

                if (total > lastTotal) {
                    double activeDelta = totalActive - lastTotalActive;
                    double totalDelta = total - lastTotal;
                    m_cpuUsage = (activeDelta / totalDelta) * 100.0;
                    emit cpuUsageChanged();
                }

                m_lastTotalUser = user;
                m_lastTotalUserLow = nice;
                m_lastTotalSys = sys;
                m_lastTotalIdle = idle;
            }
        }
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

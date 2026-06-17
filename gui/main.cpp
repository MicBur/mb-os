#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QObject>
#include <QTimer>
#include <QFile>
#include <QDir>
#include <QTextStream>
#include <QStringList>
#include <QStandardPaths>
#include <QDebug>
#include <QProcess>
#include <QRegularExpression>
#include <QVariantList>
#include <QSet>
#include <QColor>
#include <QCryptographicHash>
#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
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
    // Accessibility
    Q_PROPERTY(double uiScale READ uiScale NOTIFY uiScaleChanged)
    // Home Screen
    Q_PROPERTY(int homePageCount READ homePageCount NOTIFY homeScreenChanged)
    Q_PROPERTY(QVariantList homeScreenData READ homeScreenData NOTIFY homeScreenChanged)

public:
    SystemMonitor(QObject *parent = nullptr) : QObject(parent), m_cpuUsage(0), m_memUsage(0),
        m_gpuUsage(0), m_gpuMemUsage(0), m_cpuTemp(0) {
        loadAccessibility();
        applyCursorSize();
        loadHomeScreen();
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
    // Accessibility
    double uiScale() const { return m_uiScale; }

    Q_INVOKABLE void launchApp(const QString &command) {
        qDebug() << "Launching app:" << command;
        QStringList args = QProcess::splitCommand(command);
        if (!args.isEmpty()) {
            QString program = args.takeFirst();
            // Check if it's a shell script — run via bash
            QString fullPath = QStandardPaths::findExecutable(program);
            if (!fullPath.isEmpty()) {
                QFile f(fullPath);
                if (f.open(QIODevice::ReadOnly)) {
                    QByteArray header = f.read(32);
                    f.close();
                    if (header.startsWith("#!/bin/bash") || header.startsWith("#!/bin/sh")) {
                        args.prepend(fullPath);
                        QProcess::startDetached("bash", args);
                        return;
                    }
                }
            }
            QProcess::startDetached(program, args);
        }
    }

    // Lower the shell window so other apps can appear on top
    Q_INVOKABLE void lowerShellWindow() {
        QProcess::startDetached("bash", QStringList() << "-c"
            << "sleep 0.3; DISPLAY=:0 xdotool search --name 'MB-OS Desktop Shell' windowlower 2>/dev/null");
    }

    // ===== Lock Screen: PIN + Face Auth =====

    Q_INVOKABLE bool hasPin() {
        QString pinFile = QDir::homePath() + "/.config/mb-os/pin.hash";
        return QFile::exists(pinFile);
    }

    Q_INVOKABLE void setPin(const QString &pin) {
        QString dir = QDir::homePath() + "/.config/mb-os";
        QDir().mkpath(dir);
        QFile f(dir + "/pin.hash");
        if (f.open(QIODevice::WriteOnly)) {
            QByteArray hash = QCryptographicHash::hash(pin.toUtf8(), QCryptographicHash::Sha256).toHex();
            f.write(hash);
            f.close();
            qDebug() << "PIN set successfully";
        }
    }

    Q_INVOKABLE bool verifyPin(const QString &pin) {
        QString pinFile = QDir::homePath() + "/.config/mb-os/pin.hash";
        QFile f(pinFile);
        if (!f.open(QIODevice::ReadOnly)) return false;
        QByteArray stored = f.readAll().trimmed();
        f.close();
        QByteArray input = QCryptographicHash::hash(pin.toUtf8(), QCryptographicHash::Sha256).toHex();
        return stored == input;
    }

    Q_INVOKABLE bool hasFaceData() {
        QString faceFile = QDir::homePath() + "/.config/mb-os/face.json";
        return QFile::exists(faceFile);
    }

    Q_INVOKABLE void startFaceVerify() {
        // Run face-auth.py verify in background, emit signal when done
        QProcess *proc = new QProcess(this);
        connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, [this, proc](int exitCode, QProcess::ExitStatus) {
            emit faceAuthResult(exitCode == 0);
            proc->deleteLater();
        });
        proc->start("python3", QStringList() << "/usr/local/bin/face-auth.py" << "verify");
    }

    Q_INVOKABLE void enrollFace() {
        QProcess::startDetached("bash", QStringList() << "-c"
            << "DISPLAY=:0 xterm -bg black -fg green -fs 14 -T 'Gesicht registrieren' -e 'python3 /usr/local/bin/face-auth.py enroll; sleep 2'");
    }

    // Capture intruder photo on wrong PIN
    Q_INVOKABLE void captureIntruderPhoto() {
        QString dir = QDir::homePath() + "/.config/mb-os/intruder_photos";
        QDir().mkpath(dir);
        QString timestamp = QDateTime::currentDateTime().toString("yyyy-MM-dd_HH-mm-ss");
        QString path = dir + "/" + timestamp + ".jpg";
        // Use ffmpeg to capture one frame from webcam
        QProcess::startDetached("bash", QStringList() << "-c"
            << QString("ffmpeg -f v4l2 -i /dev/video0 -frames:v 1 -y '%1' 2>/dev/null").arg(path));
        qDebug() << "Intruder photo captured:" << path;
    }

    // Get list of intruder photos (newest first)
    Q_INVOKABLE QVariantList getIntruderPhotos() {
        QVariantList photos;
        QString dir = QDir::homePath() + "/.config/mb-os/intruder_photos";
        QDir d(dir);
        if (!d.exists()) return photos;

        QStringList files = d.entryList(QStringList() << "*.jpg" << "*.png", QDir::Files, QDir::Time);
        for (const QString &file : files) {
            QVariantMap entry;
            // Parse timestamp from filename: 2026-06-17_20-10-51.jpg
            QString name = QFileInfo(file).baseName();
            entry["filename"] = file;
            entry["path"] = dir + "/" + file;
            entry["timestamp"] = name.replace("_", " ").replace("-", ":");
            photos.append(entry);
            if (photos.size() >= 20) break; // Max 20 entries
        }
        return photos;
    }

    // Clear intruder photos
    Q_INVOKABLE void clearIntruderPhotos() {
        QString dir = QDir::homePath() + "/.config/mb-os/intruder_photos";
        QDir d(dir);
        if (d.exists()) {
            for (const QString &f : d.entryList(QDir::Files)) {
                d.remove(f);
            }
        }
    }

    // Change PIN
    Q_INVOKABLE bool changePin(const QString &oldPin, const QString &newPin) {
        if (!verifyPin(oldPin)) return false;
        setPin(newPin);
        return true;
    }


    Q_INVOKABLE QVariantList getInstalledApps() {
        QVariantList apps;
        QStringList searchPaths = {
            "/usr/share/applications",
            "/var/lib/snapd/desktop/applications",
            QDir::homePath() + "/.local/share/applications"
        };
        QSet<QString> seen; // Avoid duplicates by exec
        for (const auto &path : searchPaths) {
            QDir dir(path);
            if (!dir.exists()) continue;
            for (const auto &entry : dir.entryList({"*.desktop"}, QDir::Files)) {
                QFile f(dir.absoluteFilePath(entry));
                if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) continue;
                QTextStream in(&f);
                QString name, exec, icon, categories;
                bool noDisplay = false, inDesktopEntry = false;
                while (!in.atEnd()) {
                    QString line = in.readLine().trimmed();
                    if (line == "[Desktop Entry]") { inDesktopEntry = true; continue; }
                    if (line.startsWith("[") && line != "[Desktop Entry]") { inDesktopEntry = false; continue; }
                    if (!inDesktopEntry) continue;
                    if (line.startsWith("Name=") && name.isEmpty()) name = line.mid(5);
                    else if (line.startsWith("Exec=")) exec = line.mid(5);
                    else if (line.startsWith("Icon=")) icon = line.mid(5);
                    else if (line.startsWith("Categories=")) categories = line.mid(11);
                    else if (line.startsWith("NoDisplay=true")) noDisplay = true;
                    else if (line.startsWith("Hidden=true")) noDisplay = true;
                }
                f.close();
                if (noDisplay || name.isEmpty() || exec.isEmpty()) continue;
                // Clean exec: remove %f %u %F %U etc.
                exec.remove(QRegularExpression(" %[fFuUdDnNickvm]"));
                exec = exec.trimmed();
                if (seen.contains(exec)) continue;
                seen.insert(exec);
                // Derive icon text (first 1-2 chars of name)
                QString iconText = name.left(1).toUpper();
                if (name.length() > 1) iconText = name.left(2);
                // Derive color from name hash
                uint hash = qHash(name);
                int hue = hash % 360;
                QString clr = QColor::fromHsl(hue, 180, 140).name();
                // Category mapping
                QString cat = "system";
                if (categories.contains("Development")) cat = "dev";
                else if (categories.contains("Network") || categories.contains("WebBrowser")) cat = "web";
                else if (categories.contains("Multimedia") || categories.contains("Audio") || categories.contains("Video")) cat = "media";
                else if (categories.contains("Settings") || categories.contains("System")) cat = "system";
                else if (categories.contains("Utility") || categories.contains("Accessories")) cat = "tools";
                else if (categories.contains("Game")) cat = "games";
                QVariantMap app;
                app["name"] = name;
                app["icon"] = iconText;
                app["cmd"] = exec;
                app["clr"] = clr;
                app["category"] = cat;
                app["source"] = "desktop"; // Mark as auto-discovered
                apps.append(app);
            }
        }
        // Sort alphabetically
        std::sort(apps.begin(), apps.end(), [](const QVariant &a, const QVariant &b) {
            return a.toMap()["name"].toString().toLower() < b.toMap()["name"].toString().toLower();
        });
        return apps;
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

    Q_INVOKABLE void setUiScale(double scale) {
        m_uiScale = qBound(1.0, scale, 4.0);
        saveAccessibility();
        applyCursorSize();
        emit uiScaleChanged();
    }

    void applyCursorSize() {
        int cursorSize = qRound(24 * m_uiScale);
        qDebug() << "Setting cursor size:" << cursorSize;
        // Set env for child processes
        qputenv("XCURSOR_SIZE", QByteArray::number(cursorSize));
        // Write full Xresources + cursor icon theme + reload everything
        QString script = QString(
            "export DISPLAY=:0 XCURSOR_SIZE=%1;"
            // Update Xresources
            "echo 'Xcursor.size: %1' > /tmp/.xcursor_size;"
            "echo 'Xcursor.theme: DMZ-White' >> /tmp/.xcursor_size;"
            "xrdb -merge /tmp/.xcursor_size;"
            // Create cursor theme config
            "mkdir -p ~/.icons/default;"
            "echo '[Icon Theme]' > ~/.icons/default/index.theme;"
            "echo 'Name=Default' >> ~/.icons/default/index.theme;"
            "echo 'Size=%1' >> ~/.icons/default/index.theme;"
            "echo 'Inherits=DMZ-White' >> ~/.icons/default/index.theme;"
            // Reload root cursor
            "xsetroot -cursor_name left_ptr;"
            // Tell openbox to reconfigure (picks up new cursor)
            "openbox --reconfigure 2>/dev/null || true"
        ).arg(cursorSize);
        QProcess::startDetached("bash", QStringList() << "-c" << script);
    }

    // Home Screen management
    int homePageCount() const { return qMax(1, m_homePages.size()); }
    QVariantList homeScreenData() const { return m_homePages; }

    Q_INVOKABLE QVariantList getHomePageApps(int page) {
        if (page >= 0 && page < m_homePages.size())
            return m_homePages[page].toList();
        return {};
    }

    Q_INVOKABLE void addToHomeScreen(int page, const QString &name, const QString &icon, const QString &cmd, const QString &clr) {
        qDebug() << "addToHomeScreen: page=" << page << "name=" << name << "cmd=" << cmd << "pages.size=" << m_homePages.size();
        // Ensure we have enough pages
        while (m_homePages.size() <= page) {
            QVariantList emptyPage;
            m_homePages.append(QVariant::fromValue(emptyPage));
        }
        QVariantMap app;
        app["name"] = name;
        app["icon"] = icon;
        app["cmd"] = cmd;
        app["clr"] = clr;
        // Get current page apps
        QVariantList pageApps;
        if (m_homePages[page].canConvert<QVariantList>()) {
            pageApps = m_homePages[page].toList();
        }
        // Avoid duplicates
        for (const auto &a : pageApps) {
            if (a.toMap()["cmd"].toString() == cmd) {
                qDebug() << "addToHomeScreen: DUPLICATE, skipping" << cmd;
                return;
            }
        }
        pageApps.append(QVariant::fromValue(app));
        m_homePages[page] = QVariant::fromValue(pageApps);
        qDebug() << "addToHomeScreen: SUCCESS! pageApps.size=" << pageApps.size();
        saveHomeScreen();
        emit homeScreenChanged();
    }

    Q_INVOKABLE void removeFromHomeScreen(int page, int index) {
        if (page >= 0 && page < m_homePages.size()) {
            QVariantList pageApps = m_homePages[page].toList();
            if (index >= 0 && index < pageApps.size()) {
                pageApps.removeAt(index);
                m_homePages[page] = pageApps;
                saveHomeScreen();
                emit homeScreenChanged();
            }
        }
    }

    Q_INVOKABLE void addHomePage() {
        m_homePages.append(QVariantList());
        saveHomeScreen();
        emit homeScreenChanged();
    }

    Q_INVOKABLE void removeHomePage(int page) {
        if (page >= 0 && page < m_homePages.size() && m_homePages.size() > 1) {
            m_homePages.removeAt(page);
            saveHomeScreen();
            emit homeScreenChanged();
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
    void uiScaleChanged();
    void homeScreenChanged();
    void faceAuthResult(bool success);

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
    int m_slowTick = 0;
    double m_uiScale = 1.0;
    QVariantList m_homePages; // Each element is a QVariantList of QVariantMaps
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

    void loadAccessibility() {
        QFile f(QDir::homePath() + "/.config/mb-os/accessibility.conf");
        if (f.open(QIODevice::ReadOnly)) {
            QTextStream in(&f);
            while (!in.atEnd()) {
                QString line = in.readLine().trimmed();
                if (line.startsWith("uiScale=")) {
                    m_uiScale = qBound(1.0, line.mid(8).toDouble(), 4.0);
                }
            }
            f.close();
        }
    }

    void saveAccessibility() {
        QDir().mkpath(QDir::homePath() + "/.config/mb-os");
        QFile f(QDir::homePath() + "/.config/mb-os/accessibility.conf");
        if (f.open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream out(&f);
            out << "uiScale=" << m_uiScale << "\n";
            f.close();
        }
    }

    void loadHomeScreen() {
        QFile f(QDir::homePath() + "/.config/mb-os/homescreen.json");
        if (f.open(QIODevice::ReadOnly)) {
            QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
            f.close();
            QJsonArray pages = doc.object()["pages"].toArray();
            m_homePages.clear();
            for (const auto &page : pages) {
                QVariantList pageApps;
                for (const auto &app : page.toArray()) {
                    pageApps.append(app.toObject().toVariantMap());
                }
                m_homePages.append(QVariant::fromValue(pageApps));
            }
        }
        if (m_homePages.isEmpty()) {
            QVariantList emptyPage;
            m_homePages.append(QVariant::fromValue(emptyPage)); // At least one page
        }
        qDebug() << "loadHomeScreen: loaded" << m_homePages.size() << "pages from" << QDir::homePath();
    }

    void saveHomeScreen() {
        QString path = QDir::homePath() + "/.config/mb-os/homescreen.json";
        qDebug() << "saveHomeScreen: homePath=" << QDir::homePath() << "file=" << path << "pages=" << m_homePages.size();
        QDir().mkpath(QDir::homePath() + "/.config/mb-os");
        QJsonObject root;
        QJsonArray pages;
        for (const auto &page : m_homePages) {
            QJsonArray pageArr;
            for (const auto &app : page.toList()) {
                QJsonObject obj = QJsonObject::fromVariantMap(app.toMap());
                pageArr.append(obj);
            }
            pages.append(pageArr);
        }
        root["pages"] = pages;
        QFile f(path);
        if (f.open(QIODevice::WriteOnly)) {
            QByteArray data = QJsonDocument(root).toJson(QJsonDocument::Indented);
            f.write(data);
            f.close();
            qDebug() << "saveHomeScreen: WRITTEN" << data.size() << "bytes to" << path;
        } else {
            qDebug() << "saveHomeScreen: FAILED to open" << path << f.errorString();
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

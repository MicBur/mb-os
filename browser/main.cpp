#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QCommandLineParser>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>
#include <QDir>
#include <QStringList>
#include <QDebug>
#include <QProcess>
#include <QWebEngineNotification>
#include <QWebEngineProfile>

// Forward web notifications to system notification daemon (dunst)
void handleNotification(std::unique_ptr<QWebEngineNotification> notification) {
    QString title = notification->title();
    QString body = notification->message();
    QString origin = notification->origin().host();
    qDebug() << "Web Notification:" << title << body << "from" << origin;
    // Forward to notify-send (dunst will display it)
    QProcess::startDetached("notify-send", QStringList()
        << "-a" << "MB-Browser"
        << "-u" << "normal"
        << "-t" << "8000"
        << title
        << body);
    notification->show();
}

int main(int argc, char *argv[]) {
    // Extension loading
    QDir extDir("/home/mbuser/.config/mb-browser/extensions");
    QStringList extPaths;
    if (extDir.exists()) {
        for (const QString &subdir : extDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
            extPaths.append(extDir.absoluteFilePath(subdir));
        }
    }
    QString flags = "--enable-extensions";
    if (!extPaths.isEmpty()) {
        flags += " --load-extension=" + extPaths.join(",");
        qDebug() << "Loading Chrome extensions:" << extPaths;
    }
    qputenv("QTWEBENGINE_CHROMIUM_FLAGS", flags.toUtf8());

    QtWebEngineQuick::initialize();
    QGuiApplication app(argc, argv);
    app.setOrganizationName("MB-OS");
    app.setOrganizationDomain("mb-os.local");
    app.setApplicationName("mb-browser");
    app.setApplicationVersion("1.0");

    // CRITICAL: Set persistent storage paths FIRST, before any other profile access!
    // Qt WebEngine locks the profile configuration on first use.
    QString dataPath = QDir::homePath() + "/.config/mb-browser/data";
    QString cachePath = QDir::homePath() + "/.config/mb-browser/cache";
    QDir().mkpath(dataPath);
    QDir().mkpath(cachePath);
    QWebEngineProfile::defaultProfile()->setPersistentStoragePath(dataPath);
    QWebEngineProfile::defaultProfile()->setCachePath(cachePath);
    QWebEngineProfile::defaultProfile()->setPersistentCookiesPolicy(QWebEngineProfile::ForcePersistentCookies);
    QWebEngineProfile::defaultProfile()->setHttpUserAgent(
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36");

    // Enable web notifications → forward to dunst via notify-send (AFTER storage setup!)
    QWebEngineProfile::defaultProfile()->setNotificationPresenter(&handleNotification);
    qDebug() << "Browser storage:" << dataPath << "home:" << QDir::homePath();

    // Parse --url / -u command line argument
    QCommandLineParser parser;
    parser.setApplicationDescription("MB-Browser - Private & Secure");
    parser.addHelpOption();
    parser.addVersionOption();

    QCommandLineOption urlOption(
        QStringList() << "u" << "url",
        "URL to open on startup.",
        "url",
        "https://duckduckgo.com"
    );
    parser.addOption(urlOption);
    parser.addPositionalArgument("url", "URL to open", "[url]");
    parser.process(app);

    QString startUrl = parser.value(urlOption);
    // Also accept URL as positional argument (xdg-open passes it this way)
    QStringList posArgs = parser.positionalArguments();
    if (!posArgs.isEmpty() && posArgs.first().startsWith("http")) {
        startUrl = posArgs.first();
    }

    // Pass URL and home path to QML context
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("startUrl", startUrl);
    engine.rootContext()->setContextProperty("homePath", QDir::homePath());

    const QUrl qmlUrl(u"qrc:/main.qml"_qs);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [qmlUrl](QObject *obj, const QUrl &objUrl) {
        if (!obj && qmlUrl == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    engine.load(qmlUrl);

    return app.exec();
}

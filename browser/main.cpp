#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QCommandLineParser>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>
#include <QDir>
#include <QStringList>
#include <QDebug>

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
    app.setApplicationName("mb-browser");
    app.setApplicationVersion("1.0");

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

    // Pass URL to QML context
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("startUrl", startUrl);

    const QUrl qmlUrl(u"qrc:/main.qml"_qs);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [qmlUrl](QObject *obj, const QUrl &objUrl) {
        if (!obj && qmlUrl == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    engine.load(qmlUrl);

    return app.exec();
}

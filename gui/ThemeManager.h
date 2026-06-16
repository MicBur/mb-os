#pragma once
#include <QObject>
#include <QString>
#include <QColor>

class ThemeManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString accentColor READ accentColor NOTIFY themeChanged)
    Q_PROPERTY(QString secondaryColor READ secondaryColor NOTIFY themeChanged)
    Q_PROPERTY(QString glassBgColor READ glassBgColor NOTIFY themeChanged)
    Q_PROPERTY(QString glassBorderColor READ glassBorderColor NOTIFY themeChanged)
    Q_PROPERTY(QString glowColor READ glowColor NOTIFY themeChanged)
    Q_PROPERTY(QString glowColor2 READ glowColor2 NOTIFY themeChanged)

public:
    explicit ThemeManager(QObject *parent = nullptr);

    QString accentColor() const { return m_accentColor; }
    QString secondaryColor() const { return m_secondaryColor; }
    QString glassBgColor() const { return m_glassBgColor; }
    QString glassBorderColor() const { return m_glassBorderColor; }
    QString glowColor() const { return m_glowColor; }
    QString glowColor2() const { return m_glowColor2; }

    Q_INVOKABLE void loadTheme();
    Q_INVOKABLE void setTheme(const QString &themeName);

signals:
    void themeChanged();

private:
    QString m_accentColor;
    QString m_secondaryColor;
    QString m_glassBgColor;
    QString m_glassBorderColor;
    QString m_glowColor;
    QString m_glowColor2;
};

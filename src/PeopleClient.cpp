/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "PeopleClient.h"

#include <KApplicationTrader>
#include <KIO/ApplicationLauncherJob>

#include <QClipboard>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QStandardPaths>
#include <QUrl>

KService::Ptr PeopleClient::takerAmong(const KService::List &services, const QString &scheme)
{
    for (const auto &service : services) {
        if (service && !service->exec().isEmpty() && service->schemeHandlers().contains(scheme)) return service;
    }
    return {};
}

// The application that takes a kind of address: the one chosen for it, or
// one that says it takes it although it keeps out of the menus, as KDE
// Connect's does for a number to text or call.
KService::Ptr PeopleClient::taker(const QString &scheme)
{
    if (auto chosen = KApplicationTrader::preferredService(QStringLiteral("x-scheme-handler/") + scheme)) return chosen;
    return takerAmong(KService::allServices(), scheme);
}

PeopleClient::PeopleClient(QObject *parent)
    : QObject(parent)
{
    refresh();
}

void PeopleClient::setProgram(const QString &program)
{
    m_programSet = true;
    if (m_program == program) return;
    m_program = program;
    Q_EMIT availableChanged();
}

void PeopleClient::refresh()
{
    QString program = m_program;
    if (!m_programSet) {
        program = QStandardPaths::findExecutable(QString::fromLatin1(Command));
        // A command installed for one person, where the session's path
        // leaves that folder out.
        if (program.isEmpty())
            program = QStandardPaths::findExecutable(QString::fromLatin1(Command),
                                                     {QDir::homePath() + QStringLiteral("/.local/bin")});
    }
    const bool text = bool(taker(QStringLiteral("sms"))), call = bool(taker(QStringLiteral("tel"))),
               email = bool(taker(QStringLiteral("mailto")));
    if (program == m_program && text == m_canText && call == m_canCall && email == m_canEmail) return;
    m_program = program;
    m_canText = text;
    m_canCall = call;
    m_canEmail = email;
    Q_EMIT availableChanged();
}

void PeopleClient::ask(const QStringList &arguments, bool forPerson)
{
    if (m_program.isEmpty()) return;
    const int asked = forPerson ? ++m_personAsked : ++m_listAsked;
    auto *process = new QProcess(this);
    connect(process, &QProcess::errorOccurred, process, &QObject::deleteLater);
    connect(process, &QProcess::finished, this, [this, process, asked, forPerson](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        // An older answer than the question now waiting is dropped.
        if (asked != (forPerson ? m_personAsked : m_listAsked)) return;
        if (status != QProcess::NormalExit || code != 0) return;
        const QJsonObject answer = QJsonDocument::fromJson(process->readAllStandardOutput()).object();
        if (forPerson) {
            // A person no longer there closes its page.
            m_person = answer.contains(QLatin1String("error")) ? QVariantMap() : answer.toVariantMap();
            Q_EMIT personChanged();
            // Who is who may have changed with it.
            ask(QStringList{QStringLiteral("people")} + (m_words.isEmpty() ? QStringList() : QStringList{m_words}), false);
        } else if (!answer.contains(QLatin1String("error"))) {
            m_people = answer.value(QLatin1String("people")).toVariant().toList();
            m_count = answer.value(QLatin1String("count")).toInt();
            Q_EMIT peopleChanged();
        }
    });
    process->start(m_program, arguments, QIODevice::ReadOnly);
}

void PeopleClient::find(const QString &words)
{
    m_words = words.simplified();
    ask(QStringList{QStringLiteral("people")} + (m_words.isEmpty() ? QStringList() : QStringList{m_words}), false);
}

void PeopleClient::open(const QString &id)
{
    if (id.isEmpty()) return;
    ask({QStringLiteral("person"), id}, true);
}

void PeopleClient::close()
{
    ++m_personAsked;
    if (m_person.isEmpty()) return;
    m_person.clear();
    Q_EMIT personChanged();
}

void PeopleClient::decide(const QString &verb, const QString &other)
{
    const QString id = m_person.value(QStringLiteral("id")).toString();
    if (id.isEmpty()) return;
    ask(other.isEmpty() ? QStringList{verb, id} : QStringList{verb, id, other}, true);
}

void PeopleClient::join(const QString &other)
{
    if (!other.isEmpty()) decide(QStringLiteral("join"), other);
}

void PeopleClient::notSame(const QString &other)
{
    if (!other.isEmpty()) decide(QStringLiteral("not-same"), other);
}

void PeopleClient::separate()
{
    decide(QStringLiteral("separate"), QString());
}

QString PeopleClient::address(const QString &kind, const QString &value)
{
    const QString to = value.trimmed();
    if (to.isEmpty()) return {};
    if (kind == QLatin1String("text")) return QStringLiteral("sms:") + to;
    if (kind == QLatin1String("call")) return QStringLiteral("tel:") + to;
    if (kind == QLatin1String("email")) return QStringLiteral("mailto:") + to;
    return {};
}

bool PeopleClient::reach(const QString &kind, const QString &value)
{
    const QString to = address(kind, value);
    if (to.isEmpty()) return false;
    const bool offered = kind == QLatin1String("text") ? m_canText : kind == QLatin1String("call") ? m_canCall : m_canEmail;
    if (!offered) return false;
    // The address is handed over as an address; nothing typed is run.
    const QUrl url(to);
    const auto service = taker(url.scheme());
    if (!service) return false;
    auto *job = new KIO::ApplicationLauncherJob(service, this);
    job->setUrls({url});
    job->start();
    return true;
}

void PeopleClient::copy(const QString &value)
{
    if (auto *clipboard = QGuiApplication::clipboard()) clipboard->setText(value);
}

#include "FileDetails.h"

#include <KFileMetaData/Extractor>
#include <KFileMetaData/ExtractorCollection>
#include <KFileMetaData/Properties>
#include <KFileMetaData/SimpleExtractionResult>

#include <QCoreApplication>
#include <QDateTime>
#include <QLocale>
#include <QVariantMap>

using namespace KFileMetaData;

namespace
{
QString length(double seconds)
{
    const qint64 total = qRound64(seconds);
    const qint64 hours = total / 3600;
    const QString minutesAndSeconds =
        QStringLiteral("%1:%2").arg(hours ? (total % 3600) / 60 : total / 60, hours ? 2 : 1, 10, QLatin1Char('0')).arg(total % 60, 2, 10, QLatin1Char('0'));
    return hours ? QStringLiteral("%1:%2").arg(hours).arg(minutesAndSeconds) : minutesAndSeconds;
}
}

QVariantList readMediaDetails(const QString &path, const QString &mimeType)
{
    const bool photo = mimeType.startsWith(QLatin1String("image/"));
    const bool song = mimeType.startsWith(QLatin1String("audio/"));
    const bool video = mimeType.startsWith(QLatin1String("video/"));
    if (!photo && !song && !video) {
        return {};
    }
    ExtractorCollection collection;
    const auto extractors = collection.fetchExtractors(mimeType);
    SimpleExtractionResult result(path, mimeType, ExtractionResult::ExtractMetaData);
    for (auto *extractor : extractors) {
        extractor->extract(&result);
    }
    const auto properties = result.properties();
    const auto text = [&properties](Property::Property property) {
        return properties.value(property).toString().trimmed();
    };
    QVariantList rows;
    const auto add = [&rows](const char *label, const QString &value) {
        if (!value.isEmpty()) {
            rows.append(QVariantMap{{QStringLiteral("label"), QCoreApplication::translate("FileDetails", label)}, {QStringLiteral("value"), value}});
        }
    };

    const int width = properties.value(Property::Width).toInt();
    const int height = properties.value(Property::Height).toInt();
    if ((photo || video) && width > 0 && height > 0) {
        add("Dimensions", QStringLiteral("%1 × %2").arg(width).arg(height));
    }
    if (photo) {
        QDateTime taken = properties.value(Property::PhotoDateTimeOriginal).toDateTime();
        if (!taken.isValid()) {
            taken = properties.value(Property::ImageDateTime).toDateTime();
        }
        if (taken.isValid()) {
            add("Taken", QLocale().toString(taken, QLocale::ShortFormat));
        }
        // A camera's model usually repeats its maker's name.
        const QString maker = text(Property::Manufacturer);
        const QString model = text(Property::Model);
        add("Camera", model.startsWith(maker, Qt::CaseInsensitive) ? model : QStringLiteral("%1 %2").arg(maker, model).trimmed());
    }
    if (song) {
        add("Title", text(Property::Title));
        add("Artist", text(Property::Artist));
        add("Album", text(Property::Album));
    }
    const double seconds = properties.value(Property::Duration).toDouble();
    if ((song || video) && seconds > 0) {
        add("Length", length(seconds));
    }
    return rows;
}

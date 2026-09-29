#pragma once

#include <QString>
#include <QVariantList>

// A photo's, a song's or a video's details from KDE's metadata readers, as
// labelled rows for Files' Properties. It reads the file, so it runs off the
// GUI thread.
QVariantList readMediaDetails(const QString &path, const QString &mimeType);

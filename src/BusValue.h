/* SPDX-License-Identifier: GPL-2.0-or-later */

#pragma once

#include <QDBusArgument>
#include <QDBusVariant>
#include <QVariant>

namespace tettegouche
{
// A dictionary or list inside a variant arrives as a bus argument; QML and the
// island's rows want it as a plain map or list, all the way down.
inline QVariant plainBusValue(const QVariant &value)
{
    if (value.canConvert<QDBusArgument>()) {
        const auto argument = value.value<QDBusArgument>();
        if (argument.currentType() == QDBusArgument::MapType) {
            QVariantMap map;
            argument >> map;
            for (auto it = map.begin(); it != map.end(); ++it) it.value() = plainBusValue(it.value());
            return map;
        }
        if (argument.currentType() == QDBusArgument::ArrayType) {
            QVariantList list;
            argument >> list;
            for (QVariant &item : list) item = plainBusValue(item);
            return list;
        }
    }
    if (value.canConvert<QDBusVariant>()) return plainBusValue(value.value<QDBusVariant>().variant());
    return value;
}
}

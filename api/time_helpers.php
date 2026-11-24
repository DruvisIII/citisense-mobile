<?php
// ============================================================
// TIMESTAMPS FOR THE APP
// ------------------------------------------------------------
// Dates such as announcements.datePosted and notification.dateSent
// are filled in by MySQL (CURRENT_TIMESTAMP / NOW()), so they are
// in the database's time zone: UTC on Railway, Philippine time on
// XAMPP. Sending them without a zone made the phone read a UTC time
// as Philippine time ("8 hours ago" for a brand-new announcement).
//
// citisense_iso_time() adds the database's real UTC offset, e.g.
// "2026-11-23T10:00:00+00:00". The app converts it to the phone's
// local time. Nothing is hard-coded: the offset is read from MySQL.
// ============================================================

/**
 * Offset of the database's NOW() from UTC, in seconds (cached).
 */
function citisense_db_utc_offset(mysqli $conn): int
{
    static $offset = null;

    if ($offset === null) {
        $offset = 0;
        try {
            $result = $conn->query('SELECT TIMESTAMPDIFF(SECOND, UTC_TIMESTAMP(), NOW()) AS diff');
            if ($result) {
                $diff = (int) ($result->fetch_assoc()['diff'] ?? 0);
                // Round to the nearest 15 minutes (time zones are multiples of it).
                $offset = (int) (round($diff / 900) * 900);
            }
        } catch (Throwable $e) {
            error_log('CitiSense time zone lookup failed: ' . $e->getMessage());
        }
    }

    return $offset;
}

/**
 * A database date/time as ISO 8601 with its UTC offset, or null.
 */
function citisense_iso_time(mysqli $conn, $value): ?string
{
    $value = trim((string) ($value ?? ''));
    if ($value === '' || str_starts_with($value, '0000-00-00')) {
        return null;
    }

    $offset = citisense_db_utc_offset($conn);
    $sign = $offset < 0 ? '-' : '+';
    $abs = abs($offset);
    $zone = sprintf('%s%02d:%02d', $sign, intdiv($abs, 3600), intdiv($abs % 3600, 60));

    try {
        $date = new DateTimeImmutable($value, new DateTimeZone($zone));
        return $date->format('Y-m-d\TH:i:sP');
    } catch (Throwable $e) {
        return null;
    }
}

/**
 * The database's current time, in the same form as citisense_iso_time().
 * Sent with lists as "serverTime": the app measures how old each item is
 * against this clock, so a wrong phone clock or time zone cannot turn
 * "5 minutes ago" into "Yesterday".
 */
function citisense_server_time(mysqli $conn): ?string
{
    try {
        $result = $conn->query('SELECT NOW() AS now');
        $now = $result ? (string) ($result->fetch_assoc()['now'] ?? '') : '';
        return citisense_iso_time($conn, $now);
    } catch (Throwable $e) {
        return null;
    }
}

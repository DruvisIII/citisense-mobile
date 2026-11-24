<?php
// ============================================================
// SHARED HELPERS FOR COMMENTS AND MESSAGES
// ------------------------------------------------------------
// Lookups are done with simple queries instead of JOINs because
// tables imported from XAMPP and tables created on Railway can use
// different text collations, which makes JOINs fail.
// ============================================================

/** The user's barangay and name, or null if the user doesn't exist. */
function conversation_load_user(mysqli $conn, string $userID): ?array
{
    $stmt = $conn->prepare(
        'SELECT userID, firstName, lastName, barangayID FROM users WHERE userID = ? LIMIT 1'
    );
    $stmt->bind_param('s', $userID);
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    return $row ?: null;
}

/**
 * Makes sure these tables store 4-byte characters (emoji). Tables imported
 * from an older export can still use utf8 (3 bytes), which turns 😀 into
 * "?" or rejects the message. Checked once per request, converted once.
 */
function conversation_ensure_utf8mb4(mysqli $conn, array $tables): void
{
    static $checked = [];

    foreach ($tables as $table) {
        if (isset($checked[$table]) || !preg_match('/^[a-z_]+$/', $table)) {
            continue;
        }
        $checked[$table] = true;

        try {
            $stmt = $conn->prepare(
                "SELECT COUNT(*) AS total FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
                   AND CHARACTER_SET_NAME IS NOT NULL AND CHARACTER_SET_NAME <> 'utf8mb4'"
            );
            $stmt->bind_param('s', $table);
            $stmt->execute();
            $notUtf8mb4 = (int) ($stmt->get_result()->fetch_assoc()['total'] ?? 0);
            $stmt->close();

            if ($notUtf8mb4 > 0) {
                // Keep the collation family the admin website joins with.
                $collation = $table === 'resident_messages' ? 'utf8mb4_unicode_ci' : 'utf8mb4_general_ci';
                $conn->query("ALTER TABLE `$table` CONVERT TO CHARACTER SET utf8mb4 COLLATE $collation");
                error_log("CitiSense: converted $table to utf8mb4 so emoji are saved correctly.");
            }
        } catch (Throwable $e) {
            error_log("CitiSense: could not check/convert $table to utf8mb4: " . $e->getMessage());
        }
    }
}

/** Profile picture paths for a list of userIDs: [userID => path]. */
function conversation_user_pictures(mysqli $conn, array $userIDs): array
{
    $ids = array_values(array_unique(array_filter(array_map('strval', $userIDs), 'strlen')));
    if (!$ids) {
        return [];
    }

    $pictures = [];
    $stmt = $conn->prepare('SELECT profilePic FROM users WHERE userID = ? LIMIT 1');
    foreach ($ids as $id) {
        $stmt->bind_param('s', $id);
        $stmt->execute();
        $row = $stmt->get_result()->fetch_assoc();
        $pictures[$id] = trim((string) ($row['profilePic'] ?? ''));
    }
    $stmt->close();

    return $pictures;
}

/** Short one-line preview of a message for a "replying to" quote. */
function conversation_preview(string $text, int $width = 90): string
{
    $text = trim(preg_replace('/\s+/u', ' ', $text) ?? '');
    return mb_strimwidth($text, 0, $width, '…');
}

/** Full names for a list of userIDs: [userID => "First Last"]. */
function conversation_user_names(mysqli $conn, array $userIDs): array
{
    $ids = array_values(array_unique(array_filter(array_map('strval', $userIDs), 'strlen')));
    if (!$ids) {
        return [];
    }

    $names = [];
    $stmt = $conn->prepare('SELECT firstName, lastName FROM users WHERE userID = ? LIMIT 1');
    foreach ($ids as $id) {
        $stmt->bind_param('s', $id);
        $stmt->execute();
        $row = $stmt->get_result()->fetch_assoc();
        if ($row) {
            $names[$id] = trim(($row['firstName'] ?? '') . ' ' . ($row['lastName'] ?? ''));
        }
    }
    $stmt->close();

    return $names;
}

/**
 * Trims a message, drops invisible control characters (keeps line breaks)
 * and limits blank lines.
 */
function conversation_clean_text(string $text): string
{
    $text = str_replace(["\r\n", "\r"], "\n", $text);
    // Invalid UTF-8 would make the patterns below return null.
    if (!mb_check_encoding($text, 'UTF-8')) {
        $text = mb_convert_encoding($text, 'UTF-8', 'UTF-8');
    }
    // Remove only control characters (except line breaks and tabs) and
    // the bidirectional override marks that can disguise text. Everything
    // else is kept: emoji joiners (U+200D), variation selectors, flag tag
    // characters, and emoji newer than this server's Unicode tables
    // (which older PCRE versions count as "unassigned").
    $text = preg_replace('/(?![\n\t])\p{Cc}|[\x{202A}-\x{202E}\x{2066}-\x{2069}]/u', '', $text) ?? '';
    $text = preg_replace("/\n{3,}/", "\n\n", $text) ?? '';
    return trim($text);
}

/**
 * Reply links from the admin website's message_replies table
 * ("item X is a reply to Y"): [itemID => parentID]. Empty when the table
 * does not exist yet.
 */
function conversation_reply_parents(mysqli $conn, string $type, array $itemIDs): array
{
    if (!$itemIDs) {
        return [];
    }

    $parents = [];
    try {
        $stmt = $conn->prepare(
            'SELECT parentID FROM message_replies WHERE itemType = ? AND itemID = ? AND parentType = ? LIMIT 1'
        );
        foreach ($itemIDs as $id) {
            $id = (int) $id;
            $stmt->bind_param('sis', $type, $id, $type);
            $stmt->execute();
            $row = $stmt->get_result()->fetch_assoc();
            if ($row) {
                $parents[$id] = (int) $row['parentID'];
            }
        }
        $stmt->close();
    } catch (Throwable $e) {
        return [];
    }

    return $parents;
}

/** Saves "item is a reply to parent" in message_replies, if that table exists. */
function conversation_save_reply_link(mysqli $conn, string $itemType, int $itemID, string $parentType, int $parentID): void
{
    try {
        $stmt = $conn->prepare(
            'INSERT IGNORE INTO message_replies (itemType, itemID, parentType, parentID) VALUES (?, ?, ?, ?)'
        );
        $stmt->bind_param('sisi', $itemType, $itemID, $parentType, $parentID);
        $stmt->execute();
        $stmt->close();
    } catch (Throwable $e) {
        // The admin website creates this table; replies still post without it.
        error_log('CitiSense reply link skipped: ' . $e->getMessage());
    }
}

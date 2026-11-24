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
    $text = preg_replace('/[^\P{C}\n\t]/u', '', $text) ?? '';
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

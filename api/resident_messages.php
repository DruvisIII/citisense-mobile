<?php
// ============================================================
// MESSAGES WITH THE BARANGAY (resident side)
// ------------------------------------------------------------
// Header X-Auth-Token: session token from login.php
//
// POST action=list    userID [, includeReports=1]
// POST action=send    userID, message [, reportID] [, replyTo]
// POST action=delete  userID, key
//
// One conversation per resident, the same one the admin website's
// Messages page shows:
//   - general messages      resident_messages  (key "d<messageID>")
//   - messages about one    report_messages    (key "r<id>")
//     of the resident's reports, tagged with that report
// Replies to a specific message are saved in message_replies
// (the admin website's table): "item X is a reply to Y".
//
// A resident only ever sees their own conversation, can only attach
// their own reports, and can only delete messages they sent. The
// barangay's messages can never be deleted from the app.
// ============================================================

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Accept, X-Auth-Token');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/time_helpers.php';
require_once __DIR__ . '/conversation_common.php';

function messages_respond(bool $success, string $message, int $status = 200, array $extra = []): never
{
    http_response_code($status);
    echo json_encode(['success' => $success, 'message' => $message] + $extra, JSON_UNESCAPED_UNICODE);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    messages_respond(false, 'Invalid request method.', 405);
}

const MESSAGE_MAX_LENGTH = 2000;
const MESSAGES_PER_HOUR = 30;

$action = (string) ($_POST['action'] ?? 'list');
$userID = trim((string) ($_POST['userID'] ?? ''));

if ($userID === '') {
    messages_respond(false, 'Your session has expired. Please log in again.', 401, ['code' => 'SESSION_EXPIRED']);
}

/** "r12" / "d5" to [table type, id], or null. */
function messages_key_parts(string $key): ?array
{
    if (!preg_match('/^([rd])(\d{1,10})$/', $key, $m)) {
        return null;
    }
    return [$m[1] === 'r' ? 'report_message' : 'resident_message', (int) $m[2]];
}

function messages_key(string $type, int $id): string
{
    return ($type === 'report_message' ? 'r' : 'd') . $id;
}

/** The resident's reports in their barangay: [reportID => row]. */
function messages_load_reports(mysqli $conn, string $userID, string $barangayID): array
{
    $stmt = $conn->prepare(
        'SELECT r.reportID, r.dateReported, r.statusID, c.categoryName, s.statusName
         FROM reports r
         LEFT JOIN categories c ON c.categoryID = r.categoryID
         LEFT JOIN stats s ON s.statusID = r.statusID
         WHERE r.userID = ? AND r.barangayID = ?
         ORDER BY r.dateReported DESC, r.reportID DESC'
    );
    $stmt->bind_param('ss', $userID, $barangayID);
    $stmt->execute();
    $reports = [];
    foreach ($stmt->get_result()->fetch_all(MYSQLI_ASSOC) as $row) {
        $reports[(string) $row['reportID']] = $row;
    }
    $stmt->close();

    return $reports;
}

/** First photo of each report: [reportID => imagePath]. */
function messages_report_images(mysqli $conn, array $reportIDs): array
{
    $images = [];
    $stmt = $conn->prepare(
        'SELECT imagePath FROM reportimages WHERE reportID = ? ORDER BY imagesID ASC LIMIT 1'
    );
    foreach ($reportIDs as $reportID) {
        $reportID = (string) $reportID;
        $stmt->bind_param('s', $reportID);
        $stmt->execute();
        $images[$reportID] = trim((string) ($stmt->get_result()->fetch_assoc()['imagePath'] ?? ''));
    }
    $stmt->close();

    return $images;
}

/**
 * Every message of the conversation, oldest first, in the same order as the
 * admin website (time, then general before report messages, then id).
 */
function messages_load_rows(mysqli $conn, string $userID, string $barangayID, array $reports): array
{
    $rows = [];

    $stmt = $conn->prepare(
        'SELECT messageID, senderType, senderID, message, created_at
         FROM resident_messages
         WHERE userID = ? AND barangayID = ?'
    );
    $stmt->bind_param('ss', $userID, $barangayID);
    $stmt->execute();
    foreach ($stmt->get_result()->fetch_all(MYSQLI_ASSOC) as $row) {
        $rows[] = [
            'type' => 'resident_message',
            'id' => (int) $row['messageID'],
            'reportID' => '',
            'senderType' => (string) $row['senderType'],
            'senderID' => (string) $row['senderID'],
            'message' => (string) $row['message'],
            'at' => (string) $row['created_at'],
        ];
    }
    $stmt->close();

    if ($reports) {
        $stmt = $conn->prepare(
            'SELECT id, reportID, senderType, senderID, message, created_at
             FROM report_messages
             WHERE reportID = ?'
        );
        foreach (array_keys($reports) as $reportID) {
            $reportID = (string) $reportID;
            $stmt->bind_param('s', $reportID);
            $stmt->execute();
            foreach ($stmt->get_result()->fetch_all(MYSQLI_ASSOC) as $row) {
                $rows[] = [
                    'type' => 'report_message',
                    'id' => (int) $row['id'],
                    'reportID' => (string) $row['reportID'],
                    'senderType' => (string) $row['senderType'],
                    'senderID' => (string) $row['senderID'],
                    'message' => (string) $row['message'],
                    'at' => (string) $row['created_at'],
                ];
            }
        }
        $stmt->close();
    }

    usort($rows, static function (array $a, array $b): int {
        // The admin website sorts "d" (general) before "r" (report) at equal times.
        $aGroup = $a['type'] === 'report_message' ? 'r' : 'd';
        $bGroup = $b['type'] === 'report_message' ? 'r' : 'd';
        return [$a['at'], $aGroup, $a['id']] <=> [$b['at'], $bGroup, $b['id']];
    });

    return $rows;
}

/** Reply links for these rows: ["type:id" => [type, id]]. */
function messages_reply_parents(mysqli $conn, array $rows): array
{
    $parents = [];
    if (!$rows) {
        return $parents;
    }

    $stmt = $conn->prepare(
        'SELECT parentType, parentID FROM message_replies WHERE itemType = ? AND itemID = ? LIMIT 1'
    );
    foreach ($rows as $row) {
        $type = $row['type'];
        $id = $row['id'];
        $stmt->bind_param('si', $type, $id);
        $stmt->execute();
        $link = $stmt->get_result()->fetch_assoc();
        if ($link) {
            $parents[$type . ':' . $id] = [(string) $link['parentType'], (int) $link['parentID']];
        }
    }
    $stmt->close();

    return $parents;
}

/** Number of messages this resident sent in the last hour (both tables). */
function messages_recent_count(mysqli $conn, string $userID): int
{
    $total = 0;

    $stmt = $conn->prepare(
        "SELECT COUNT(*) AS total FROM resident_messages
         WHERE userID = ? AND senderType = 'resident'
           AND created_at >= NOW() - INTERVAL 1 HOUR"
    );
    $stmt->bind_param('s', $userID);
    $stmt->execute();
    $total += (int) ($stmt->get_result()->fetch_assoc()['total'] ?? 0);
    $stmt->close();

    $stmt = $conn->prepare(
        "SELECT COUNT(*) AS total FROM report_messages
         WHERE senderType = 'resident' AND senderID = ?
           AND created_at >= NOW() - INTERVAL 1 HOUR"
    );
    $stmt->bind_param('s', $userID);
    $stmt->execute();
    $total += (int) ($stmt->get_result()->fetch_assoc()['total'] ?? 0);
    $stmt->close();

    return $total;
}

try {
    citisense_require_user($conn, $userID);

    // Same tables as the admin website (created there too); creating
    // them here lets the app work before an admin has logged in.
    $conn->query(
        "CREATE TABLE IF NOT EXISTS resident_messages (
            messageID INT(11) NOT NULL AUTO_INCREMENT,
            barangayID VARCHAR(50) NOT NULL,
            userID VARCHAR(50) NOT NULL,
            senderType ENUM('resident','barangay') NOT NULL,
            senderID VARCHAR(50) NOT NULL,
            message TEXT NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (messageID),
            KEY idx_resident_messages_user (barangayID, userID)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
    );
    $conn->query(
        "CREATE TABLE IF NOT EXISTS report_messages (
            id INT AUTO_INCREMENT PRIMARY KEY,
            reportID VARCHAR(50) NOT NULL,
            senderType ENUM('resident', 'barangay') NOT NULL,
            senderID VARCHAR(50) NOT NULL,
            message TEXT NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_report_messages_report (reportID)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );
    $conn->query(
        "CREATE TABLE IF NOT EXISTS message_replies (
            itemType VARCHAR(20) NOT NULL,
            itemID INT(11) NOT NULL,
            parentType VARCHAR(20) NOT NULL,
            parentID INT(11) NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (itemType, itemID),
            KEY idx_message_replies_parent (parentType, parentID)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
    );
    conversation_ensure_utf8mb4($conn, ['resident_messages', 'report_messages']);

    $user = conversation_load_user($conn, $userID);
    if ($user === null || trim((string) $user['barangayID']) === '') {
        messages_respond(false, 'Please choose your barangay in Settings first.', 400);
    }
    $barangayID = (string) $user['barangayID'];

    $reports = messages_load_reports($conn, $userID, $barangayID);
    $rows = messages_load_rows($conn, $userID, $barangayID, $reports);

    $keysInConversation = [];
    $ownKeys = [];
    foreach ($rows as $row) {
        $key = messages_key($row['type'], $row['id']);
        $keysInConversation[$key] = true;
        if ($row['senderType'] === 'resident' && $row['senderID'] === $userID) {
            $ownKeys[$key] = true;
        }
    }

    $resultMessage = 'Messages loaded.';

    // --------------------------------------------------------- send
    if ($action === 'send') {
        $message = conversation_clean_text((string) ($_POST['message'] ?? ''));
        $reportID = trim((string) ($_POST['reportID'] ?? ''));
        $replyTo = trim((string) ($_POST['replyTo'] ?? ''));

        if ($message === '') {
            messages_respond(false, 'Please type a message first.', 400);
        }
        if (mb_strlen($message) > MESSAGE_MAX_LENGTH) {
            messages_respond(false, 'Messages can be up to ' . MESSAGE_MAX_LENGTH . ' characters.', 400);
        }
        if ($reportID !== '' && !isset($reports[$reportID])) {
            messages_respond(false, 'You can only ask about reports you submitted.', 404);
        }

        $replyParts = null;
        if ($replyTo !== '') {
            $replyParts = messages_key_parts($replyTo);
            if ($replyParts === null || !isset($keysInConversation[$replyTo])) {
                messages_respond(false, 'The message you are replying to was deleted.', 404);
            }
        }

        if (messages_recent_count($conn, $userID) >= MESSAGES_PER_HOUR) {
            messages_respond(false, 'You are sending messages too quickly. Please try again later.', 429);
        }

        $conn->begin_transaction();
        try {
            if ($reportID !== '') {
                $stmt = $conn->prepare(
                    "INSERT INTO report_messages (reportID, senderType, senderID, message)
                     VALUES (?, 'resident', ?, ?)"
                );
                $stmt->bind_param('sss', $reportID, $userID, $message);
                $stmt->execute();
                $newType = 'report_message';
            } else {
                $stmt = $conn->prepare(
                    "INSERT INTO resident_messages (barangayID, userID, senderType, senderID, message)
                     VALUES (?, ?, 'resident', ?, ?)"
                );
                $stmt->bind_param('ssss', $barangayID, $userID, $userID, $message);
                $stmt->execute();
                $newType = 'resident_message';
            }
            $newID = (int) $conn->insert_id;
            $stmt->close();

            if ($replyParts !== null) {
                $stmt = $conn->prepare(
                    'INSERT INTO message_replies (itemType, itemID, parentType, parentID) VALUES (?, ?, ?, ?)'
                );
                $stmt->bind_param('sisi', $newType, $newID, $replyParts[0], $replyParts[1]);
                $stmt->execute();
                $stmt->close();
            }

            $conn->commit();
        } catch (Throwable $sendError) {
            $conn->rollback();
            throw $sendError;
        }

        $resultMessage = 'Message sent.';
        $rows = messages_load_rows($conn, $userID, $barangayID, $reports);

    // ------------------------------------------------------- delete
    } elseif ($action === 'delete') {
        $key = trim((string) ($_POST['key'] ?? ''));
        $parts = messages_key_parts($key);

        if ($parts === null || !isset($keysInConversation[$key])) {
            messages_respond(false, 'Message not found. It may already have been deleted.', 404);
        }
        // Only the resident's own messages; never the barangay's.
        if (!isset($ownKeys[$key])) {
            messages_respond(false, 'You can only delete messages you sent.', 403);
        }

        [$type, $id] = $parts;
        $conn->begin_transaction();
        try {
            if ($type === 'report_message') {
                $stmt = $conn->prepare(
                    "DELETE FROM report_messages
                     WHERE id = ? AND senderType = 'resident' AND senderID = ?"
                );
                $stmt->bind_param('is', $id, $userID);
            } else {
                $stmt = $conn->prepare(
                    "DELETE FROM resident_messages
                     WHERE messageID = ? AND userID = ? AND senderType = 'resident' AND senderID = ?"
                );
                $stmt->bind_param('iss', $id, $userID, $userID);
            }
            $stmt->execute();
            $deleted = $stmt->affected_rows;
            $stmt->close();

            if ($deleted !== 1) {
                throw new RuntimeException('Message was not deleted.');
            }

            // The deleted message is no longer a reply. Replies TO it keep
            // their link, so they show "Original message was deleted".
            $stmt = $conn->prepare('DELETE FROM message_replies WHERE itemType = ? AND itemID = ?');
            $stmt->bind_param('si', $type, $id);
            $stmt->execute();
            $stmt->close();

            $conn->commit();
        } catch (Throwable $deleteError) {
            $conn->rollback();
            throw $deleteError;
        }

        $resultMessage = 'Message deleted.';
        $rows = messages_load_rows($conn, $userID, $barangayID, $reports);
    } elseif ($action !== 'list') {
        messages_respond(false, 'Unknown action.', 400);
    }

    // --------------------------------------------------------- list
    $officialIDs = [];
    foreach ($rows as $row) {
        if ($row['senderType'] === 'barangay') {
            $officialIDs[] = $row['senderID'];
        }
    }
    $names = conversation_user_names($conn, $officialIDs);

    $barangayName = '';
    $stmt = $conn->prepare('SELECT barangayName FROM barangay WHERE barangayID = ? LIMIT 1');
    $stmt->bind_param('s', $barangayID);
    $stmt->execute();
    $barangayRow = $stmt->get_result()->fetch_assoc();
    $stmt->close();
    if ($barangayRow) {
        $barangayName = (string) $barangayRow['barangayName'];
    }

    $reportLabel = static function (string $reportID) use ($reports): string {
        if ($reportID === '') {
            return '';
        }
        $category = trim((string) ($reports[$reportID]['categoryName'] ?? ''));
        return $category !== '' ? $reportID . ' · ' . $category : $reportID;
    };

    $messages = [];
    $byKey = [];
    foreach ($rows as $row) {
        $fromBarangay = $row['senderType'] === 'barangay';
        $isMine = !$fromBarangay && $row['senderID'] === $userID;
        $key = messages_key($row['type'], $row['id']);

        $byKey[$key] = count($messages);
        $messages[] = [
            'key' => $key,
            'id' => $row['id'],
            'reportID' => $row['reportID'],
            'reportLabel' => $reportLabel($row['reportID']),
            'fromBarangay' => $fromBarangay,
            'isMine' => $isMine,
            'canDelete' => $isMine,
            'name' => $fromBarangay
                ? (($names[$row['senderID']] ?? '') ?: 'Barangay Official')
                : 'You',
            'message' => $row['message'],
            'createdAt' => citisense_iso_time($conn, $row['at']),
            'replyTo' => null,
        ];
    }

    // "Replying to …" quotes.
    $parents = messages_reply_parents($conn, $rows);
    foreach ($messages as $i => $message) {
        $parts = messages_key_parts($message['key']);
        $parent = $parents[$parts[0] . ':' . $parts[1]] ?? null;
        if ($parent === null) {
            continue;
        }

        $parentKey = messages_key($parent[0], $parent[1]);
        if (isset($byKey[$parentKey])) {
            $original = $messages[$byKey[$parentKey]];
            $messages[$i]['replyTo'] = [
                'key' => $parentKey,
                'name' => $original['fromBarangay'] ? $original['name'] . ' · Barangay' : 'You',
                'text' => conversation_preview($original['message']),
                'reportID' => $original['reportID'],
                'missing' => false,
            ];
        } else {
            $messages[$i]['replyTo'] = [
                'key' => $parentKey,
                'name' => '',
                'text' => 'Original message was deleted',
                'reportID' => '',
                'missing' => true,
            ];
        }
    }

    $extra = [
        'barangayName' => $barangayName,
        'data' => $messages,
    ];

    if (($_POST['includeReports'] ?? '') === '1' || $action !== 'list') {
        $images = messages_report_images($conn, array_keys($reports));
        $reportList = [];
        foreach ($reports as $reportID => $report) {
            $reportList[] = [
                'reportID' => (string) $reportID,
                'categoryName' => (string) ($report['categoryName'] ?? ''),
                'statusID' => (string) ($report['statusID'] ?? ''),
                'statusName' => (string) ($report['statusName'] ?? ''),
                'imagePath' => $images[$reportID] ?? '',
                'dateReported' => citisense_iso_time($conn, (string) $report['dateReported']),
            ];
        }
        $extra['reports'] = $reportList;
    }

    messages_respond(true, $resultMessage, 200, $extra);
} catch (Throwable $e) {
    error_log('CitiSense resident messages error: ' . $e->getMessage());
    messages_respond(false, 'Something went wrong. Please try again later.', 500);
}

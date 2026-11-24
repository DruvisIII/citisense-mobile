<?php
// ============================================================
// MESSAGES WITH THE BARANGAY (resident side)
// ------------------------------------------------------------
// POST action=list  userID [, afterID]
// POST action=send  userID, message
// Header X-Auth-Token: session token from login.php
//
// General conversation between a resident and their barangay,
// stored in the admin website's resident_messages table. The
// admin website's Messages page shows these and replies into the
// same table, so both sides see one conversation.
// A resident only ever sees their own conversation.
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
    echo json_encode(['success' => $success, 'message' => $message] + $extra);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    messages_respond(false, 'Invalid request method.', 405);
}

const MESSAGE_MAX_LENGTH = 2000;

$action = (string) ($_POST['action'] ?? 'list');
$userID = trim((string) ($_POST['userID'] ?? ''));

if ($userID === '') {
    messages_respond(false, 'Your session has expired. Please log in again.', 401);
}

try {
    citisense_require_user($conn, $userID);

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
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );

    $user = conversation_load_user($conn, $userID);
    if ($user === null || trim((string) $user['barangayID']) === '') {
        messages_respond(false, 'Please choose your barangay in Settings first.', 400);
    }
    $barangayID = (string) $user['barangayID'];

    // --------------------------------------------------------- send
    if ($action === 'send') {
        $message = conversation_clean_text((string) ($_POST['message'] ?? ''));

        if ($message === '') {
            messages_respond(false, 'Please type a message first.', 400);
        }
        if (mb_strlen($message) > MESSAGE_MAX_LENGTH) {
            messages_respond(false, 'Messages can be up to ' . MESSAGE_MAX_LENGTH . ' characters.', 400);
        }

        // Basic spam protection: at most 30 messages per hour.
        $stmt = $conn->prepare(
            "SELECT COUNT(*) AS total FROM resident_messages
             WHERE userID = ? AND senderType = 'resident'
               AND created_at >= NOW() - INTERVAL 1 HOUR"
        );
        $stmt->bind_param('s', $userID);
        $stmt->execute();
        $recent = (int) ($stmt->get_result()->fetch_assoc()['total'] ?? 0);
        $stmt->close();

        if ($recent >= 30) {
            messages_respond(false, 'You are sending messages too quickly. Please try again later.', 429);
        }

        $stmt = $conn->prepare(
            "INSERT INTO resident_messages (barangayID, userID, senderType, senderID, message)
             VALUES (?, ?, 'resident', ?, ?)"
        );
        $stmt->bind_param('ssss', $barangayID, $userID, $userID, $message);
        $stmt->execute();
        $stmt->close();
    } elseif ($action !== 'list') {
        messages_respond(false, 'Unknown action.', 400);
    }

    // --------------------------------------------------------- list
    // Oldest first, only this resident's conversation with their barangay.
    $stmt = $conn->prepare(
        "SELECT messageID, senderType, senderID, message, created_at
         FROM resident_messages
         WHERE userID = ? AND barangayID = ?
         ORDER BY created_at ASC, messageID ASC"
    );
    $stmt->bind_param('ss', $userID, $barangayID);
    $stmt->execute();
    $rows = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    $officialIDs = [];
    foreach ($rows as $row) {
        if ($row['senderType'] === 'barangay') {
            $officialIDs[] = (string) $row['senderID'];
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

    $messages = [];
    foreach ($rows as $row) {
        $fromBarangay = $row['senderType'] === 'barangay';
        $messages[] = [
            'id' => (int) $row['messageID'],
            'fromBarangay' => $fromBarangay,
            'name' => $fromBarangay
                ? (($names[(string) $row['senderID']] ?? '') ?: 'Barangay Official')
                : 'You',
            'message' => (string) $row['message'],
            'createdAt' => citisense_iso_time($conn, $row['created_at']),
        ];
    }

    messages_respond(true, $action === 'send' ? 'Message sent.' : 'Messages loaded.', 200, [
        'barangayName' => $barangayName,
        'data' => $messages,
    ]);
} catch (Throwable $e) {
    error_log('CitiSense resident messages error: ' . $e->getMessage());
    messages_respond(false, 'Something went wrong. Please try again later.', 500);
}

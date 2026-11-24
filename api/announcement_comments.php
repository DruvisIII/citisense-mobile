<?php
// ============================================================
// ANNOUNCEMENT COMMENTS (resident side)
// ------------------------------------------------------------
// POST action=list  userID, announceID
// POST action=add   userID, announceID, message [, parentID]
// Header X-Auth-Token: session token from login.php
//
// Uses the admin website's announcement_comments table:
// residents post with senderType 'resident', barangay officials
// with 'barangay' (from the admin website). Comments the admin
// hid are not shown, except to the resident who wrote them.
// Only residents of the announcement's barangay can read or post.
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

function comments_respond(bool $success, string $message, int $status = 200, array $extra = []): never
{
    http_response_code($status);
    echo json_encode(['success' => $success, 'message' => $message] + $extra);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    comments_respond(false, 'Invalid request method.', 405);
}

const COMMENT_MAX_LENGTH = 1000;

$action = (string) ($_POST['action'] ?? 'list');
$userID = trim((string) ($_POST['userID'] ?? ''));
$announceID = (int) ($_POST['announceID'] ?? 0);

if ($userID === '' || $announceID <= 0) {
    comments_respond(false, 'Please open the announcement again.', 400);
}

try {
    citisense_require_user($conn, $userID);

    $conn->query(
        "CREATE TABLE IF NOT EXISTS announcement_comments (
            commentID INT(11) NOT NULL AUTO_INCREMENT,
            announceID INT(11) NOT NULL,
            senderType ENUM('resident','barangay') NOT NULL,
            senderID VARCHAR(50) NOT NULL,
            message TEXT NOT NULL,
            isHidden TINYINT(1) NOT NULL DEFAULT 0,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (commentID),
            KEY idx_announcement_comments_announce (announceID)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );

    $user = conversation_load_user($conn, $userID);
    if ($user === null) {
        comments_respond(false, 'Your session has expired. Please log in again.', 401);
    }

    // The announcement must be for the resident's own barangay.
    $stmt = $conn->prepare('SELECT announceID, barangayID FROM announcements WHERE announceID = ? LIMIT 1');
    $stmt->bind_param('i', $announceID);
    $stmt->execute();
    $announcement = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$announcement || (string) $announcement['barangayID'] !== (string) $user['barangayID']) {
        comments_respond(false, 'This announcement is no longer available.', 404);
    }

    // ---------------------------------------------------------- add
    if ($action === 'add') {
        $message = conversation_clean_text((string) ($_POST['message'] ?? ''));

        if ($message === '') {
            comments_respond(false, 'Please write a comment first.', 400);
        }
        if (mb_strlen($message) > COMMENT_MAX_LENGTH) {
            comments_respond(false, 'Comments can be up to ' . COMMENT_MAX_LENGTH . ' characters.', 400);
        }

        // Basic spam protection: at most 20 comments per hour.
        $stmt = $conn->prepare(
            "SELECT COUNT(*) AS total FROM announcement_comments
             WHERE senderType = 'resident' AND senderID = ?
               AND created_at >= NOW() - INTERVAL 1 HOUR"
        );
        $stmt->bind_param('s', $userID);
        $stmt->execute();
        $recent = (int) ($stmt->get_result()->fetch_assoc()['total'] ?? 0);
        $stmt->close();

        if ($recent >= 20) {
            comments_respond(false, 'You are commenting too quickly. Please try again later.', 429);
        }

        // Optional reply to another visible comment on the same announcement.
        $parentID = (int) ($_POST['parentID'] ?? 0);
        if ($parentID > 0) {
            $stmt = $conn->prepare(
                'SELECT commentID FROM announcement_comments
                 WHERE commentID = ? AND announceID = ? AND isHidden = 0 LIMIT 1'
            );
            $stmt->bind_param('ii', $parentID, $announceID);
            $stmt->execute();
            $parentFound = (bool) $stmt->get_result()->fetch_assoc();
            $stmt->close();

            if (!$parentFound) {
                comments_respond(false, 'The comment you are replying to was removed.', 404);
            }
        }

        $stmt = $conn->prepare(
            "INSERT INTO announcement_comments (announceID, senderType, senderID, message)
             VALUES (?, 'resident', ?, ?)"
        );
        $stmt->bind_param('iss', $announceID, $userID, $message);
        $stmt->execute();
        $commentID = (int) $conn->insert_id;
        $stmt->close();

        if ($parentID > 0) {
            conversation_save_reply_link($conn, 'announcement_comment', $commentID, 'announcement_comment', $parentID);
        }
    } elseif ($action !== 'list') {
        comments_respond(false, 'Unknown action.', 400);
    }

    // --------------------------------------------------------- list
    $stmt = $conn->prepare(
        "SELECT commentID, senderType, senderID, message, isHidden, created_at
         FROM announcement_comments
         WHERE announceID = ?
           AND (isHidden = 0 OR (senderType = 'resident' AND senderID = ?))
         ORDER BY created_at ASC, commentID ASC"
    );
    $stmt->bind_param('is', $announceID, $userID);
    $stmt->execute();
    $rows = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    $names = conversation_user_names($conn, array_column($rows, 'senderID'));
    $parents = conversation_reply_parents(
        $conn,
        'announcement_comment',
        array_map('intval', array_column($rows, 'commentID'))
    );

    $byID = [];
    foreach ($rows as $row) {
        $byID[(int) $row['commentID']] = $row;
    }

    $comments = [];
    foreach ($rows as $row) {
        $id = (int) $row['commentID'];
        $fromBarangay = $row['senderType'] === 'barangay';
        $name = $names[(string) $row['senderID']] ?? '';

        $replyToName = null;
        $parentID = $parents[$id] ?? null;
        if ($parentID !== null && isset($byID[$parentID])) {
            $parent = $byID[$parentID];
            $replyToName = $parent['senderType'] === 'barangay'
                ? 'Barangay'
                : ($names[(string) $parent['senderID']] ?? 'Resident');
        }

        $comments[] = [
            'id' => $id,
            'fromBarangay' => $fromBarangay,
            'isMine' => !$fromBarangay && (string) $row['senderID'] === $userID,
            'name' => $fromBarangay
                ? ($name !== '' ? $name . ' · Barangay' : 'Barangay Official')
                : ($name !== '' ? $name : 'Resident'),
            'message' => (string) $row['message'],
            'hidden' => (int) $row['isHidden'] === 1,
            'replyToName' => $replyToName,
            'createdAt' => citisense_iso_time($conn, $row['created_at']),
        ];
    }

    comments_respond(true, $action === 'add' ? 'Your comment was posted.' : 'Comments loaded.', 200, [
        'data' => $comments,
    ]);
} catch (Throwable $e) {
    error_log('CitiSense announcement comments error: ' . $e->getMessage());
    comments_respond(false, 'Something went wrong. Please try again later.', 500);
}

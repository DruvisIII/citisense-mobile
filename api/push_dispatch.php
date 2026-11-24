<?php
// ============================================================
// PUSH DISPATCHER
// ------------------------------------------------------------
// Sends a push notification for every report update and every
// barangay announcement that has not been pushed yet.
//
// The admin panel saves status changes into `notification` and
// announcements into `announcements`; it does not send pushes
// itself. Calling this URL after saving (or on a schedule) sends
// them:
//
//   https://<api>/push_dispatch.php?key=<PUSH_DISPATCH_SECRET>
//
// Each item is pushed once: sent items are recorded in the
// `push_sent_log` table, which this file creates on first run.
// On that first run, everything already in the database is
// marked as sent so old items don't flood residents' phones.
// ============================================================

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/send_push_notification.php';

function dispatch_respond(int $status, array $body): never
{
    http_response_code($status);
    echo json_encode($body);
    exit;
}

$secret = trim((string) getenv('PUSH_DISPATCH_SECRET'));
$given = (string) ($_GET['key'] ?? $_POST['key'] ?? '');

if ($secret === '') {
    dispatch_respond(503, ['success' => false, 'message' => 'PUSH_DISPATCH_SECRET is not configured.']);
}
if (!hash_equals($secret, $given)) {
    dispatch_respond(403, ['success' => false, 'message' => 'Forbidden.']);
}

set_time_limit(120);
ignore_user_abort(true);

// Only push recent items, so a long outage doesn't send stale news.
const DISPATCH_MAX_AGE_HOURS = 24;
const DISPATCH_BATCH = 50;

// ------------------------------------------------------------
// Log table (created once)
// ------------------------------------------------------------
$conn->query(
    "CREATE TABLE IF NOT EXISTS push_sent_log (
        kind VARCHAR(20) NOT NULL,
        itemID VARCHAR(64) NOT NULL,
        sentAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (kind, itemID)
    )"
);

$logCount = (int) ($conn->query('SELECT COUNT(*) AS total FROM push_sent_log')->fetch_assoc()['total'] ?? 0);

if ($logCount === 0) {
    $conn->query("INSERT IGNORE INTO push_sent_log (kind, itemID) SELECT 'report', notifID FROM notification");
    $conn->query("INSERT IGNORE INTO push_sent_log (kind, itemID) SELECT 'announcement', announceID FROM announcements");
    // Marker row so the seeding never runs again, even if both tables were empty.
    $conn->query("INSERT IGNORE INTO push_sent_log (kind, itemID) VALUES ('seed', 'done')");

    dispatch_respond(200, [
        'success' => true,
        'message' => 'First run: existing items marked as already sent. New items will be pushed from now on.',
    ]);
}

/**
 * Claim an item so two dispatcher calls running at once can't both push it.
 */
function dispatch_claim(mysqli $conn, string $kind, string $itemID): bool
{
    $stmt = $conn->prepare('INSERT IGNORE INTO push_sent_log (kind, itemID) VALUES (?, ?)');
    $stmt->bind_param('ss', $kind, $itemID);
    $stmt->execute();
    $claimed = $stmt->affected_rows === 1;
    $stmt->close();

    return $claimed;
}

/**
 * Push to a list of [userID, fcmToken] rows; removes dead tokens.
 */
function dispatch_send(mysqli $conn, array $devices, string $title, string $body, array $data): int
{
    $sent = 0;

    foreach ($devices as $device) {
        $token = (string) $device['fcmToken'];
        $result = citisense_fcm_send($token, $title, $body, $data);

        if ($result === 'sent') {
            $sent++;
        } elseif ($result === 'invalid_token') {
            $delete = $conn->prepare('DELETE FROM user_device_tokens WHERE fcmToken = ?');
            $delete->bind_param('s', $token);
            $delete->execute();
            $delete->close();
        }
    }

    return $sent;
}

function dispatch_short(string $text, int $length = 150): string
{
    $text = trim(preg_replace('/\s+/', ' ', strip_tags($text)) ?? '');
    return mb_strlen($text) > $length ? mb_substr($text, 0, $length - 1) . '…' : $text;
}

$summary = ['reports' => 0, 'announcements' => 0, 'pushesSent' => 0];

// ------------------------------------------------------------
// 1. Report updates -> the report owner's phones
// ------------------------------------------------------------
$stmt = $conn->prepare(
    "SELECT n.notifID, n.userID, n.reportID, n.message
     FROM notification n
     LEFT JOIN push_sent_log p
        ON p.kind = 'report' AND p.itemID = n.notifID
     WHERE p.itemID IS NULL
       AND n.dateSent >= NOW() - INTERVAL " . DISPATCH_MAX_AGE_HOURS . " HOUR
     ORDER BY n.dateSent ASC
     LIMIT " . DISPATCH_BATCH
);
$stmt->execute();
$pendingReports = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
$stmt->close();

foreach ($pendingReports as $row) {
    $notifID = (string) $row['notifID'];
    if (!dispatch_claim($conn, 'report', $notifID)) {
        continue;
    }

    $userID = (string) $row['userID'];
    $devices = $conn->prepare('SELECT userID, fcmToken FROM user_device_tokens WHERE userID = ?');
    $devices->bind_param('s', $userID);
    $devices->execute();
    $list = $devices->get_result()->fetch_all(MYSQLI_ASSOC);
    $devices->close();

    $summary['reports']++;
    $summary['pushesSent'] += dispatch_send(
        $conn,
        $list,
        'Report Update',
        dispatch_short((string) $row['message']),
        ['type' => 'report_status', 'reportID' => (string) $row['reportID'], 'notifID' => $notifID]
    );
}

// ------------------------------------------------------------
// 2. Announcements -> every resident of that barangay
// ------------------------------------------------------------
$stmt = $conn->prepare(
    "SELECT a.announceID, a.barangayID, a.title, a.content
     FROM announcements a
     LEFT JOIN push_sent_log p
        ON p.kind = 'announcement' AND p.itemID = a.announceID
     WHERE p.itemID IS NULL
       AND a.datePosted >= NOW() - INTERVAL " . DISPATCH_MAX_AGE_HOURS . " HOUR
     ORDER BY a.datePosted ASC
     LIMIT " . DISPATCH_BATCH
);
$stmt->execute();
$pendingAnnouncements = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
$stmt->close();

foreach ($pendingAnnouncements as $row) {
    $announceID = (string) $row['announceID'];
    if (!dispatch_claim($conn, 'announcement', $announceID)) {
        continue;
    }

    $barangayID = (string) $row['barangayID'];
    $devices = $conn->prepare(
        'SELECT t.userID, t.fcmToken
         FROM user_device_tokens t
         JOIN users u ON u.userID = t.userID
         WHERE u.barangayID = ?'
    );
    $devices->bind_param('s', $barangayID);
    $devices->execute();
    $list = $devices->get_result()->fetch_all(MYSQLI_ASSOC);
    $devices->close();

    $summary['announcements']++;
    $summary['pushesSent'] += dispatch_send(
        $conn,
        $list,
        'New announcement: ' . dispatch_short((string) $row['title'], 80),
        dispatch_short((string) $row['content']),
        ['type' => 'announcement', 'announceID' => $announceID]
    );
}

dispatch_respond(200, ['success' => true] + $summary);

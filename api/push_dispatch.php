<?php
// ============================================================
// PUSH DISPATCHER
// ------------------------------------------------------------
// Sends a push notification for every report update and every
// barangay announcement that has not been pushed yet, and one when
// an administrator edits an announcement ("Announcement updated").
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
require_once __DIR__ . '/time_helpers.php';

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

set_exception_handler(function (Throwable $e): void {
    error_log('CitiSense push dispatch error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Dispatch error: ' . $e->getMessage()]);
});
ignore_user_abort(true);

// Only push recent items, so a long outage doesn't send stale news.
const DISPATCH_MAX_AGE_HOURS = 24;
const DISPATCH_BATCH = 500;

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
    $check = $conn->prepare('SELECT 1 FROM push_sent_log WHERE kind = ? AND itemID = ? LIMIT 1');
    $check->bind_param('ss', $kind, $itemID);
    $check->execute();
    $alreadySent = $check->get_result()->num_rows > 0;
    $check->close();

    if ($alreadySent) {
        return false;
    }

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

/** Phones of every resident of a barangay. */
function dispatch_barangay_devices(mysqli $conn, string $barangayID): array
{
    // Residents, then their phones (two simple lookups, so differing
    // table collations can't break a join).
    $residents = $conn->prepare('SELECT userID FROM users WHERE barangayID = ?');
    $residents->bind_param('s', $barangayID);
    $residents->execute();
    $userIDs = array_column($residents->get_result()->fetch_all(MYSQLI_ASSOC), 'userID');
    $residents->close();

    $list = [];
    $devices = $conn->prepare('SELECT userID, fcmToken FROM user_device_tokens WHERE userID = ?');
    foreach ($userIDs as $residentID) {
        $residentID = (string) $residentID;
        $devices->bind_param('s', $residentID);
        $devices->execute();
        foreach ($devices->get_result()->fetch_all(MYSQLI_ASSOC) as $device) {
            $list[] = $device;
        }
    }
    $devices->close();

    return $list;
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
// Recent rows only; whether each was already pushed is checked in PHP
// (dispatch_claim), because joining push_sent_log to tables imported
// with another text collation fails with "Illegal mix of collations".
$stmt = $conn->prepare(
    "SELECT notifID, userID, reportID, message, dateSent
     FROM notification
     WHERE dateSent >= NOW() - INTERVAL " . DISPATCH_MAX_AGE_HOURS . " HOUR
     ORDER BY dateSent ASC
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

    // Messages open the conversation in the app; status updates open the report.
    $text = (string) $row['message'];
    $lower = mb_strtolower($text);
    $reportID = (string) ($row['reportID'] ?? '');
    $isMessage = str_contains($lower, 'new reply from your barangay')
        || str_contains($lower, 'replied about your report')
        || str_contains($lower, 'new message from the barangay');

    $summary['reports']++;
    $summary['pushesSent'] += dispatch_send(
        $conn,
        $list,
        $isMessage ? 'Message from your barangay' : 'Report Update',
        dispatch_short($text),
        [
            'type' => $isMessage ? ($reportID !== '' ? 'report_message' : 'message') : 'report_status',
            'reportID' => $reportID,
            'notifID' => $notifID,
            'sentAt' => (string) citisense_iso_time($conn, $row['dateSent']),
        ]
    );
}

// ------------------------------------------------------------
// 2. Announcements -> every resident of that barangay
// ------------------------------------------------------------
$stmt = $conn->prepare(
    "SELECT announceID, barangayID, title, content, datePosted
     FROM announcements
     WHERE datePosted >= NOW() - INTERVAL " . DISPATCH_MAX_AGE_HOURS . " HOUR
     ORDER BY datePosted ASC
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

    $list = dispatch_barangay_devices($conn, (string) $row['barangayID']);

    $summary['announcements']++;
    $summary['pushesSent'] += dispatch_send(
        $conn,
        $list,
        'New announcement: ' . dispatch_short((string) $row['title'], 80),
        dispatch_short((string) $row['content']),
        [
            'type' => 'announcement',
            'announceID' => $announceID,
            'sentAt' => (string) citisense_iso_time($conn, $row['datePosted']),
        ]
    );
}

// ------------------------------------------------------------
// 3. Edited announcements -> every resident of that barangay
// ------------------------------------------------------------
// The admin website saves an edit (title, text, pictures) in one
// transaction, so only finished edits are seen here. Each
// announcement's last pushed version is kept as a fingerprint in
// announcement_push_state. A different fingerprint means it was
// edited: one "Announcement updated" push, claimed by changing the
// stored fingerprint (so two dispatcher runs cannot both send it,
// and saving without changes sends nothing).
$conn->query(
    "CREATE TABLE IF NOT EXISTS announcement_push_state (
        announceID INT(11) NOT NULL,
        fingerprint CHAR(40) NOT NULL,
        updatedAt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (announceID)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
);

$summary['announcementsUpdated'] = 0;

$all = $conn->query('SELECT announceID, barangayID, title, content FROM announcements');
$announcementRows = $all ? $all->fetch_all(MYSQLI_ASSOC) : [];

$imageStmt = null;
try {
    $imageStmt = $conn->prepare(
        'SELECT imagePath FROM announcement_images WHERE announceID = ? ORDER BY sortOrder ASC, imageID ASC'
    );
} catch (Throwable $noImages) {
    $imageStmt = null; // No pictures table yet: text changes are still detected.
}

$stateStmt = $conn->prepare('SELECT fingerprint FROM announcement_push_state WHERE announceID = ? LIMIT 1');
$insertState = $conn->prepare('INSERT IGNORE INTO announcement_push_state (announceID, fingerprint) VALUES (?, ?)');
$claimEdit = $conn->prepare(
    'UPDATE announcement_push_state SET fingerprint = ? WHERE announceID = ? AND fingerprint = ?'
);

foreach ($announcementRows as $row) {
    $announceID = (int) $row['announceID'];

    $images = [];
    if ($imageStmt) {
        $imageStmt->bind_param('i', $announceID);
        $imageStmt->execute();
        $images = array_column($imageStmt->get_result()->fetch_all(MYSQLI_ASSOC), 'imagePath');
    }
    $fingerprint = sha1((string) $row['title'] . "\0" . (string) $row['content'] . "\0" . implode("\n", $images));

    $stateStmt->bind_param('i', $announceID);
    $stateStmt->execute();
    $known = $stateStmt->get_result()->fetch_assoc();

    if (!$known) {
        // First time seen (new announcements are pushed by section 2).
        $insertState->bind_param('is', $announceID, $fingerprint);
        $insertState->execute();
        continue;
    }

    $previous = (string) $known['fingerprint'];
    if ($previous === $fingerprint) {
        continue;
    }

    $claimEdit->bind_param('sis', $fingerprint, $announceID, $previous);
    $claimEdit->execute();
    if ($claimEdit->affected_rows !== 1) {
        continue; // Another dispatcher run already sent this edit.
    }

    $list = dispatch_barangay_devices($conn, (string) $row['barangayID']);

    $summary['announcementsUpdated']++;
    $summary['pushesSent'] += dispatch_send(
        $conn,
        $list,
        'Announcement updated: ' . dispatch_short((string) $row['title'], 80),
        dispatch_short((string) $row['content']),
        [
            'type' => 'announcement_updated',
            'announceID' => (string) $announceID,
            'sentAt' => (string) citisense_server_time($conn),
        ]
    );
}

$stateStmt->close();
$insertState->close();
$claimEdit->close();
if ($imageStmt) {
    $imageStmt->close();
}

// Forget deleted announcements.
$conn->query('DELETE FROM announcement_push_state WHERE announceID NOT IN (SELECT announceID FROM announcements)');

dispatch_respond(200, ['success' => true] + $summary);

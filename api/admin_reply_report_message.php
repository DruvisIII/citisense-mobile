<?php

/*
|--------------------------------------------------------------------------
| ADMIN: REPLY TO A REPORT CONVERSATION (barangay side)
|--------------------------------------------------------------------------
| For the admin web panel (Reports > Manage > Messages with Residents).
| Uses the admin panel's login session. If a csrf_token is sent it is
| checked; otherwise the request must come from the same site (Origin /
| Referer), which blocks requests from other websites.
|
| POST: reportID, message, [csrf_token]
|
| Saves the barangay's reply, adds an in-app notification for the
| resident, and sends a push notification.
*/

session_start();
require_once __DIR__ . '/engagement_common.php';

ini_set('display_errors', '0');
error_reporting(E_ALL);
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    engagement_respond(false, 'POST required.', 405);
}

// Admin authentication.
$adminId = $_SESSION['admin_id'] ?? null;
$barangayId = $_SESSION['barangay_id'] ?? null;

if (
    !is_scalar($adminId) || trim((string)$adminId) === '' ||
    !is_scalar($barangayId) || trim((string)$barangayId) === ''
) {
    engagement_respond(false, 'Admin login required.', 401);
}

// CSRF protection.
$csrf = $_POST['csrf_token'] ?? null;

if ($csrf !== null) {
    if (
        !is_string($csrf) ||
        !isset($_SESSION['csrf_token']) ||
        !is_string($_SESSION['csrf_token']) ||
        !hash_equals($_SESSION['csrf_token'], $csrf)
    ) {
        engagement_respond(false, 'Invalid security token.', 403);
    }
} else {
    $source = (string)($_SERVER['HTTP_ORIGIN'] ?? $_SERVER['HTTP_REFERER'] ?? '');
    $sourceHost = (string)parse_url($source, PHP_URL_HOST);
    $sourcePort = parse_url($source, PHP_URL_PORT);
    $serverHost = (string)($_SERVER['HTTP_HOST'] ?? '');

    if ($sourcePort !== null && $sourcePort !== false) {
        $sourceHost .= ':' . $sourcePort;
    }

    if ($sourceHost === '' || strcasecmp($sourceHost, $serverHost) !== 0) {
        engagement_respond(false, 'Request blocked: it did not come from the admin panel.', 403);
    }
}

$adminId = trim((string)$adminId);
$barangayId = trim((string)$barangayId);
$reportID = trim((string)($_POST['reportID'] ?? ''));
$message = trim((string)($_POST['message'] ?? ''));

if ($reportID === '' || strlen($reportID) > 50) {
    engagement_respond(false, 'Invalid report.', 400);
}

if ($message === '' || mb_strlen($message) > 500) {
    engagement_respond(false, 'Message must be 1 to 500 characters.', 400);
}

require_once __DIR__ . '/config.php';
ensure_engagement_tables($conn);

// The report must belong to the admin's barangay.
$stmt = $conn->prepare(
    "SELECT reportID, userID FROM reports
     WHERE reportID = ? AND barangayID = ?
     LIMIT 1"
);
$stmt->bind_param('ss', $reportID, $barangayId);
$stmt->execute();
$report = $stmt->get_result()->fetch_assoc();
$stmt->close();

if (!$report) {
    engagement_respond(false, 'Report not found in your barangay.', 404);
}

$userId = (string)$report['userID'];

// Save reply.
$stmt = $conn->prepare(
    "INSERT INTO report_messages (reportID, senderType, senderID, message)
     VALUES (?, 'barangay', ?, ?)"
);
$stmt->bind_param('sss', $reportID, $adminId, $message);

if (!$stmt->execute()) {
    $stmt->close();
    engagement_respond(false, 'Failed to save the reply.', 500);
}
$stmt->close();

// In-app notification (same table as status updates).
$excerpt = mb_strlen($message) > 80 ? mb_substr($message, 0, 77) . '...' : $message;
$notificationMessage = 'New reply from your barangay on report ' . $reportID . ': ' . $excerpt;
$notificationId = 'NOT' . strtoupper(bin2hex(random_bytes(16)));

$stmt = $conn->prepare(
    "INSERT INTO notification (notifID, userID, reportID, message, isRead, dateSent)
     VALUES (?, ?, ?, ?, 0, CURRENT_TIMESTAMP)"
);

if ($stmt) {
    $stmt->bind_param('ssss', $notificationId, $userId, $reportID, $notificationMessage);
    $stmt->execute();
    $stmt->close();
}

// Push notification (a failure does not undo the reply).
$pushAccepted = 0;

try {
    require_once __DIR__ . '/send_push_notification.php';

    $stmt = $conn->prepare("SELECT fcmToken FROM user_device_tokens WHERE userID = ?");
    $stmt->bind_param('s', $userId);
    $stmt->execute();
    $tokens = $stmt->get_result();

    while ($row = $tokens->fetch_assoc()) {
        $token = trim((string)$row['fcmToken']);

        if ($token === '') {
            continue;
        }

        if (sendPushNotification(
            $token,
            'New reply from your barangay',
            $excerpt,
            ['type' => 'report_message', 'reportID' => $reportID]
        )) {
            $pushAccepted++;
        }
    }

    $stmt->close();
} catch (Throwable $e) {
    error_log('CitiSense reply saved, but push failed: ' . $e->getMessage());
}

engagement_respond(true, 'Reply sent.', 200, ['pushAccepted' => $pushAccepted]);

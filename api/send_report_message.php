<?php

/*
|--------------------------------------------------------------------------
| SEND REPORT MESSAGE (resident)
|--------------------------------------------------------------------------
| POST: userID, reportID, message
|
| Lets the resident reply to or comment on their barangay's updates.
*/

require_once __DIR__ . '/engagement_common.php';
engagement_headers();
require_once __DIR__ . '/config.php';

ensure_engagement_tables($conn);

$userID = trim($_POST['userID'] ?? '');
$reportID = trim($_POST['reportID'] ?? '');
$message = trim($_POST['message'] ?? '');

if ($userID === '' || $reportID === '') {
    engagement_respond(false, 'User and report are required.', 400);
}

if ($message === '') {
    engagement_respond(false, 'Please type a message.', 400);
}

if (mb_strlen($message) > 500) {
    engagement_respond(false, 'Messages must not exceed 500 characters.', 400);
}

require_own_report($conn, $userID, $reportID);

// Basic spam protection: at most 20 messages per hour per user.
$stmt = $conn->prepare(
    "SELECT COUNT(*) AS total
     FROM report_messages
     WHERE senderType = 'resident' AND senderID = ?
       AND created_at >= DATE_SUB(NOW(), INTERVAL 1 HOUR)"
);
$stmt->bind_param('s', $userID);
$stmt->execute();
$count = (int)($stmt->get_result()->fetch_assoc()['total'] ?? 0);
$stmt->close();

if ($count >= 20) {
    engagement_respond(
        false,
        'You are sending messages too quickly. Please try again later.',
        429
    );
}

$stmt = $conn->prepare(
    "INSERT INTO report_messages (reportID, senderType, senderID, message)
     VALUES (?, 'resident', ?, ?)"
);
$stmt->bind_param('sss', $reportID, $userID, $message);

if (!$stmt->execute()) {
    $stmt->close();
    engagement_respond(false, 'Failed to send your message.', 500);
}

$id = $conn->insert_id;
$stmt->close();

engagement_respond(true, 'Message sent.', 200, [
    'data' => [
        'id' => $id,
        'type' => 'resident',
        'message' => $message,
        'createdAt' => date('Y-m-d H:i:s')
    ]
]);

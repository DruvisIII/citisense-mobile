<?php

/*
|--------------------------------------------------------------------------
| GET REPORT THREAD
|--------------------------------------------------------------------------
| POST: userID, reportID
|
| Returns everything the resident sees under "Updates & Messages":
|   - status updates from the barangay (from the notification table)
|   - messages from the resident and from the barangay (report_messages)
| plus the resident's feedback for the report, if any.
*/

require_once __DIR__ . '/engagement_common.php';
engagement_headers();
require_once __DIR__ . '/config.php';

ensure_engagement_tables($conn);

$userID = trim($_POST['userID'] ?? '');
$reportID = trim($_POST['reportID'] ?? '');

if ($userID === '' || $reportID === '') {
    engagement_respond(false, 'User and report are required.', 400);
}

$report = require_own_report($conn, $userID, $reportID);

$items = [];

// Status updates sent by the barangay (reply notifications are skipped
// because the reply itself is already in report_messages).
$stmt = $conn->prepare(
    "SELECT message, dateSent
     FROM notification
     WHERE reportID = ? AND userID = ?
       AND message NOT LIKE 'New reply from your barangay%'"
);

if ($stmt) {
    $stmt->bind_param('ss', $reportID, $userID);
    $stmt->execute();
    $result = $stmt->get_result();

    while ($row = $result->fetch_assoc()) {
        $items[] = [
            'type' => 'system',
            'message' => (string)$row['message'],
            'createdAt' => (string)$row['dateSent']
        ];
    }

    $stmt->close();
}

// Conversation messages.
$stmt = $conn->prepare(
    "SELECT id, senderType, message, created_at
     FROM report_messages
     WHERE reportID = ?
     ORDER BY created_at ASC, id ASC"
);

if (!$stmt) {
    engagement_respond(false, 'Database error.', 500);
}

$stmt->bind_param('s', $reportID);
$stmt->execute();
$result = $stmt->get_result();

while ($row = $result->fetch_assoc()) {
    $items[] = [
        'id' => (int)$row['id'],
        'type' => (string)$row['senderType'],
        'message' => (string)$row['message'],
        'createdAt' => (string)$row['created_at']
    ];
}

$stmt->close();

// Oldest first.
usort($items, function ($a, $b) {
    return strtotime($a['createdAt']) <=> strtotime($b['createdAt']);
});

// Resident's feedback, if already given.
$feedback = null;

$stmt = $conn->prepare(
    "SELECT is_fixed, rating, comment, updated_at
     FROM report_feedback
     WHERE reportID = ? AND userID = ?
     LIMIT 1"
);

if ($stmt) {
    $stmt->bind_param('ss', $reportID, $userID);
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if ($row) {
        $feedback = [
            'isFixed' => (int)$row['is_fixed'] === 1,
            'rating' => (int)$row['rating'],
            'comment' => (string)($row['comment'] ?? ''),
            'updatedAt' => (string)$row['updated_at']
        ];
    }
}

engagement_respond(true, 'Thread loaded.', 200, [
    'data' => [
        'statusID' => (string)$report['statusID'],
        'items' => $items,
        'feedback' => $feedback
    ]
]);

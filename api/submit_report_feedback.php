<?php

/*
|--------------------------------------------------------------------------
| SUBMIT REPORT FEEDBACK
|--------------------------------------------------------------------------
| POST: userID, reportID, isFixed (1 or 0), rating (1-5), comment (optional)
|
| Available only after the barangay marks the report as resolved
| (STAT003). The resident can update their feedback later.
| If the resident says it is NOT fixed, a message is added to the report
| conversation so the barangay sees it.
*/

require_once __DIR__ . '/engagement_common.php';
engagement_headers();
require_once __DIR__ . '/config.php';

ensure_engagement_tables($conn);

$userID = trim($_POST['userID'] ?? '');
$reportID = trim($_POST['reportID'] ?? '');
$isFixedRaw = trim($_POST['isFixed'] ?? '');
$rating = (int)($_POST['rating'] ?? 0);
$comment = trim($_POST['comment'] ?? '');

if ($userID === '' || $reportID === '') {
    engagement_respond(false, 'User and report are required.', 400);
}

if ($isFixedRaw !== '1' && $isFixedRaw !== '0') {
    engagement_respond(false, 'Please tell us if the issue is fixed.', 400);
}

if ($rating < 1 || $rating > 5) {
    engagement_respond(false, 'Please choose a rating from 1 to 5.', 400);
}

if (mb_strlen($comment) > 300) {
    engagement_respond(false, 'Comments must not exceed 300 characters.', 400);
}

$isFixed = (int)$isFixedRaw;

$report = require_own_report($conn, $userID, $reportID);

if ((string)$report['statusID'] !== 'STAT003') {
    engagement_respond(
        false,
        'You can give feedback once your report is marked resolved.',
        400
    );
}

// Was it previously marked as fixed? (to avoid repeating the message)
$previousFixed = null;
$stmt = $conn->prepare(
    "SELECT is_fixed FROM report_feedback WHERE reportID = ? LIMIT 1"
);
$stmt->bind_param('s', $reportID);
$stmt->execute();
$row = $stmt->get_result()->fetch_assoc();
$stmt->close();

if ($row) {
    $previousFixed = (int)$row['is_fixed'];
}

$commentValue = $comment === '' ? null : $comment;

$stmt = $conn->prepare(
    "INSERT INTO report_feedback (reportID, userID, is_fixed, rating, comment)
     VALUES (?, ?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE
        is_fixed = VALUES(is_fixed),
        rating = VALUES(rating),
        comment = VALUES(comment)"
);
$stmt->bind_param('ssiis', $reportID, $userID, $isFixed, $rating, $commentValue);

if (!$stmt->execute()) {
    $stmt->close();
    engagement_respond(false, 'Failed to save your feedback.', 500);
}

$stmt->close();

// Let the barangay know in the conversation when it is not fixed.
if ($isFixed === 0 && $previousFixed !== 0) {
    $note = 'I checked and the issue is not fixed yet.';

    if ($comment !== '') {
        $note .= ' ' . $comment;
    }

    $stmt = $conn->prepare(
        "INSERT INTO report_messages (reportID, senderType, senderID, message)
         VALUES (?, 'resident', ?, ?)"
    );

    if ($stmt) {
        $stmt->bind_param('sss', $reportID, $userID, $note);
        $stmt->execute();
        $stmt->close();
    }
}

engagement_respond(true, 'Thank you for your feedback!', 200, [
    'data' => [
        'isFixed' => $isFixed === 1,
        'rating' => $rating,
        'comment' => $comment
    ]
]);

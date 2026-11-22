<?php

/*
|--------------------------------------------------------------------------
| SUBMIT APP FEEDBACK
|--------------------------------------------------------------------------
| POST: userID, type (suggestion | complaint | bug | other),
|       rating (optional, 1-5), message
|
| Suggestions or complaints about the CitiSense app itself.
*/

require_once __DIR__ . '/engagement_common.php';
engagement_headers();
require_once __DIR__ . '/config.php';

ensure_engagement_tables($conn);

$userID = trim($_POST['userID'] ?? '');
$type = strtolower(trim($_POST['type'] ?? ''));
$rating = (int)($_POST['rating'] ?? 0);
$message = trim($_POST['message'] ?? '');

$allowedTypes = ['suggestion', 'complaint', 'bug', 'other'];

if ($userID === '') {
    engagement_respond(false, 'User is required.', 400);
}

if (!in_array($type, $allowedTypes, true)) {
    engagement_respond(false, 'Please choose a feedback type.', 400);
}

if (mb_strlen($message) < 10) {
    engagement_respond(false, 'Please write at least 10 characters.', 400);
}

if (mb_strlen($message) > 1000) {
    engagement_respond(false, 'Feedback must not exceed 1000 characters.', 400);
}

$ratingValue = ($rating >= 1 && $rating <= 5) ? $rating : null;

// Make sure the user exists.
$stmt = $conn->prepare("SELECT userID FROM users WHERE userID = ? LIMIT 1");
$stmt->bind_param('s', $userID);
$stmt->execute();
$exists = $stmt->get_result()->num_rows > 0;
$stmt->close();

if (!$exists) {
    engagement_respond(false, 'User not found.', 404);
}

// At most 5 feedback submissions per hour.
$stmt = $conn->prepare(
    "SELECT COUNT(*) AS total FROM app_feedback
     WHERE userID = ? AND created_at >= DATE_SUB(NOW(), INTERVAL 1 HOUR)"
);
$stmt->bind_param('s', $userID);
$stmt->execute();
$count = (int)($stmt->get_result()->fetch_assoc()['total'] ?? 0);
$stmt->close();

if ($count >= 5) {
    engagement_respond(
        false,
        'You have sent a lot of feedback recently. Please try again later.',
        429
    );
}

$stmt = $conn->prepare(
    "INSERT INTO app_feedback (userID, feedback_type, rating, message)
     VALUES (?, ?, ?, ?)"
);
$stmt->bind_param('ssis', $userID, $type, $ratingValue, $message);

if (!$stmt->execute()) {
    $stmt->close();
    engagement_respond(false, 'Failed to send your feedback.', 500);
}

$stmt->close();

engagement_respond(true, 'Thank you! Your feedback was sent.');

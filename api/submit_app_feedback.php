<?php

/*
|--------------------------------------------------------------------------
| SUBMIT APP FEEDBACK
|--------------------------------------------------------------------------
| POST: userID, type (suggestion | complaint | bug | other),
|       rating (optional, 1-5), message
|
| Suggestions or complaints about the CitiSense app itself.
| Saved in app_feedback and emailed to the development team
| (FEEDBACK_EMAIL, default citisensedevs@gmail.com) through api/mailer.php.
| If the email cannot be sent, the saved row is removed and the app is told
| it failed, so it never shows "sent" for feedback nobody received.
*/

require_once __DIR__ . '/engagement_common.php';
engagement_headers();
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/mailer.php';

ensure_engagement_tables($conn);

$userID = trim($_POST['userID'] ?? '');
$type = strtolower(trim($_POST['type'] ?? ''));
$rating = (int)($_POST['rating'] ?? 0);
$message = trim($_POST['message'] ?? '');

$allowedTypes = ['suggestion', 'complaint', 'bug', 'other'];

if ($userID === '') {
    engagement_respond(false, 'Your session has expired. Please log in again.', 401);
}

citisense_require_user($conn, $userID);

if (!in_array($type, $allowedTypes, true)) {
    engagement_respond(false, 'Please choose a feedback type.', 400);
}

if ($message === '') {
    engagement_respond(false, 'Please write your feedback first.', 400);
}

if (mb_strlen($message) > 1000) {
    engagement_respond(false, 'Feedback must not exceed 1000 characters.', 400);
}

$ratingValue = ($rating >= 1 && $rating <= 5) ? $rating : null;

// The sender's details for the email.
$stmt = $conn->prepare(
    "SELECT userID, firstName, lastName, email, barangayID FROM users WHERE userID = ? LIMIT 1"
);
$stmt->bind_param('s', $userID);
$stmt->execute();
$user = $stmt->get_result()->fetch_assoc();
$stmt->close();

if (!$user) {
    engagement_respond(false, 'Your session has expired. Please log in again.', 401);
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
    engagement_respond(false, 'We could not send your feedback. Please try again.', 500);
}

$feedbackID = (int) $conn->insert_id;
$stmt->close();

// ------------------------------------------------------------
// Email the development team
// ------------------------------------------------------------
$barangayName = '';
$stmt = $conn->prepare('SELECT barangayName FROM barangay WHERE barangayID = ? LIMIT 1');
$userBarangay = (string) ($user['barangayID'] ?? '');
$stmt->bind_param('s', $userBarangay);
$stmt->execute();
$barangayRow = $stmt->get_result()->fetch_assoc();
$stmt->close();
if ($barangayRow) {
    $barangayName = (string) $barangayRow['barangayName'];
}

$submittedAt = new DateTimeImmutable('now', new DateTimeZone('Asia/Manila'));
$typeLabels = ['suggestion' => 'Suggestion', 'complaint' => 'Complaint', 'bug' => 'Bug / Problem', 'other' => 'Other'];
$typeLabel = $typeLabels[$type] ?? 'Other';
$fullName = trim(($user['firstName'] ?? '') . ' ' . ($user['lastName'] ?? ''));
$stars = $ratingValue !== null ? str_repeat('★', $ratingValue) . str_repeat('☆', 5 - $ratingValue) . " ({$ratingValue}/5)" : 'Not rated';

$e = static fn($text) => htmlspecialchars((string) $text, ENT_QUOTES, 'UTF-8');

$rows = [
    'Type' => $typeLabel,
    'Rating' => $stars,
    'From' => $fullName !== '' ? $fullName : 'Resident',
    'Email' => (string) ($user['email'] ?? ''),
    'User ID' => $userID,
    'Barangay' => $barangayName !== '' ? $barangayName : (string) ($user['barangayID'] ?? ''),
    'Submitted' => $submittedAt->format('F j, Y g:i A') . ' (Philippine time)',
    'Feedback ID' => '#' . $feedbackID,
];

$htmlRows = '';
$textRows = '';
foreach ($rows as $label => $value) {
    $htmlRows .= '<tr><td style="padding:6px 12px 6px 0;color:#596887;white-space:nowrap;vertical-align:top">'
        . $e($label) . '</td><td style="padding:6px 0;color:#0F2350">' . $e($value) . '</td></tr>';
    $textRows .= $label . ': ' . $value . "\n";
}

$htmlBody = '<div style="font-family:Arial,sans-serif;line-height:1.55;color:#0F2350;max-width:620px">'
    . '<h2 style="color:#2563EB;margin:0 0 12px">New CitiSense app feedback</h2>'
    . '<table style="border-collapse:collapse;font-size:14px;margin-bottom:16px">' . $htmlRows . '</table>'
    . '<div style="font-size:13px;color:#596887;margin-bottom:6px">Feedback</div>'
    . '<div style="white-space:pre-wrap;background:#F5F8FD;border:1px solid #D6DFEC;border-radius:10px;padding:14px;font-size:15px">'
    . nl2br($e($message)) . '</div>'
    . '<p style="font-size:12px;color:#8792AA;margin-top:18px">Sent automatically from the CitiSense mobile app.</p>'
    . '</div>';

$textBody = "New CitiSense app feedback\n\n" . $textRows . "\nFeedback:\n" . $message . "\n";

$recipient = trim((string) getenv('FEEDBACK_EMAIL')) ?: 'citisensedevs@gmail.com';
$subject = '[CitiSense Feedback] ' . $typeLabel . ' from ' . ($fullName !== '' ? $fullName : 'a resident');

$sent = citisense_send_mail($recipient, 'CitiSense Developers', $subject, $htmlBody, $textBody);

if (!$sent) {
    // Do not keep (or report) feedback the team never received.
    $stmt = $conn->prepare('DELETE FROM app_feedback WHERE id = ?');
    $stmt->bind_param('i', $feedbackID);
    $stmt->execute();
    $stmt->close();

    engagement_respond(
        false,
        'We could not send your feedback right now. Please try again in a few minutes.',
        502
    );
}

engagement_respond(true, 'Thank you! Your feedback was sent.');

<?php
// ============================================================
// CHANGE PASSWORD (logged-in user)
// ------------------------------------------------------------
// POST userID, currentPassword, newPassword
// The current password must be correct, so knowing a userID is
// not enough to change someone's password.
// ============================================================

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Accept');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/validation.php';
require_once __DIR__ . '/auth.php';

function change_password_respond(bool $success, string $message, int $status = 200): never
{
    http_response_code($status);
    echo json_encode(['success' => $success, 'message' => $message]);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    change_password_respond(false, 'Invalid request method.', 405);
}

$userID = trim((string) ($_POST['userID'] ?? ''));
$currentPassword = (string) ($_POST['currentPassword'] ?? '');
$newPassword = (string) ($_POST['newPassword'] ?? '');

if ($userID === '' || $currentPassword === '' || $newPassword === '') {
    change_password_respond(false, 'Please fill in all password fields.', 400);
}

$passwordError = citisense_password_error($newPassword);
if ($passwordError !== null) {
    change_password_respond(false, $passwordError, 400);
}

if (hash_equals($currentPassword, $newPassword)) {
    change_password_respond(false, 'Your new password must be different from your current password.', 400);
}

try {
    citisense_require_user($conn, $userID);

    $stmt = $conn->prepare('SELECT userID, pass FROM users WHERE userID = ? LIMIT 1');
    $stmt->bind_param('s', $userID);
    $stmt->execute();
    $user = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$user || !password_verify($currentPassword, (string) $user['pass'])) {
        usleep(400000); // slows down repeated guessing
        change_password_respond(false, 'Your current password is incorrect.', 400);
    }

    $hash = password_hash($newPassword, PASSWORD_DEFAULT);

    $stmt = $conn->prepare('UPDATE users SET pass = ? WHERE userID = ?');
    $stmt->bind_param('ss', $hash, $userID);
    $stmt->execute();
    $stmt->close();

    // Any password reset that was in progress is no longer valid.
    $stmt = $conn->prepare('DELETE FROM password_reset_otps WHERE userID = ?');
    if ($stmt) {
        $stmt->bind_param('s', $userID);
        $stmt->execute();
        $stmt->close();
    }

    // Sign out other phones; this one stays logged in.
    citisense_end_sessions($conn, $userID, citisense_request_token());

    change_password_respond(true, 'Your password has been changed.');
} catch (Throwable $e) {
    // Never log the passwords themselves.
    error_log('CitiSense change password error: ' . $e->getMessage());
    change_password_respond(false, 'We could not change your password. Please try again.', 500);
}

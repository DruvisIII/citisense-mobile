<?php
require_once __DIR__ . '/password_reset_common.php';
require_once __DIR__ . '/validation.php';
require_once __DIR__ . '/auth.php';
reset_require_post();

$resetToken = trim((string)($_POST['resetToken'] ?? ''));
$newPassword = (string)($_POST['newPassword'] ?? '');

if (!preg_match('/^[a-f0-9]{64}$/', $resetToken)) {
    reset_json(
        false,
        'Your password reset session has expired. Please request a new code.',
        [],
        400
    );
}

$passwordError = citisense_password_error($newPassword);
if ($passwordError !== null) {
    reset_json(false, $passwordError, [], 400);
}

$tokenHash = hash('sha256', $resetToken);

$conn->begin_transaction();

try {
    $stmt = $conn->prepare(
        "SELECT id, userID
         FROM password_reset_otps
         WHERE reset_token_hash = ?
         AND purpose = 'password_reset'
         AND verified_at IS NOT NULL
         AND expires_at > NOW()
         LIMIT 1
         FOR UPDATE"
    );

    $stmt->bind_param('s', $tokenHash);
    $stmt->execute();
    $record = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$record) {
        $conn->rollback();

        reset_json(
            false,
            'Your password reset session has expired. Please request a new code.',
            [],
            400
        );
    }

    $userID = (string)$record['userID'];

    $passwordHash = password_hash($newPassword, PASSWORD_DEFAULT);

    $stmt = $conn->prepare(
        'UPDATE users SET pass = ? WHERE userID = ?'
    );

    $stmt->bind_param('ss', $passwordHash, $userID);

    if (!$stmt->execute() || $stmt->affected_rows !== 1) {
        throw new RuntimeException('Password update failed.');
    }

    $stmt->close();

    // Remove all reset records for this user.
    // This also makes the reset token unusable again.
    $stmt = $conn->prepare(
        'DELETE FROM password_reset_otps WHERE userID = ?'
    );

    $stmt->bind_param('s', $userID);
    $stmt->execute();
    $stmt->close();

    $conn->commit();

    // A recovered password signs out every phone that was logged in.
    try {
        citisense_end_sessions($conn, $userID);
    } catch (Throwable $sessionError) {
        error_log('CitiSense reset: could not end sessions: ' . $sessionError->getMessage());
    }

    reset_json(
        true,
        'Your password has been changed successfully. You can now log in.'
    );

} catch (Throwable $e) {
    $conn->rollback();

    error_log('CitiSense password reset error: ' . $e->getMessage());

    reset_json(
        false,
        'Unable to update your password. Please try again.',
        [],
        500
    );
}

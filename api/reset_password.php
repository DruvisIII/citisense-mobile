
<?php
require_once __DIR__ . '/password_reset_common.php';
reset_require_post();

$resetToken = trim((string)($_POST['resetToken'] ?? ''));
$newPassword = (string)($_POST['newPassword'] ?? '');

if (
    !preg_match('/^[a-f0-9]{64}$/', $resetToken) ||
    strlen($newPassword) < 8 ||
    strlen($newPassword) > 72
) {
    reset_json(
        false,
        'Please provide a valid reset session and a password between 8 and 72 characters.',
        [],
        400
    );
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

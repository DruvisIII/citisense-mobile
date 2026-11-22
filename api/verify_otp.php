
<?php
require_once __DIR__ . '/password_reset_common.php';
reset_require_post();

$email = strtolower(trim((string)($_POST['email'] ?? '')));
$method = 'email';
$otp = trim((string)($_POST['otp'] ?? ''));

if (
    !filter_var($email, FILTER_VALIDATE_EMAIL) ||
    !preg_match('/^\d{6}$/', $otp)
) {
    reset_json(false, 'Invalid or expired verification code.', [], 400);
}

$stmt = $conn->prepare(
    'SELECT userID FROM users WHERE email = ? LIMIT 1'
);
$stmt->bind_param('s', $email);
$stmt->execute();
$user = $stmt->get_result()->fetch_assoc();
$stmt->close();

if (!$user) {
    reset_json(false, 'Invalid or expired verification code.', [], 400);
}

$userID = (string)$user['userID'];

$conn->begin_transaction();

try {
    $stmt = $conn->prepare(
        "SELECT id, otp_hash, attempts
         FROM password_reset_otps
         WHERE userID = ?
         AND purpose = 'password_reset'
         AND method = ?
         AND verified_at IS NULL
         AND expires_at > NOW()
         ORDER BY id DESC
         LIMIT 1
         FOR UPDATE"
    );

    $stmt->bind_param('ss', $userID, $method);
    $stmt->execute();
    $record = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$record || (int)$record['attempts'] >= 5) {
        $conn->rollback();
        reset_json(false, 'Invalid or expired verification code.', [], 400);
    }

    $otpID = (int)$record['id'];

    if (!password_verify($otp, (string)$record['otp_hash'])) {
        $stmt = $conn->prepare(
            'UPDATE password_reset_otps SET attempts = attempts + 1 WHERE id = ?'
        );
        $stmt->bind_param('i', $otpID);
        $stmt->execute();
        $stmt->close();

        $conn->commit();

        reset_json(false, 'Invalid or expired verification code.', [], 400);
    }

    $resetToken = bin2hex(random_bytes(32));
    $resetTokenHash = hash('sha256', $resetToken);

    $stmt = $conn->prepare(
        'UPDATE password_reset_otps
         SET verified_at = NOW(), reset_token_hash = ?
         WHERE id = ?'
    );

    $stmt->bind_param('si', $resetTokenHash, $otpID);

    if (!$stmt->execute()) {
        throw new RuntimeException('Unable to save reset token.');
    }

    $stmt->close();
    $conn->commit();

    reset_json(
        true,
        'Verification successful. You may now set a new password.',
        ['resetToken' => $resetToken]
    );

} catch (Throwable $e) {
    $conn->rollback();
    error_log('CitiSense OTP verification error: ' . $e->getMessage());

    reset_json(false, 'Unable to verify your code. Please try again.', [], 500);
}


<?php
require_once __DIR__ . '/password_reset_common.php';
reset_require_post();

$email = strtolower(trim((string)($_POST['email'] ?? '')));
$method = 'email';

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    reset_json(false, 'Please provide a valid email address.', [], 400);
}

$stmt = $conn->prepare(
    'SELECT userID, firstName, email FROM users WHERE email = ? LIMIT 1'
);
$stmt->bind_param('s', $email);
$stmt->execute();
$user = $stmt->get_result()->fetch_assoc();
$stmt->close();

if (!$user) {
    reset_json(true, 'If the account exists, a verification code will be sent to its registered email.');
}

$userID = (string)$user['userID'];

$active = reset_find_active_otp($conn, $userID, $method);

if ($active) {
    $created = strtotime((string)$active['created_at']);

    if ($created !== false && (time() - $created) < 60) {
        reset_json(false, 'Please wait before requesting another code.', [
            'retryAfter' => 60 - (time() - $created)
        ], 429);
    }
}

$stmt = $conn->prepare(
    "SELECT COUNT(*) AS total
     FROM password_reset_otps
     WHERE userID = ? AND method = ?
     AND created_at >= (NOW() - INTERVAL 1 HOUR)"
);
$stmt->bind_param('ss', $userID, $method);
$stmt->execute();
$count = (int)($stmt->get_result()->fetch_assoc()['total'] ?? 0);
$stmt->close();

if ($count >= 5) {
    reset_json(false, 'Too many code requests. Please try again later.', [], 429);
}

$otp = (string)random_int(100000, 999999);
$otpHash = password_hash($otp, PASSWORD_DEFAULT);

$stmt = $conn->prepare(
    "UPDATE password_reset_otps
     SET expires_at = NOW()
     WHERE userID = ? AND method = ?
     AND verified_at IS NULL AND expires_at > NOW()"
);
$stmt->bind_param('ss', $userID, $method);
$stmt->execute();
$stmt->close();

$purpose = 'password_reset';
$destination = (string)$user['email'];

$stmt = $conn->prepare(
    "INSERT INTO password_reset_otps
     (userID, purpose, method, destination, otp_hash, expires_at)
     VALUES (?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL 5 MINUTE))"
);
$stmt->bind_param(
    'sssss',
    $userID,
    $purpose,
    $method,
    $destination,
    $otpHash
);

if (!$stmt->execute()) {
    $stmt->close();
    reset_json(false, 'Unable to start password recovery right now.', [], 500);
}

$otpID = (int)$stmt->insert_id;
$stmt->close();

$sent = reset_send_email(
    (string)$user['email'],
    (string)$user['firstName'],
    $otp,
    $resetSecrets
);

if (!$sent) {
    $stmt = $conn->prepare(
        'DELETE FROM password_reset_otps WHERE id = ?'
    );
    $stmt->bind_param('i', $otpID);
    $stmt->execute();
    $stmt->close();

    reset_json(false, 'We could not send the verification code. Please try again.', [], 502);
}

reset_json(true, 'A verification code has been sent to your registered email.');

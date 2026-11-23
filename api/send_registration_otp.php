<?php


error_reporting(E_ALL);
ini_set('display_errors', '0');

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Accept');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/config.php';

function registration_otp_response(
    bool $success,
    string $message,
    int $status = 200
): void {
    http_response_code($status);
    echo json_encode([
        'success' => $success,
        'message' => $message
    ]);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    registration_otp_response(false, 'Invalid request method.', 405);
}

// Get submitted information.
$email = strtolower(trim($_POST['email'] ?? ''));
$firstName = trim($_POST['firstName'] ?? '');

if ($email === '' || $firstName === '') {
    registration_otp_response(false, 'Email and first name are required.', 400);
}

// Validate email format.
if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    registration_otp_response(false, 'Please enter a valid email address.', 400);
}

// Check if email is already registered.
$check = $conn->prepare(
    "SELECT userID FROM users WHERE email = ? LIMIT 1"
);

if (!$check) {
    registration_otp_response(false, 'Database error.', 500);
}

$check->bind_param('s', $email);
$check->execute();

$result = $check->get_result();
$emailExists = $result->num_rows > 0;

$check->close();

if ($emailExists) {
    registration_otp_response(
        false,
        'This email address is already registered.'
    );
}

// Check resend cooldown: 60 seconds.
$cooldown = $conn->prepare(
    "SELECT id FROM registration_email_otps
     WHERE email = ?
     AND created_at >= DATE_SUB(NOW(), INTERVAL 60 SECOND)
     ORDER BY id DESC
     LIMIT 1"
);

if (!$cooldown) {
    registration_otp_response(false, 'Database error.', 500);
}

$cooldown->bind_param('s', $email);
$cooldown->execute();

$cooldownResult = $cooldown->get_result();
$recentRequest = $cooldownResult->num_rows > 0;

$cooldown->close();

if ($recentRequest) {
    registration_otp_response(
        false,
        'Please wait 60 seconds before requesting another code.',
        429
    );
}

// Limit requests to five per hour.
$limit = $conn->prepare(
    "SELECT COUNT(*) AS total
     FROM registration_email_otps
     WHERE email = ?
     AND created_at >= DATE_SUB(NOW(), INTERVAL 1 HOUR)"
);

if (!$limit) {
    registration_otp_response(false, 'Database error.', 500);
}

$limit->bind_param('s', $email);
$limit->execute();

$limitResult = $limit->get_result();
$limitRow = $limitResult->fetch_assoc();

$limit->close();

if ((int)($limitRow['total'] ?? 0) >= 5) {
    registration_otp_response(
        false,
        'You have reached the OTP request limit. Please try again later.',
        429
    );
}

// Generate a six-digit OTP.
$otp = (string) random_int(100000, 999999);

// Hash the OTP before saving it.
$otpHash = password_hash($otp, PASSWORD_DEFAULT);

// Store OTP with a five-minute expiration.
$insert = $conn->prepare(
    "INSERT INTO registration_email_otps
     (email, firstName, otp_hash, expires_at)
     VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL 5 MINUTE))"
);

if (!$insert) {
    registration_otp_response(false, 'Database error.', 500);
}

$insert->bind_param('sss', $email, $firstName, $otpHash);

if (!$insert->execute()) {
    $insert->close();
    registration_otp_response(false, 'Failed to create verification code.', 500);
}

$otpId = $conn->insert_id;
$insert->close();

// Send verification email.
require_once __DIR__ . '/mailer.php';
$secrets = citisense_load_secrets();

function delete_registration_otp(mysqli $conn, int $otpId): void
{
    $delete = $conn->prepare(
        "DELETE FROM registration_email_otps WHERE id = ?"
    );

    if ($delete) {
        $delete->bind_param('i', $otpId);
        $delete->execute();
        $delete->close();
    }
}

if (!citisense_mail_configured($secrets)) {
    error_log('CitiSense registration: no email provider configured.');
    delete_registration_otp($conn, (int)$otpId);

    registration_otp_response(
        false,
        'Email service is not configured.',
        500
    );
}

$safeName = htmlspecialchars(
    $firstName,
    ENT_QUOTES,
    'UTF-8'
);

$htmlBody =
    '<div style="font-family:Arial,sans-serif;line-height:1.6;color:#24324a">'
    . '<h2>Welcome to CitiSense!</h2>'
    . '<p>Hello ' . $safeName . ',</p>'
    . '<p>Use the verification code below to verify your email address:</p>'
    . '<p style="font-size:30px;font-weight:bold;letter-spacing:7px">'
    . $otp
    . '</p>'
    . '<p>This code expires in 5 minutes.</p>'
    . '<p>If you did not request a CitiSense account, you can ignore this email.</p>'
    . '<p>For your security, do not share this code with anyone.</p>'
    . '</div>';

$textBody =
    "Your CitiSense email verification code is {$otp}. "
    . "It expires in 5 minutes. Do not share this code.";

$sent = citisense_send_mail(
    $email,
    $firstName,
    'Verify your CitiSense account',
    $htmlBody,
    $textBody,
    $secrets
);

if (!$sent) {
    // Remove the OTP record if sending failed.
    delete_registration_otp($conn, (int)$otpId);

    registration_otp_response(
        false,
        'Unable to send verification email. Please try again later.',
        500
    );
}

registration_otp_response(
    true,
    'Verification code sent successfully.'
);

?>



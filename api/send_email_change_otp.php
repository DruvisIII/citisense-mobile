<?php

/*
|--------------------------------------------------------------------------
| SEND EMAIL CHANGE OTP
|--------------------------------------------------------------------------
| Called from Settings > Personal Details when the user changes their email.
|
| POST: userID, firstName, newEmail
|
| 1. Rejects the new email if another account already uses it
|    (response includes "code": "EMAIL_TAKEN").
| 2. Sends a six-digit code to the new email to prove it exists and
|    belongs to the user. The code expires in 5 minutes.
|
| Uses the same Gmail SMTP setup, cooldown, and request limit as
| send_registration_otp.php.
*/

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

function email_change_response(
    bool $success,
    string $message,
    int $status = 200,
    string $code = ''
): void {
    http_response_code($status);

    $response = [
        'success' => $success,
        'message' => $message
    ];

    if ($code !== '') {
        $response['code'] = $code;
    }

    echo json_encode($response);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    email_change_response(false, 'Invalid request method.', 405);
}

// Create the OTP table the first time this endpoint is used.
$createTable = $conn->query(
    "CREATE TABLE IF NOT EXISTS email_change_otps (
        id INT AUTO_INCREMENT PRIMARY KEY,
        userID VARCHAR(50) NOT NULL,
        new_email VARCHAR(255) NOT NULL,
        otp_hash VARCHAR(255) NOT NULL,
        attempts INT NOT NULL DEFAULT 0,
        expires_at DATETIME NOT NULL,
        used_at DATETIME NULL DEFAULT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_email_change_user (userID),
        INDEX idx_email_change_email (new_email)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
);

if (!$createTable) {
    error_log('CitiSense email change: could not create table: ' . $conn->error);
    email_change_response(false, 'Database error.', 500);
}

// Get submitted information.
$userID = trim($_POST['userID'] ?? '');
$firstName = trim($_POST['firstName'] ?? '');
$newEmail = strtolower(trim($_POST['newEmail'] ?? ''));

if ($userID === '' || $newEmail === '') {
    email_change_response(false, 'User and new email are required.', 400);
}

// Validate email format.
if (!filter_var($newEmail, FILTER_VALIDATE_EMAIL)) {
    email_change_response(false, 'Please enter a valid email address.', 400);
}

// Make sure the user exists and get their current email.
$userStmt = $conn->prepare(
    "SELECT email, firstName FROM users WHERE userID = ? LIMIT 1"
);

if (!$userStmt) {
    email_change_response(false, 'Database error.', 500);
}

$userStmt->bind_param('s', $userID);
$userStmt->execute();
$user = $userStmt->get_result()->fetch_assoc();
$userStmt->close();

if (!$user) {
    email_change_response(false, 'User not found.', 404);
}

if ($firstName === '') {
    $firstName = (string)($user['firstName'] ?? '');
}

if (strtolower(trim((string)$user['email'])) === $newEmail) {
    email_change_response(false, 'This is already your current email address.', 400);
}

// Check if another account already uses this email.
$check = $conn->prepare(
    "SELECT userID FROM users
     WHERE LOWER(email) = ? AND userID <> ?
     LIMIT 1"
);

if (!$check) {
    email_change_response(false, 'Database error.', 500);
}

$check->bind_param('ss', $newEmail, $userID);
$check->execute();
$emailTaken = $check->get_result()->num_rows > 0;
$check->close();

if ($emailTaken) {
    email_change_response(
        false,
        'This email address is already used by another account. '
        . 'Please use a different email.',
        409,
        'EMAIL_TAKEN'
    );
}

// Check resend cooldown: 60 seconds.
$cooldown = $conn->prepare(
    "SELECT id FROM email_change_otps
     WHERE userID = ?
     AND created_at >= DATE_SUB(NOW(), INTERVAL 60 SECOND)
     ORDER BY id DESC
     LIMIT 1"
);

if (!$cooldown) {
    email_change_response(false, 'Database error.', 500);
}

$cooldown->bind_param('s', $userID);
$cooldown->execute();
$recentRequest = $cooldown->get_result()->num_rows > 0;
$cooldown->close();

if ($recentRequest) {
    email_change_response(
        false,
        'Please wait 60 seconds before requesting another code.',
        429
    );
}

// Limit requests to five per hour.
$limit = $conn->prepare(
    "SELECT COUNT(*) AS total
     FROM email_change_otps
     WHERE userID = ?
     AND created_at >= DATE_SUB(NOW(), INTERVAL 1 HOUR)"
);

if (!$limit) {
    email_change_response(false, 'Database error.', 500);
}

$limit->bind_param('s', $userID);
$limit->execute();
$limitRow = $limit->get_result()->fetch_assoc();
$limit->close();

if ((int)($limitRow['total'] ?? 0) >= 5) {
    email_change_response(
        false,
        'You have reached the code request limit. Please try again later.',
        429
    );
}

// Cancel any older unused codes for this user.
$cancel = $conn->prepare(
    "UPDATE email_change_otps
     SET used_at = NOW()
     WHERE userID = ? AND used_at IS NULL"
);

if ($cancel) {
    $cancel->bind_param('s', $userID);
    $cancel->execute();
    $cancel->close();
}

// Generate a six-digit OTP and store only its hash.
$otp = (string) random_int(100000, 999999);
$otpHash = password_hash($otp, PASSWORD_DEFAULT);

$insert = $conn->prepare(
    "INSERT INTO email_change_otps
     (userID, new_email, otp_hash, expires_at)
     VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL 5 MINUTE))"
);

if (!$insert) {
    email_change_response(false, 'Database error.', 500);
}

$insert->bind_param('sss', $userID, $newEmail, $otpHash);

if (!$insert->execute()) {
    $insert->close();
    email_change_response(false, 'Failed to create verification code.', 500);
}

$otpId = $conn->insert_id;
$insert->close();

function delete_email_change_otp(mysqli $conn, int $otpId): void
{
    $delete = $conn->prepare("DELETE FROM email_change_otps WHERE id = ?");

    if ($delete) {
        $delete->bind_param('i', $otpId);
        $delete->execute();
        $delete->close();
    }
}

// Load Gmail credentials from the shared configuration.
require_once __DIR__ . '/email_secrets.php';
$secrets = citisense_load_secrets();

if (
    empty($secrets['gmail_address']) ||
    empty($secrets['gmail_app_password'])
) {
    delete_email_change_otp($conn, $otpId);
    email_change_response(false, 'Email service is not configured.', 500);
}

$autoload = __DIR__ . '/vendor/autoload.php';

if (!file_exists($autoload)) {
    error_log('CitiSense email change: PHPMailer autoload file not found.');
    delete_email_change_otp($conn, $otpId);
    email_change_response(false, 'Email service is unavailable.', 500);
}

require_once $autoload;

// Send the verification email to the NEW address.
try {
    $mail = new PHPMailer\PHPMailer\PHPMailer(true);

    $mail->isSMTP();
    $mail->Host = 'smtp.gmail.com';
    $mail->SMTPAuth = true;
    $mail->Username = (string)($secrets['gmail_address'] ?? '');
    $mail->Password = (string)($secrets['gmail_app_password'] ?? '');
    $mail->SMTPSecure =
        PHPMailer\PHPMailer\PHPMailer::ENCRYPTION_STARTTLS;
    $mail->Port = 587;
    $mail->CharSet = 'UTF-8';

    $mail->setFrom($mail->Username, 'CitiSense');
    $mail->addAddress($newEmail, $firstName);

    $mail->isHTML(true);
    $mail->Subject = 'Verify your new CitiSense email';

    $safeName = htmlspecialchars($firstName, ENT_QUOTES, 'UTF-8');

    $mail->Body =
        '<div style="font-family:Arial,sans-serif;line-height:1.6;color:#24324a">'
        . '<h2>Confirm your new email</h2>'
        . '<p>Hello ' . $safeName . ',</p>'
        . '<p>You asked to change the email on your CitiSense account to this address. '
        . 'Use the code below to confirm it:</p>'
        . '<p style="font-size:30px;font-weight:bold;letter-spacing:7px">'
        . $otp
        . '</p>'
        . '<p>This code expires in 5 minutes.</p>'
        . '<p>If you did not request this change, you can ignore this email. '
        . 'Your account email will stay the same.</p>'
        . '<p>For your security, do not share this code with anyone.</p>'
        . '</div>';

    $mail->AltBody =
        "Your CitiSense email change code is {$otp}. "
        . "It expires in 5 minutes. Do not share this code.";

    $mail->send();

} catch (Throwable $e) {
    error_log('CitiSense email change email error: ' . $e->getMessage());

    delete_email_change_otp($conn, $otpId);

    email_change_response(
        false,
        'Unable to send the verification email. Please check the address and try again.',
        500
    );
}

email_change_response(true, 'Verification code sent to your new email.');

?>



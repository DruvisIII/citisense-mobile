<?php
// Shared helpers for CitiSense password recovery endpoints.

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

require_once __DIR__ . '/config.php';

$secretsFile = __DIR__ . '/password_reset_secrets.php';
if (!file_exists($secretsFile)) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Password recovery is not configured on the server.']);
    exit;
}
$resetSecrets = require $secretsFile;

function reset_json(bool $success, string $message, array $extra = [], int $status = 200): void
{
    http_response_code($status);
    echo json_encode(array_merge(['success' => $success, 'message' => $message], $extra));
    exit;
}

function reset_require_post(): void
{
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
        reset_json(false, 'Invalid request method.', [], 405);
    }
}

function reset_send_email(string $to, string $firstName, string $otp, array $secrets): bool
{
    $autoload = __DIR__ . '/vendor/autoload.php';
    if (!file_exists($autoload)) {
        error_log('CitiSense password reset: PHPMailer vendor/autoload.php not found.');
        return false;
    }

    require_once $autoload;

    try {
        $mail = new PHPMailer\PHPMailer\PHPMailer(true);
        $mail->isSMTP();
        $mail->Host = 'smtp.gmail.com';
        $mail->SMTPAuth = true;
        $mail->Username = (string)($secrets['gmail_address'] ?? '');
        $mail->Password = (string)($secrets['gmail_app_password'] ?? '');
        $mail->SMTPSecure = PHPMailer\PHPMailer\PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port = 587;
        $mail->CharSet = 'UTF-8';
        $mail->setFrom($mail->Username, 'CitiSense');
        $mail->addAddress($to, $firstName);
        $mail->isHTML(true);
        $mail->Subject = 'Your CitiSense password reset code';
        $safeName = htmlspecialchars($firstName, ENT_QUOTES, 'UTF-8');
        $mail->Body = '<div style="font-family:Arial,sans-serif;line-height:1.6;color:#24324a">'
            . '<h2>CitiSense password reset</h2>'
            . '<p>Hello ' . $safeName . ',</p>'
            . '<p>Use this verification code to reset your CitiSense password:</p>'
            . '<p style="font-size:30px;font-weight:bold;letter-spacing:7px">' . $otp . '</p>'
            . '<p>This code expires in 5 minutes. If you did not request a password reset, you can ignore this email.</p>'
            . '<p>For your security, do not share this code with anyone.</p></div>';
        $mail->AltBody = "Your CitiSense password reset code is {$otp}. It expires in 5 minutes. Do not share this code.";
        $mail->send();
        return true;
    } catch (Throwable $e) {
        error_log('CitiSense password reset email error: ' . $e->getMessage());
        return false;
    }
}

function reset_normalize_ph_mobile(string $raw): ?string
{
    $digits = preg_replace('/\D+/', '', $raw);
    if (strlen($digits) === 11 && str_starts_with($digits, '09')) {
        return '63' . substr($digits, 1);
    }
    if (strlen($digits) === 12 && str_starts_with($digits, '639')) {
        return $digits;
    }
    if (strlen($digits) === 13 && str_starts_with($digits, '639')) {
        return $digits;
    }
    return null;
}

function reset_send_sms(string $number, string $otp, array $secrets): bool
{
    if (!function_exists('curl_init')) {
        error_log('CitiSense password reset: PHP cURL extension is not enabled.');
        return false;
    }

    $apiKey = trim((string)($secrets['semaphore_api_key'] ?? ''));
    if ($apiKey === '') {
        error_log('CitiSense password reset: Semaphore API key is missing.');
        return false;
    }

    $message = "Your CitiSense password reset code is {otp}. It expires in 5 minutes. Do not share this code.";
    $payload = [
        'apikey' => $apiKey,
        'number' => $number,
        'message' => $message,
        'code' => $otp,
    ];
    $senderName = trim((string)($secrets['semaphore_sendername'] ?? ''));
    if ($senderName !== '') {
        $payload['sendername'] = $senderName;
    }

    $ch = curl_init('https://api.semaphore.co/api/v4/otp');
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => http_build_query($payload),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_TIMEOUT => 25,
    ]);
    $response = curl_exec($ch);
    $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlError = curl_error($ch);
    curl_close($ch);

    if ($response === false || $httpCode < 200 || $httpCode >= 300) {
        error_log('CitiSense Semaphore error. HTTP ' . $httpCode . '; ' . $curlError . '; response: ' . (string)$response);
        return false;
    }

    $decoded = json_decode((string)$response, true);
    if (!is_array($decoded) || !isset($decoded[0]) || !is_array($decoded[0])) {
        error_log('CitiSense Semaphore unexpected response: ' . (string)$response);
        return false;
    }

    $providerStatus = strtolower((string)($decoded[0]['status'] ?? ''));
    if ($providerStatus === 'failed' || $providerStatus === 'refunded') {
        error_log('CitiSense Semaphore rejected SMS: ' . (string)$response);
        return false;
    }
    return true; // queued/pending means Semaphore accepted the message
}

function reset_find_active_otp(mysqli $conn, string $userID, string $method): ?array {
    $stmt = $conn->prepare(
        "SELECT id, created_at FROM password_reset_otps
         WHERE userID = ? AND method = ?
         AND purpose = 'password_reset'
         AND expires_at > NOW()
         ORDER BY id DESC LIMIT 1"
    );

    $stmt->bind_param('ss', $userID, $method);
    $stmt->execute();

    $result = $stmt->get_result();
    $row = $result->fetch_assoc() ?: null;

    $stmt->close();

    return $row;
}




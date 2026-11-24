<?php
// ============================================================
// SHARED EMAIL SENDER
// ------------------------------------------------------------
// Railway blocks outbound SMTP (Gmail on port 587) on the Free,
// Trial and Hobby plans, so the OTP emails never leave the server.
// This helper sends through an HTTPS email API when one is
// configured, and falls back to Gmail SMTP (fine on XAMPP or on
// Railway Pro).
//
// Order of preference (first one configured wins):
//   0. GMAIL_SCRIPT_URL + GMAIL_SCRIPT_SECRET -> free Google Apps
//                          Script that sends from your own Gmail
//                          (see README "Free Gmail sending")
//   1. BREVO_API_KEY   -> https://api.brevo.com  (free, 300/day,
//                          sender can be a verified Gmail address)
//   2. RESEND_API_KEY  -> https://api.resend.com (needs a verified
//                          domain to email anyone but yourself)
//   3. GMAIL_ADDRESS + GMAIL_APP_PASSWORD -> SMTP via PHPMailer
//
// Sender address: MAIL_FROM_EMAIL, otherwise GMAIL_ADDRESS.
// Sender name:    MAIL_FROM_NAME, otherwise "CitiSense".
// ============================================================

require_once __DIR__ . '/email_secrets.php';

/**
 * True when at least one way of sending email is configured.
 */
function citisense_mail_configured(?array $secrets = null): bool
{
    $secrets = $secrets ?? citisense_load_secrets();

    if (!empty($secrets['gmail_script_url']) && !empty($secrets['gmail_script_secret'])) {
        return true;
    }

    $hasSender = !empty($secrets['mail_from_email']) || !empty($secrets['gmail_address']);

    if (!empty($secrets['brevo_api_key']) || !empty($secrets['resend_api_key'])) {
        return $hasSender;
    }

    return !empty($secrets['gmail_address']) && !empty($secrets['gmail_app_password']);
}

/**
 * Send one email. Returns true when the provider accepted it.
 * Failures are written to the PHP error log (visible in Railway logs).
 */
function citisense_send_mail(
    string $toEmail,
    string $toName,
    string $subject,
    string $htmlBody,
    string $textBody,
    ?array $secrets = null
): bool {
    $secrets = $secrets ?? citisense_load_secrets();

    if (!empty($secrets['gmail_script_url']) && !empty($secrets['gmail_script_secret'])) {
        return citisense_send_via_gmail_script(
            (string)$secrets['gmail_script_url'],
            (string)$secrets['gmail_script_secret'],
            (string)($secrets['mail_from_name'] ?? 'CitiSense'),
            $toEmail, $toName, $subject, $htmlBody, $textBody
        );
    }

    $fromEmail = (string)($secrets['mail_from_email'] ?? $secrets['gmail_address'] ?? '');
    $fromName = (string)($secrets['mail_from_name'] ?? 'CitiSense');

    if ($fromEmail === '') {
        error_log('CitiSense mailer: no sender address. Set MAIL_FROM_EMAIL or GMAIL_ADDRESS.');
        return false;
    }

    if (!empty($secrets['brevo_api_key'])) {
        return citisense_send_via_brevo(
            (string)$secrets['brevo_api_key'],
            $fromEmail, $fromName, $toEmail, $toName, $subject, $htmlBody, $textBody
        );
    }

    if (!empty($secrets['resend_api_key'])) {
        return citisense_send_via_resend(
            (string)$secrets['resend_api_key'],
            $fromEmail, $fromName, $toEmail, $toName, $subject, $htmlBody, $textBody
        );
    }

    return citisense_send_via_smtp(
        $secrets, $fromEmail, $fromName, $toEmail, $toName, $subject, $htmlBody, $textBody
    );
}

/**
 * POST a JSON body and return [httpStatus, responseBody|false, curlError].
 */
function citisense_mail_post_json(string $url, array $headers, array $payload): array
{
    if (!function_exists('curl_init')) {
        return [0, false, 'PHP cURL extension is not enabled.'];
    }

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => json_encode($payload),
        CURLOPT_HTTPHEADER => array_merge(
            ['Content-Type: application/json', 'Accept: application/json'],
            $headers
        ),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_TIMEOUT => 25,
    ]);

    $body = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $error = curl_error($ch);
    curl_close($ch);

    return [$status, $body, $error];
}

function citisense_send_via_gmail_script(
    string $scriptUrl,
    string $secret,
    string $fromName,
    string $toEmail,
    string $toName,
    string $subject,
    string $htmlBody,
    string $textBody
): bool {
    if (!function_exists('curl_init')) {
        error_log('CitiSense mailer (Gmail script): PHP cURL extension is not enabled.');
        return false;
    }

    $ch = curl_init($scriptUrl);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => json_encode([
            'secret' => $secret,
            'to' => $toEmail,
            'name' => $fromName,
            'subject' => $subject,
            'html' => $htmlBody,
            'text' => $textBody,
        ]),
        CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
        CURLOPT_RETURNTRANSFER => true,
        // Apps Script answers with a redirect to the script's output.
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_MAXREDIRS => 5,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_TIMEOUT => 30,
    ]);

    $body = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $error = curl_error($ch);
    curl_close($ch);

    $decoded = is_string($body) ? json_decode($body, true) : null;

    if ($body === false || $status < 200 || $status >= 300 || !is_array($decoded) || ($decoded['success'] ?? false) !== true) {
        error_log("CitiSense mailer (Gmail script) failed. HTTP {$status}; {$error}; response: " . substr((string)$body, 0, 500));
        return false;
    }

    return true;
}

function citisense_send_via_brevo(
    string $apiKey,
    string $fromEmail,
    string $fromName,
    string $toEmail,
    string $toName,
    string $subject,
    string $htmlBody,
    string $textBody
): bool {
    [$status, $body, $error] = citisense_mail_post_json(
        'https://api.brevo.com/v3/smtp/email',
        ['api-key: ' . $apiKey],
        [
            'sender' => ['email' => $fromEmail, 'name' => $fromName],
            'to' => [['email' => $toEmail, 'name' => $toName !== '' ? $toName : $toEmail]],
            'subject' => $subject,
            'htmlContent' => $htmlBody,
            'textContent' => $textBody,
        ]
    );

    if ($body === false || $status < 200 || $status >= 300) {
        error_log("CitiSense mailer (Brevo) failed. HTTP {$status}; {$error}; response: " . (string)$body);
        return false;
    }

    return true;
}

function citisense_send_via_resend(
    string $apiKey,
    string $fromEmail,
    string $fromName,
    string $toEmail,
    string $toName,
    string $subject,
    string $htmlBody,
    string $textBody
): bool {
    [$status, $body, $error] = citisense_mail_post_json(
        'https://api.resend.com/emails',
        ['Authorization: Bearer ' . $apiKey],
        [
            'from' => $fromName . ' <' . $fromEmail . '>',
            'to' => [$toEmail],
            'subject' => $subject,
            'html' => $htmlBody,
            'text' => $textBody,
        ]
    );

    if ($body === false || $status < 200 || $status >= 300) {
        error_log("CitiSense mailer (Resend) failed. HTTP {$status}; {$error}; response: " . (string)$body);
        return false;
    }

    return true;
}

function citisense_send_via_smtp(
    array $secrets,
    string $fromEmail,
    string $fromName,
    string $toEmail,
    string $toName,
    string $subject,
    string $htmlBody,
    string $textBody
): bool {
    $username = (string)($secrets['gmail_address'] ?? '');
    $password = (string)($secrets['gmail_app_password'] ?? '');

    if ($username === '' || $password === '') {
        error_log('CitiSense mailer: no email provider configured. Set BREVO_API_KEY (recommended on Railway) or GMAIL_ADDRESS + GMAIL_APP_PASSWORD.');
        return false;
    }

    $autoload = __DIR__ . '/vendor/autoload.php';
    if (!file_exists($autoload)) {
        error_log('CitiSense mailer: vendor/autoload.php not found. Run "composer install" in the api folder.');
        return false;
    }
    require_once $autoload;

    try {
        $mail = new PHPMailer\PHPMailer\PHPMailer(true);
        $mail->isSMTP();
        $mail->Host = 'smtp.gmail.com';
        $mail->SMTPAuth = true;
        $mail->Username = $username;
        $mail->Password = $password;
        $mail->SMTPSecure = PHPMailer\PHPMailer\PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port = 587;
        $mail->Timeout = 15;
        $mail->CharSet = 'UTF-8';

        // Gmail only allows sending as the authenticated account.
        $mail->setFrom($username, $fromName);
        $mail->addAddress($toEmail, $toName);

        $mail->isHTML(true);
        $mail->Subject = $subject;
        $mail->Body = $htmlBody;
        $mail->AltBody = $textBody;

        $mail->send();
        return true;
    } catch (Throwable $e) {
        error_log('CitiSense mailer (SMTP) failed: ' . $e->getMessage()
            . ' (On Railway Free/Hobby, SMTP is blocked; set BREVO_API_KEY instead.)');
        return false;
    }
}

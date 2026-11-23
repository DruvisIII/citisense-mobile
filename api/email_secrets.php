<?php

function citisense_load_secrets(): array
{
    static $cached = null;
    if ($cached !== null) {
        return $cached;
    }

    // Load local credentials for XAMPP.
    $localFile = __DIR__ . '/password_reset_secrets.php';
    $secrets = [];

    if (is_file($localFile)) {
        $localSecrets = require $localFile;

        if (is_array($localSecrets)) {
            $secrets = $localSecrets;
        }
    }

    // Railway environment variables override local values.
    $environmentVariables = [
        'gmail_address' => 'GMAIL_ADDRESS',
        'gmail_app_password' => 'GMAIL_APP_PASSWORD',
        'semaphore_api_key' => 'SEMAPHORE_API_KEY',
        'semaphore_sendername' => 'SEMAPHORE_SENDERNAME',
        'brevo_api_key' => 'BREVO_API_KEY',
        'resend_api_key' => 'RESEND_API_KEY',
        'mail_from_email' => 'MAIL_FROM_EMAIL',
        'mail_from_name' => 'MAIL_FROM_NAME',
    ];

    foreach ($environmentVariables as $key => $variable) {
        $value = getenv($variable);

        if ($value !== false && trim($value) !== '') {
            $secrets[$key] = trim($value);
        }
    }

    $cached = $secrets;
    return $secrets;
}

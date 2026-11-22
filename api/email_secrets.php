
<?php

function citisense_load_secrets(): array
{
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
    ];

    foreach ($environmentVariables as $key => $variable) {
        $value = getenv($variable);

        if ($value !== false && trim($value) !== '') {
            $secrets[$key] = trim($value);
        }
    }

    return $secrets;
}

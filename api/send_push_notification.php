<?php
// Internal helper for sending Firebase Cloud Messaging (FCM) pushes.
//
// The Firebase service-account key is read from, in order:
//   1. FIREBASE_SERVICE_ACCOUNT_JSON  Railway variable holding the whole
//                                      JSON file (raw JSON or base64 of it)
//   2. FIREBASE_SERVICE_ACCOUNT_PATH  path to the JSON file
//   3. the local XAMPP path below
// Never commit the key to the repository.

declare(strict_types=1);

require_once __DIR__ . '/vendor/autoload.php';

use Google\Auth\Credentials\ServiceAccountCredentials;

const CITISENSE_LOCAL_FIREBASE_KEY = 'C:/Users/Lenovo/citisense-secrets/firebase-service-account.json';

/**
 * The service-account key as an array, or null when it is not configured.
 */
function citisense_firebase_credentials(): ?array
{
    static $cached = false;
    if ($cached !== false) {
        return $cached;
    }

    $json = trim((string) getenv('FIREBASE_SERVICE_ACCOUNT_JSON'));

    if ($json !== '' && $json[0] !== '{') {
        // Allow base64 so the value fits on one line in Railway.
        $decoded = base64_decode($json, true);
        $json = $decoded !== false ? trim($decoded) : $json;
    }

    if ($json === '') {
        $path = trim((string) getenv('FIREBASE_SERVICE_ACCOUNT_PATH')) ?: CITISENSE_LOCAL_FIREBASE_KEY;
        if (is_readable($path)) {
            $json = (string) file_get_contents($path);
        }
    }

    if ($json === '') {
        error_log('FCM: no Firebase service account. Set FIREBASE_SERVICE_ACCOUNT_JSON.');
        return $cached = null;
    }

    $credentials = json_decode($json, true);
    if (!is_array($credentials) || empty($credentials['project_id']) || empty($credentials['private_key'])) {
        error_log('FCM: FIREBASE_SERVICE_ACCOUNT_JSON is not a valid service-account key.');
        return $cached = null;
    }

    return $cached = $credentials;
}

/**
 * Google OAuth access token for FCM, reused for every push in one request.
 */
function citisense_fcm_access_token(array $credentials): string
{
    static $token = null;
    static $expiresAt = 0;

    if ($token !== null && time() < $expiresAt - 60) {
        return $token;
    }

    $auth = (new ServiceAccountCredentials(
        ['https://www.googleapis.com/auth/firebase.messaging'],
        $credentials
    ))->fetchAuthToken();

    $accessToken = $auth['access_token'] ?? '';
    if (!is_string($accessToken) || $accessToken === '') {
        throw new RuntimeException('Could not get Google OAuth access token.');
    }

    $token = $accessToken;
    $expiresAt = time() + (int) ($auth['expires_in'] ?? 3000);

    return $token;
}

/**
 * Send one push. Returns 'sent', 'invalid_token' (the phone uninstalled the
 * app or the token expired, so delete it) or 'error'.
 */
function citisense_fcm_send(string $token, string $title, string $body, array $data = []): string
{
    $token = trim($token);
    if ($token === '') {
        return 'invalid_token';
    }

    $credentials = citisense_firebase_credentials();
    if ($credentials === null) {
        return 'error';
    }

    try {
        $accessToken = citisense_fcm_access_token($credentials);

        $safeData = [];
        foreach ($data as $key => $value) {
            $safeData[(string) $key] = (string) $value;
        }

        $payload = [
            'message' => [
                'token' => $token,
                'notification' => [
                    'title' => $title,
                    'body' => $body,
                ],
                'android' => [
                    'priority' => 'HIGH',
                    'notification' => [
                        'channel_id' => 'citisense_updates',
                        'notification_priority' => 'PRIORITY_HIGH',
                        'default_sound' => true,
                    ],
                ],
                'data' => (object) $safeData,
            ],
        ];

        $url = 'https://fcm.googleapis.com/v1/projects/'
            . rawurlencode((string) $credentials['project_id']) . '/messages:send';

        $handle = curl_init($url);
        curl_setopt_array($handle, [
            CURLOPT_POST => true,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => [
                'Authorization: Bearer ' . $accessToken,
                'Content-Type: application/json; charset=UTF-8',
            ],
            CURLOPT_POSTFIELDS => json_encode($payload, JSON_THROW_ON_ERROR),
            CURLOPT_CONNECTTIMEOUT => 8,
            CURLOPT_TIMEOUT => 20,
        ]);

        $response = curl_exec($handle);
        $status = (int) curl_getinfo($handle, CURLINFO_HTTP_CODE);
        $curlError = curl_error($handle);
        curl_close($handle);

        if ($response !== false && $status >= 200 && $status < 300) {
            return 'sent';
        }

        // 404 UNREGISTERED / 400 invalid token: this phone can't receive pushes.
        if (
            $status === 404 ||
            ($status === 400 && is_string($response) && str_contains($response, 'registration token'))
        ) {
            return 'invalid_token';
        }

        // Never log the registration token, OAuth token, or service-account contents.
        error_log('FCM send failed (HTTP ' . $status . '): ' . substr($curlError ?: (string) $response, 0, 500));
        return 'error';
    } catch (Throwable $e) {
        error_log('FCM sender error: ' . $e->getMessage());
        return 'error';
    }
}

/**
 * Kept for existing callers. True when FCM accepted the push.
 */
function sendPushNotification(string $token, string $title, string $body, array $data = []): bool
{
    return citisense_fcm_send($token, $title, $body, $data) === 'sent';
}

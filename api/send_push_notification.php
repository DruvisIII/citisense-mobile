<?php
// Internal helper. Called only by your authenticated report-status endpoint.
// Keep your Firebase service-account JSON outside the public web directory.

declare(strict_types=1);

require_once __DIR__ . '/vendor/autoload.php';

use Google\Auth\Credentials\ServiceAccountCredentials;

function sendPushNotification(string $token, string $title, string $body, array $data = []): bool
{
    $keyPath = 'C:/Users/Lenovo/citisense-secrets/firebase-service-account.json';

    if (!is_readable($keyPath)) {
        error_log('FCM service account is unavailable.');
        return false;
    }
    if (!function_exists('curl_init')) {
        error_log('FCM requires the PHP cURL extension.');
        return false;
    }
    if (trim($token) === '') {
        error_log('FCM send skipped: empty registration token.');
        return false;
    }

    try {
        $credentialsFile = json_decode((string) file_get_contents($keyPath), true, 512, JSON_THROW_ON_ERROR);
        $projectId = $credentialsFile['project_id'] ?? '';
        if (!is_string($projectId) || $projectId === '') {
            throw new RuntimeException('Missing Firebase project ID.');
        }

        $credentials = new ServiceAccountCredentials(
            ['https://www.googleapis.com/auth/firebase.messaging'],
            $keyPath
        );
        $auth = $credentials->fetchAuthToken();
        $accessToken = $auth['access_token'] ?? '';
        if (!is_string($accessToken) || $accessToken === '') {
            throw new RuntimeException('Could not get Google OAuth access token.');
        }

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
                    // High priority is appropriate for time-sensitive, user-visible report updates.
                    'priority' => 'HIGH',
                    'notification' => [
                        'channel_id' => 'citisense_updates',
                        'notification_priority' => 'PRIORITY_HIGH',
                        'default_sound' => true,
                    ],
                ],
                'data' => $safeData,
            ],
        ];

        $url = 'https://fcm.googleapis.com/v1/projects/' . rawurlencode($projectId) . '/messages:send';
        $handle = curl_init($url);
        if ($handle === false) {
            throw new RuntimeException('Could not initialize cURL.');
        }

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

        if ($response === false || $status < 200 || $status >= 300) {
            // Never log the registration token, OAuth token, or service-account contents.
            error_log('FCM send failed (HTTP ' . $status . '): ' . substr($curlError ?: (string) $response, 0, 500));
            return false;
        }

        return true; // Accepted by FCM, not proof that Android displayed a banner.
    } catch (Throwable $e) {
        error_log('FCM sender error: ' . $e->getMessage());
        return false;
    }
}

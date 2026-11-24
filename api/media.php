<?php
// ============================================================
// MEDIA (announcement pictures and profile pictures)
// ------------------------------------------------------------
// GET media.php?p=uploads/announcements/9f1c....jpg
//
// Sends the picture saved by the admin website or by this API.
// Only files inside the folders in CITISENSE_PUBLIC_MEDIA_FOLDERS
// are served (never report photos or anything else).
//
// When the file is not on this server (the admin website runs on
// its own server, e.g. a separate Railway service), it is
// downloaded from ANNOUNCEMENT_MEDIA_BASE_URL, the admin website's
// address, e.g. https://citisense-admin.up.railway.app/
// ============================================================

require_once __DIR__ . '/media_common.php';

ini_set('display_errors', '0');

$path = citisense_clean_media_path((string) ($_GET['p'] ?? ''));

if ($path === '') {
    http_response_code(404);
    exit;
}

$allowed = [
    'image/jpeg' => true,
    'image/png' => true,
    'image/webp' => true,
    'image/gif' => true,
];

$file = citisense_find_media_file($path);

if ($file !== '') {
    $mime = (new finfo(FILEINFO_MIME_TYPE))->file($file) ?: '';
    if (!isset($allowed[$mime])) {
        http_response_code(404);
        exit;
    }

    $modified = filemtime($file) ?: time();
    $etag = '"' . md5($path . '|' . filesize($file) . '|' . $modified) . '"';

    header('Content-Type: ' . $mime);
    header('X-Content-Type-Options: nosniff');
    header('Cache-Control: public, max-age=86400');
    header('ETag: ' . $etag);

    if (trim((string) ($_SERVER['HTTP_IF_NONE_MATCH'] ?? '')) === $etag) {
        http_response_code(304);
        exit;
    }

    header('Content-Length: ' . filesize($file));
    readfile($file);
    exit;
}

// Not on this server: ask the admin website.
$remoteBase = trim((string) getenv('ANNOUNCEMENT_MEDIA_BASE_URL'));

if ($remoteBase === '' || !preg_match('~^https?://~i', $remoteBase) || !function_exists('curl_init')) {
    http_response_code(404);
    exit;
}

$remoteUrl = rtrim($remoteBase, '/') . '/' . implode('/', array_map('rawurlencode', explode('/', $path)));

$maxBytes = 15 * 1024 * 1024;
$body = '';
$tooLarge = false;

$curl = curl_init($remoteUrl);
curl_setopt_array($curl, [
    CURLOPT_FOLLOWLOCATION => false,
    CURLOPT_CONNECTTIMEOUT => 8,
    CURLOPT_TIMEOUT => 25,
    CURLOPT_PROTOCOLS => CURLPROTO_HTTP | CURLPROTO_HTTPS,
    CURLOPT_WRITEFUNCTION => static function ($handle, string $chunk) use (&$body, &$tooLarge, $maxBytes): int {
        if (strlen($body) + strlen($chunk) > $maxBytes) {
            $tooLarge = true;
            return 0;
        }
        $body .= $chunk;
        return strlen($chunk);
    },
]);
curl_exec($curl);
$status = (int) curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
curl_close($curl);

if ($tooLarge || $status !== 200 || $body === '') {
    error_log('CitiSense media: ' . $path . ' not found on this server or at ANNOUNCEMENT_MEDIA_BASE_URL (HTTP ' . $status . ').');
    http_response_code(404);
    exit;
}

$mime = (new finfo(FILEINFO_MIME_TYPE))->buffer($body) ?: '';
if (!isset($allowed[$mime])) {
    // E.g. the admin website answered with an HTML page instead of a picture.
    error_log('CitiSense media: ' . $path . ' from ANNOUNCEMENT_MEDIA_BASE_URL is not a picture (' . $mime . ').');
    http_response_code(404);
    exit;
}

header('Content-Type: ' . $mime);
header('X-Content-Type-Options: nosniff');
header('Cache-Control: public, max-age=86400');
header('Content-Length: ' . strlen($body));
echo $body;

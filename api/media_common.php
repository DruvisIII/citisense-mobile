<?php
// ============================================================
// PICTURES SHARED WITH THE APP
// ------------------------------------------------------------
// Announcement pictures and profile pictures can be saved by two
// different servers:
//   - this API (residents' profile pictures: uploads/profile/...)
//   - the admin website (announcement pictures:
//     uploads/announcements/..., admin profile pictures:
//     uploads/profile_pictures/...)
//
// The app loads all of them through media.php on this API, which
// finds the file on this server, or, when the admin website runs
// on another server, downloads it from ANNOUNCEMENT_MEDIA_BASE_URL
// (the admin website's address). The database keeps the relative
// path exactly as the uploader saved it.
// ============================================================

/** Folders that may hold an "uploads" folder, most likely first. */
function citisense_media_roots(): array
{
    static $roots = null;
    if ($roots !== null) {
        return $roots;
    }

    $api = __DIR__;
    $project = dirname($api);
    $list = [];

    $adminRoot = trim((string) getenv('CS_UPLOAD_ROOT'));
    if ($adminRoot !== '') {
        // The admin website's volume (if both run on one server).
        $list[] = rtrim($adminRoot, '/\\');
    }

    $list[] = $project;
    $list[] = $api;

    // XAMPP: the admin website is another folder in htdocs.
    $htdocs = dirname($project);
    foreach (array_merge(
        glob($htdocs . '/*/uploads', GLOB_ONLYDIR) ?: [],
        glob($htdocs . '/*/*/uploads', GLOB_ONLYDIR) ?: []
    ) as $found) {
        $list[] = dirname($found);
        $list[] = dirname($found) . '/admin';
    }
    $list[] = $project . '/admin';

    $roots = [];
    foreach ($list as $dir) {
        $real = realpath($dir);
        if ($real !== false && is_dir($real)) {
            $roots[str_replace('\\', '/', $real) . '/'] = true;
        }
    }

    return $roots = array_keys($roots);
}

/** Folders the app may load pictures from (never report evidence elsewhere). */
const CITISENSE_PUBLIC_MEDIA_FOLDERS = [
    'uploads/announcements/',
    'uploads/profile/',
    'uploads/profile_pictures/',
];

/** Clean relative picture path, or '' when it is unsafe or not allowed. */
function citisense_clean_media_path(?string $path): string
{
    $path = str_replace('\\', '/', trim((string) $path));
    // Older rows may be saved relative to another folder ("../uploads/...").
    $path = ltrim(preg_replace('~^(\.\.?/)+~', '', ltrim($path, '/')) ?? '', '/');

    if (
        $path === '' ||
        str_contains($path, '..') ||
        str_contains($path, "\0") ||
        !preg_match('~\.(jpe?g|png|webp|gif)$~i', $path)
    ) {
        return '';
    }

    foreach (CITISENSE_PUBLIC_MEDIA_FOLDERS as $folder) {
        if (str_starts_with($path, $folder)) {
            return $path;
        }
    }

    return '';
}

/** Absolute file for a stored picture path on this server, or ''. */
function citisense_find_media_file(string $path): string
{
    $path = citisense_clean_media_path($path);
    if ($path === '') {
        return '';
    }

    // UPLOAD_ROOT is the API's "uploads" folder itself (see submit_report.php):
    // uploads/profile/x.jpg is saved as UPLOAD_ROOT/profile/x.jpg.
    $uploadRoot = trim((string) getenv('UPLOAD_ROOT'));
    if ($uploadRoot !== '') {
        $base = realpath($uploadRoot);
        if ($base !== false) {
            $base = str_replace('\\', '/', $base) . '/';
            $file = realpath($base . substr($path, strlen('uploads/')));
            if ($file !== false && is_file($file) && str_starts_with(str_replace('\\', '/', $file), $base)) {
                return $file;
            }
        }
    }

    foreach (citisense_media_roots() as $root) {
        $file = realpath($root . $path);
        if ($file !== false && is_file($file) && str_starts_with(str_replace('\\', '/', $file), $root)) {
            return $file;
        }
    }

    return '';
}

/** This API's own address, e.g. https://api.example.com/ or http://host/citisense/api/. */
function citisense_api_base_url(): string
{
    $configured = trim((string) getenv('API_PUBLIC_URL'));
    if ($configured !== '') {
        return rtrim($configured, '/') . '/';
    }

    $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
        || strtolower((string) ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '')) === 'https';
    $host = (string) ($_SERVER['HTTP_HOST'] ?? 'localhost');
    $dir = rtrim(str_replace('\\', '/', dirname((string) ($_SERVER['SCRIPT_NAME'] ?? '/index.php'))), '/');

    return ($https ? 'https' : 'http') . '://' . $host . $dir . '/';
}

/**
 * Web address the app uses for a stored picture path:
 * full URLs are kept, relative paths go through media.php.
 * Returns '' when there is no picture.
 */
function citisense_media_url(?string $path): string
{
    $path = trim((string) $path);
    if ($path === '') {
        return '';
    }
    if (preg_match('~^https?://~i', $path)) {
        return $path;
    }

    $clean = citisense_clean_media_path($path);
    if ($clean === '') {
        return '';
    }

    return citisense_api_base_url() . 'media.php?p=' . rawurlencode($clean);
}

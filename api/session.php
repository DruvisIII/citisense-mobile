<?php
// ============================================================
// APP SESSION (stay logged in / log out)
// ------------------------------------------------------------
// Header X-Auth-Token: session token from login.php
//
// POST action=restore
//     When the app opens, it sends the token it saved at login.
//     Returns the same "user" object as login.php while the session
//     is valid, or HTTP 401 (code SESSION_EXPIRED) when it is not.
//
// POST action=logout [, fcmToken]
//     Ends this phone's session on the server, and stops push
//     notifications for this account on this phone.
// ============================================================

declare(strict_types=1);

ini_set('display_errors', '0');
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Accept, X-Auth-Token');
header('Cache-Control: no-store');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

function session_respond(bool $success, string $message, int $status = 200, array $extra = []): never
{
    http_response_code($status);
    echo json_encode(['success' => $success, 'message' => $message] + $extra);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    session_respond(false, 'Invalid request method.', 405);
}

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth.php';

$action = (string) ($_POST['action'] ?? '');

try {
    if ($action === 'logout') {
        $userID = citisense_session_user($conn);
        $fcmToken = trim((string) ($_POST['fcmToken'] ?? ''));

        if ($userID !== null && $fcmToken !== '' && strlen($fcmToken) <= 512) {
            try {
                $stmt = $conn->prepare('DELETE FROM user_device_tokens WHERE userID = ? AND fcmToken = ?');
                $stmt->bind_param('ss', $userID, $fcmToken);
                $stmt->execute();
                $stmt->close();
            } catch (Throwable $tokenError) {
                error_log('CitiSense logout: device token not removed: ' . $tokenError->getMessage());
            }
        }

        citisense_end_current_session($conn);
        session_respond(true, 'You have been logged out.');
    }

    if ($action !== 'restore') {
        session_respond(false, 'Unknown action.', 400);
    }

    $userID = citisense_session_user($conn);
    if ($userID === null) {
        session_respond(false, 'Your session has expired. Please log in again.', 401, ['code' => 'SESSION_EXPIRED']);
    }

    $stmt = $conn->prepare(
        'SELECT userID, firstName, lastName, email, contactNo, profilePic, barangayID
         FROM users WHERE userID = ? LIMIT 1'
    );
    $stmt->bind_param('s', $userID);
    $stmt->execute();
    $user = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$user) {
        // The account was removed: the session is no longer valid.
        citisense_end_current_session($conn);
        session_respond(false, 'Your session has expired. Please log in again.', 401, ['code' => 'SESSION_EXPIRED']);
    }

    session_respond(true, 'Session restored.', 200, [
        'user' => [
            'userID' => (string) $user['userID'],
            'firstName' => $user['firstName'],
            'lastName' => $user['lastName'],
            'email' => $user['email'],
            'contactNo' => $user['contactNo'],
            'profilePic' => $user['profilePic'],
            'barangayID' => $user['barangayID'],
        ],
    ]);
} catch (Throwable $e) {
    error_log('CitiSense session error: ' . $e->getMessage());
    session_respond(false, 'Something went wrong. Please try again later.', 500);
}

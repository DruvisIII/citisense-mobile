<?php
// ============================================================
// APP SESSIONS
// ------------------------------------------------------------
// login.php gives the app a random session token. Endpoints that
// return or change private data (messages, comments, notifications,
// password) call citisense_require_user(), so knowing someone's
// userID (USR001, USR002, ...) is not enough to read their data.
//
// Only a SHA-256 hash of each token is stored. Tokens expire after
// 30 days without use, and are deleted when the password changes.
// The app sends the token in the "X-Auth-Token" header.
// ============================================================

const CITISENSE_SESSION_DAYS = 30;

function citisense_ensure_sessions_table(mysqli $conn): void
{
    static $done = false;
    if ($done) {
        return;
    }

    $conn->query(
        "CREATE TABLE IF NOT EXISTS user_sessions (
            tokenHash CHAR(64) NOT NULL,
            userID VARCHAR(50) NOT NULL,
            createdAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            lastUsedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (tokenHash),
            KEY idx_user_sessions_user (userID)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );
    $done = true;
}

/**
 * Creates a session for the user and returns the token (shown once).
 */
function citisense_create_session(mysqli $conn, string $userID): string
{
    citisense_ensure_sessions_table($conn);

    $token = bin2hex(random_bytes(32));
    $hash = hash('sha256', $token);

    $stmt = $conn->prepare('INSERT INTO user_sessions (tokenHash, userID) VALUES (?, ?)');
    $stmt->bind_param('ss', $hash, $userID);
    $stmt->execute();
    $stmt->close();

    // Housekeeping: drop sessions unused for too long.
    $conn->query(
        'DELETE FROM user_sessions WHERE lastUsedAt < NOW() - INTERVAL ' . CITISENSE_SESSION_DAYS . ' DAY'
    );

    return $token;
}

/** Ends every session of a user (e.g. after a password change). */
function citisense_end_sessions(mysqli $conn, string $userID, ?string $keepToken = null): void
{
    citisense_ensure_sessions_table($conn);

    if ($keepToken !== null && $keepToken !== '') {
        $keep = hash('sha256', $keepToken);
        $stmt = $conn->prepare('DELETE FROM user_sessions WHERE userID = ? AND tokenHash <> ?');
        $stmt->bind_param('ss', $userID, $keep);
    } else {
        $stmt = $conn->prepare('DELETE FROM user_sessions WHERE userID = ?');
        $stmt->bind_param('s', $userID);
    }
    $stmt->execute();
    $stmt->close();
}

function citisense_request_token(): string
{
    $token = $_SERVER['HTTP_X_AUTH_TOKEN'] ?? ($_POST['authToken'] ?? ($_GET['authToken'] ?? ''));
    return trim((string) $token);
}

/**
 * True when the request carries a valid session token for $userID.
 */
function citisense_check_user(mysqli $conn, string $userID): bool
{
    $token = citisense_request_token();
    if ($userID === '' || !preg_match('/^[a-f0-9]{64}$/', $token)) {
        return false;
    }

    citisense_ensure_sessions_table($conn);

    $hash = hash('sha256', $token);
    $stmt = $conn->prepare(
        'SELECT userID FROM user_sessions
         WHERE tokenHash = ?
           AND lastUsedAt >= NOW() - INTERVAL ' . CITISENSE_SESSION_DAYS . ' DAY
         LIMIT 1'
    );
    $stmt->bind_param('s', $hash);
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$row || !hash_equals((string) $row['userID'], $userID)) {
        return false;
    }

    $stmt = $conn->prepare('UPDATE user_sessions SET lastUsedAt = NOW() WHERE tokenHash = ?');
    $stmt->bind_param('s', $hash);
    $stmt->execute();
    $stmt->close();

    return true;
}

/**
 * Stops with HTTP 401 unless the request is from $userID's session.
 */
function citisense_require_user(mysqli $conn, string $userID): void
{
    if (!citisense_check_user($conn, $userID)) {
        http_response_code(401);
        echo json_encode([
            'success' => false,
            'code' => 'SESSION_EXPIRED',
            'message' => 'Your session has expired. Please log in again.',
        ]);
        exit;
    }
}

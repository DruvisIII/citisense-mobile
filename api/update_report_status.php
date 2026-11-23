<?php


// ============================================================
// CITISENSE - ADMIN REPORT STATUS UPDATE
//
// Features:
// 1. Validate admin session and CSRF token.
// 2. Update report status.
// 3. Save an in-app notification to MySQL.
// 4. Send a Firebase push notification.
// 5. Prevent duplicate notifications for unchanged statuses.
// ============================================================

session_start();

ini_set('display_errors', '0');
error_reporting(E_ALL);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

// ============================================================
// JSON RESPONSE HELPER
// ============================================================

function respond(
    int $code,
    bool $success,
    string $message,
    array $extra = []
): void {
    http_response_code($code);

    echo json_encode(
        array_merge(
            [
                'success' => $success,
                'message' => $message
            ],
            $extra
        )
    );

    exit;
}

// ============================================================
// REQUIRE POST REQUEST
// ============================================================

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');

    respond(
        405,
        false,
        'POST required.'
    );
}

// ============================================================
// ADMIN AUTHENTICATION
// ============================================================

$adminId = $_SESSION['admin_id'] ?? null;
$barangayId = $_SESSION['barangay_id'] ?? null;

if (
    !is_scalar($adminId) ||
    trim((string) $adminId) === '' ||
    !is_scalar($barangayId) ||
    trim((string) $barangayId) === ''
) {
    respond(
        401,
        false,
        'Admin login required.'
    );
}

// ============================================================
// CSRF PROTECTION
// ============================================================

$csrf = $_POST['csrf_token'] ?? '';

if (
    !is_string($csrf) ||
    !isset($_SESSION['csrf_token']) ||
    !is_string($_SESSION['csrf_token']) ||
    !hash_equals($_SESSION['csrf_token'], $csrf)
) {
    respond(
        403,
        false,
        'Invalid security token.'
    );
}

// ============================================================
// RECEIVE REQUEST DATA
// ============================================================

$reportId = trim((string) ($_POST['reportID'] ?? ''));
$statusId = trim((string) ($_POST['statusID'] ?? ''));

if (
    $reportId === '' ||
    $statusId === '' ||
    strlen($reportId) > 50 ||
    strlen($statusId) > 50
) {
    respond(
        400,
        false,
        'Report ID and status ID are required.'
    );
}

// ============================================================
// DATABASE CONNECTION
// ============================================================

require_once __DIR__ . '/config.php';

$transactionStarted = false;

try {

    // ========================================================
    // BEGIN TRANSACTION
    // ========================================================

    $conn->begin_transaction();
    $transactionStarted = true;

    $adminBarangay = (string) $barangayId;

    // ========================================================
    // FIND REPORT AND CONFIRM BARANGAY OWNERSHIP
    // ========================================================

    $stmt = $conn->prepare(
        'SELECT reportID, userID, statusID
         FROM reports
         WHERE reportID = ?
           AND barangayID = ?
         FOR UPDATE'
    );

    $stmt->bind_param(
        'ss',
        $reportId,
        $adminBarangay
    );

    $stmt->execute();

    $report = $stmt->get_result()->fetch_assoc();

    $stmt->close();

    if (!$report) {
        $conn->rollback();

        respond(
            404,
            false,
            'Report not found in your barangay.'
        );
    }

    // ========================================================
    // VALIDATE NEW STATUS
    // ========================================================

    $stmt = $conn->prepare(
        'SELECT statusName
         FROM stats
         WHERE statusID = ?
         LIMIT 1'
    );

    $stmt->bind_param('s', $statusId);
    $stmt->execute();

    $status = $stmt->get_result()->fetch_assoc();

    $stmt->close();

    if (!$status) {
        $conn->rollback();

        respond(
            400,
            false,
            'Unknown report status.'
        );
    }

    // ========================================================
    // DO NOT NOTIFY IF STATUS HAS NOT CHANGED
    // ========================================================

    if ((string) $report['statusID'] === $statusId) {
        $conn->commit();

        respond(
            200,
            true,
            'No change: report already has this status.',
            [
                'changed' => false
            ]
        );
    }

    // ========================================================
    // PREPARE NOTIFICATION INFORMATION
    // ========================================================

    $userId = trim((string) $report['userID']);
    $statusName = (string) $status['statusName'];

    if ($userId === '') {
        throw new RuntimeException(
            'Report owner has no user ID.'
        );
    }

    $notificationMessage =
        'Your report ' .
        $reportId .
        ' is now ' .
        $statusName .
        '.';

    // Generate a unique primary key within VARCHAR(50).
    // Example: NOT8F7C2A...
    $notificationId =
        'NOT' . strtoupper(bin2hex(random_bytes(16)));

    // ========================================================
    // UPDATE REPORT STATUS
    // ========================================================

    $stmt = $conn->prepare(
        'UPDATE reports
         SET statusID = ?,
             timeline = CURRENT_TIMESTAMP
         WHERE reportID = ?
           AND barangayID = ?'
    );

    $stmt->bind_param(
        'sss',
        $statusId,
        $reportId,
        $adminBarangay
    );

    $stmt->execute();
    $stmt->close();

    // ========================================================
    // SAVE IN-APP NOTIFICATION
    //
    // Table: notification
    //
    // notifID  - Generated unique ID
    // userID   - Resident who submitted report
    // reportID - Updated report
    // message  - Status notification text
    // isRead   - 0 (unread)
    // dateSent - Automatic timestamp
    // ========================================================

    $stmt = $conn->prepare(
        'INSERT INTO notification
            (
                notifID,
                userID,
                reportID,
                message,
                isRead,
                dateSent
            )
         VALUES (?, ?, ?, ?, 0, CURRENT_TIMESTAMP)'
    );

    $stmt->bind_param(
        'ssss',
        $notificationId,
        $userId,
        $reportId,
        $notificationMessage
    );

    $stmt->execute();
    $stmt->close();

    // Save both the report status and in-app notification.
    $conn->commit();
    $transactionStarted = false;

} catch (Throwable $e) {

    if ($transactionStarted) {
        try {
            $conn->rollback();
        } catch (Throwable $ignored) {
        }
    }

    error_log(
        'CitiSense report status update failed: ' .
        $e->getMessage()
    );

    respond(
        500,
        false,
        'Could not update report status.'
    );
}

// ============================================================
// SEND FIREBASE PUSH NOTIFICATION
//
// The database transaction has already committed.
// A Firebase failure will not erase the status update or
// the saved in-app notification.
// ============================================================

$pushAccepted = 0;

try {

    require_once __DIR__ . '/send_push_notification.php';

    // Find all registered devices for the report owner.
    $stmt = $conn->prepare(
        'SELECT fcmToken
         FROM user_device_tokens
         WHERE userID = ?'
    );

    $stmt->bind_param('s', $userId);
    $stmt->execute();

    $tokens = $stmt->get_result();

    while ($row = $tokens->fetch_assoc()) {

        $token = trim((string) $row['fcmToken']);

        if ($token === '') {
            continue;
        }

        $sent = sendPushNotification(
            $token,
            'Report Status Updated',
            $notificationMessage,
            [
                'type' => 'report_status',
                'reportID' => $reportId,
                'statusID' => $statusId
            ]
        );

        if ($sent) {
            $pushAccepted++;
        }
    }

    $stmt->close();

} catch (Throwable $e) {

    error_log(
        'CitiSense status saved, but push failed: ' .
        $e->getMessage()
    );
}

// ============================================================
// FINAL RESPONSE
// ============================================================

respond(
    200,
    true,
    'Report status updated.',
    [
        'changed' => true,
        'notificationSaved' => true,
        'pushAccepted' => $pushAccepted
    ]
);

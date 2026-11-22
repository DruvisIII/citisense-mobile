<?php

/*
|--------------------------------------------------------------------------
| CITISENSE ENGAGEMENT - SHARED HELPERS
|--------------------------------------------------------------------------
| Used by the report feedback, report messages, and app feedback endpoints.
| Creates the three tables the first time they are needed:
|
|   report_messages  Two-way conversation per report (resident <-> barangay)
|   report_feedback  Resident's confirmation + rating after a report is resolved
|   app_feedback     Suggestions / complaints about the app itself
*/

function engagement_respond(
    bool $success,
    string $message,
    int $status = 200,
    array $extra = []
): void {
    http_response_code($status);
    echo json_encode(array_merge([
        'success' => $success,
        'message' => $message
    ], $extra));
    exit;
}

function engagement_headers(): void
{
    error_reporting(E_ALL);
    ini_set('display_errors', '0');

    header('Content-Type: application/json; charset=utf-8');
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: POST, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Accept');

    if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
        http_response_code(200);
        exit;
    }

    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        engagement_respond(false, 'Invalid request method.', 405);
    }
}

function ensure_engagement_tables(mysqli $conn): void
{
    $queries = [
        "CREATE TABLE IF NOT EXISTS report_messages (
            id INT AUTO_INCREMENT PRIMARY KEY,
            reportID VARCHAR(50) NOT NULL,
            senderType ENUM('resident', 'barangay') NOT NULL,
            senderID VARCHAR(50) NOT NULL,
            message TEXT NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_report_messages_report (reportID)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS report_feedback (
            id INT AUTO_INCREMENT PRIMARY KEY,
            reportID VARCHAR(50) NOT NULL,
            userID VARCHAR(50) NOT NULL,
            is_fixed TINYINT(1) NOT NULL,
            rating TINYINT NOT NULL,
            comment VARCHAR(500) NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY uq_report_feedback_report (reportID)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS app_feedback (
            id INT AUTO_INCREMENT PRIMARY KEY,
            userID VARCHAR(50) NOT NULL,
            feedback_type VARCHAR(30) NOT NULL,
            rating TINYINT NULL,
            message TEXT NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_app_feedback_user (userID)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    ];

    foreach ($queries as $sql) {
        if (!$conn->query($sql)) {
            error_log('CitiSense engagement table error: ' . $conn->error);
            engagement_respond(false, 'Database error.', 500);
        }
    }
}

/**
 * Returns the report row when it belongs to the user, otherwise stops
 * with an error. Residents can only see and act on their own reports.
 */
function require_own_report(mysqli $conn, string $userID, string $reportID): array
{
    $stmt = $conn->prepare(
        "SELECT reportID, userID, barangayID, statusID, dateReported
         FROM reports
         WHERE reportID = ? AND userID = ?
         LIMIT 1"
    );

    if (!$stmt) {
        engagement_respond(false, 'Database error.', 500);
    }

    $stmt->bind_param('ss', $reportID, $userID);
    $stmt->execute();
    $report = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$report) {
        engagement_respond(false, 'Report not found.', 404);
    }

    return $report;
}

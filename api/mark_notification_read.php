
<?php

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Accept");

if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") {
    http_response_code(200);
    exit;
}

require_once "config.php";

$input = json_decode(file_get_contents("php://input"), true);

if (
    !is_array($input) ||
    empty($input["userID"]) ||
    empty($input["type"]) ||
    !isset($input["id"])
) {
    echo json_encode([
        "success" => false,
        "message" => "User ID, notification type, and ID are required."
    ]);
    exit;
}

$userID = trim((string) $input["userID"]);
$type = trim((string) $input["type"]);
$id = trim((string) $input["id"]);

try {
    if ($type === "report") {

        $sql = "
            UPDATE notification
            SET isRead = 1
            WHERE notifID = ?
              AND userID = ?
        ";

        $stmt = $conn->prepare($sql);
        $stmt->bind_param("ss", $id, $userID);

    } elseif ($type === "announcement") {

        $announceID = filter_var(
            $id,
            FILTER_VALIDATE_INT
        );

        if ($announceID === false || $announceID === null) {
            throw new Exception("Invalid announcement ID.");
        }

        // Verify the announcement exists.
        $check = $conn->prepare("
            SELECT announceID
            FROM announcements
            WHERE announceID = ?
        ");

        $check->bind_param("i", $announceID);
        $check->execute();

        $exists = $check->get_result()->num_rows > 0;
        $check->close();

        if (!$exists) {
            throw new Exception("Announcement not found.");
        }

        // Create or update this user's read status.
        $sql = "
            INSERT INTO announcement_reads
                (announceID, userID, isRead, readAt)
            VALUES (?, ?, 1, CURRENT_TIMESTAMP)
            ON DUPLICATE KEY UPDATE
                isRead = 1,
                readAt = CURRENT_TIMESTAMP
        ";

        $stmt = $conn->prepare($sql);
        $stmt->bind_param("is", $announceID, $userID);

    } else {
        throw new Exception("Invalid notification type.");
    }

    if (!$stmt) {
        throw new Exception("Failed to prepare update.");
    }

    if (!$stmt->execute()) {
        throw new Exception("Failed to update notification.");
    }

    echo json_encode([
        "success" => true,
        "message" => "Notification marked as read."
    ]);

    $stmt->close();

} catch (Exception $e) {
    http_response_code(500);

    echo json_encode([
        "success" => false,
        "message" => $e->getMessage()
    ]);
}

$conn->close();

?>

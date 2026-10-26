
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
    empty($input["scope"])
) {
    echo json_encode([
        "success" => false,
        "message" => "User ID and scope are required."
    ]);
    exit;
}

$userID = trim((string) $input["userID"]);
$scope = trim((string) $input["scope"]);

if (!in_array($scope, ["all", "announcements"], true)) {
    echo json_encode([
        "success" => false,
        "message" => "Invalid scope."
    ]);
    exit;
}

try {
    $conn->begin_transaction();

    if ($scope === "all") {

        $stmt = $conn->prepare("
            UPDATE notification
            SET isRead = 1
            WHERE userID = ?
              AND isRead = 0
        ");

        $stmt->bind_param("s", $userID);
        $stmt->execute();
        $stmt->close();
    }

    /*
     * Mark announcements as read for this user.
     * Only announcements that are not already
     * tracked as read will be inserted or updated.
     */
    $sql = "
        INSERT INTO announcement_reads
            (announceID, userID, isRead, readAt)
        SELECT
            a.announceID,
            ?,
            1,
            CURRENT_TIMESTAMP
        FROM announcements a
        INNER JOIN users u
            ON u.userID = ?
           AND u.barangayID = a.barangayID
        ON DUPLICATE KEY UPDATE
            isRead = 1,
            readAt = CURRENT_TIMESTAMP
    ";

    $stmt = $conn->prepare($sql);
    $stmt->bind_param("ss", $userID, $userID);
    $stmt->execute();
    $stmt->close();

    $conn->commit();

    echo json_encode([
        "success" => true,
        "message" => "Notifications marked as read."
    ]);

} catch (Exception $e) {

    $conn->rollback();
    http_response_code(500);

    echo json_encode([
        "success" => false,
        "message" => "Failed to mark notifications as read."
    ]);
}

$conn->close();

?>

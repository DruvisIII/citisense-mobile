<?php

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Accept");

if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") {
    http_response_code(200);
    exit;
}

require_once "config.php";

// Check barangayID
if (!isset($_GET["barangayID"]) || trim($_GET["barangayID"]) === "") {
    echo json_encode([
        "success" => false,
        "message" => "Barangay ID is required."
    ]);
    exit;
}

$barangayID = trim($_GET["barangayID"]);

try {

    /*
     * Get announcements intended for the user's barangay.
     *
     * JOIN barangay is included so the API can also return
     * the barangay name.
     */
    $sql = "
        SELECT
            a.announceID,
            a.userID,
            a.barangayID,
            b.barangayName,
            a.title,
            a.content,
            a.datePosted
        FROM announcements a
        LEFT JOIN barangay b
            ON a.barangayID = b.barangayID
        WHERE a.barangayID = ?
        ORDER BY a.datePosted DESC
    ";

    $stmt = $conn->prepare($sql);

    if (!$stmt) {
        throw new Exception("Failed to prepare query.");
    }

    $stmt->bind_param("s", $barangayID);

    if (!$stmt->execute()) {
        throw new Exception("Failed to execute query.");
    }

    $result = $stmt->get_result();

    $announcements = [];

    while ($row = $result->fetch_assoc()) {
        $announcements[] = [
            "announceID" => $row["announceID"],
            "userID" => $row["userID"],
            "barangayID" => $row["barangayID"],
            "barangayName" => $row["barangayName"],
            "title" => $row["title"],
            "content" => $row["content"],
            "datePosted" => $row["datePosted"]
        ];
    }

    echo json_encode([
        "success" => true,
        "message" => "Announcements retrieved successfully.",
        "data" => $announcements
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
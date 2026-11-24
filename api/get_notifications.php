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

if (
    !isset($_GET["userID"]) ||
    trim($_GET["userID"]) === "" ||
    !isset($_GET["barangayID"]) ||
    trim($_GET["barangayID"]) === ""
) {
    echo json_encode([
        "success" => false,
        "message" => "User ID and Barangay ID are required."
    ]);
    exit;
}

$userID = trim($_GET["userID"]);
$barangayID = trim($_GET["barangayID"]);

try {
    $notifications = [];

    /*
     * Status names from the stats table (e.g. Pending, In Progress,
     * Resolved, Overdue), longest first so "In Progress" wins over
     * shorter names it contains.
     */
    $statusNames = [];
    $statsResult = $conn->query("SELECT statusName FROM stats");
    if ($statsResult) {
        while ($statRow = $statsResult->fetch_assoc()) {
            $name = trim((string) $statRow["statusName"]);
            if ($name !== "") {
                $statusNames[] = $name;
            }
        }
    }
    usort($statusNames, fn($a, $b) => mb_strlen($b) <=> mb_strlen($a));

    /*
     * The status this notification is about, read from the message the
     * admin panel writes ("Your report REP001 is now In Progress.").
     * Falls back to the report's current status.
     */
    $statusFromMessage = function (string $message, ?string $currentStatus) use ($statusNames): string {
        $lower = mb_strtolower($message);

        if (str_contains($lower, "was not accepted")) {
            return "Rejected";
        }
        if (str_contains($lower, "back to pending")) {
            return "Pending";
        }
        if (str_contains($lower, "replied") || str_contains($lower, "new message")) {
            return "New Message";
        }
        foreach ($statusNames as $name) {
            if (str_contains($lower, "is now " . mb_strtolower($name))) {
                return $name;
            }
        }

        return trim((string) $currentStatus) !== "" ? (string) $currentStatus : "Update";
    };

    /*
     * 1. Retrieve report notifications
     * belonging to the current user.
     */
    $sqlReports = "
        SELECT
            n.notifID,
            n.reportID,
            n.message,
            n.isRead,
            n.dateSent,
            s.statusName AS currentStatus
        FROM notification n
        LEFT JOIN reports r
            ON r.reportID = n.reportID
        LEFT JOIN stats s
            ON s.statusID = r.statusID
        WHERE n.userID = ?
        ORDER BY n.dateSent DESC
    ";

    $stmtReports = $conn->prepare($sqlReports);

    if (!$stmtReports) {
        throw new Exception(
            "Failed to prepare report notifications query."
        );
    }

    $stmtReports->bind_param("s", $userID);
    $stmtReports->execute();

    $resultReports = $stmtReports->get_result();

    while ($row = $resultReports->fetch_assoc()) {
        $notifications[] = [
            "id" => (string) $row["notifID"],
            "type" => "report",
            "reportID" => $row["reportID"],
            "title" => "Report Update",
            "status" => $statusFromMessage(
                (string) $row["message"],
                $row["currentStatus"] ?? null
            ),
            "message" => $row["message"],
            "timestamp" => $row["dateSent"],
            "isRead" => (bool) $row["isRead"]
        ];
    }

    $stmtReports->close();

    /*
     * 2. Retrieve announcements for the user's
     * barangay and their individual read status.
     */
    $sqlAnnouncements = "
        SELECT
            a.announceID,
            a.title,
            a.content,
            a.datePosted,
            COALESCE(ar.isRead, 0) AS isRead,
            b.barangayName
        FROM announcements a
        LEFT JOIN barangay b
            ON a.barangayID = b.barangayID
        LEFT JOIN announcement_reads ar
            ON ar.announceID = a.announceID
            AND ar.userID = ?
        WHERE a.barangayID = ?
        ORDER BY a.datePosted DESC
    ";

    $stmtAnnouncements = $conn->prepare($sqlAnnouncements);

    if (!$stmtAnnouncements) {
        throw new Exception(
            "Failed to prepare announcements query."
        );
    }

    $stmtAnnouncements->bind_param(
        "ss",
        $userID,
        $barangayID
    );

    $stmtAnnouncements->execute();

    $resultAnnouncements = $stmtAnnouncements->get_result();

    while ($row = $resultAnnouncements->fetch_assoc()) {
        $notifications[] = [
            "id" => (string) $row["announceID"],
            "type" => "announcement",
            "reportID" => null,
            "title" => $row["title"],
            "message" => $row["content"],
            "barangayName" => $row["barangayName"],
            "timestamp" => $row["datePosted"],
            "isRead" => (bool) $row["isRead"]
        ];
    }

    $stmtAnnouncements->close();

    /*
     * 3. Combine both types and sort newest first.
     */
    usort($notifications, function ($a, $b) {
        return strtotime($b["timestamp"])
            <=> strtotime($a["timestamp"]);
    });

    echo json_encode([
        "success" => true,
        "message" => "Notifications retrieved successfully.",
        "data" => $notifications
    ]);

} catch (Exception $e) {
    http_response_code(500);

    echo json_encode([
        "success" => false,
        "message" => "Failed to retrieve notifications."
    ]);
}

$conn->close();

?>

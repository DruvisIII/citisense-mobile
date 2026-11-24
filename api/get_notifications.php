<?php

// ============================================================
// GET NOTIFICATIONS
// ------------------------------------------------------------
// GET userID, barangayID   (header X-Auth-Token)
//
// Report notifications (status changes, barangay messages) and
// barangay announcements, newest first.
//
// - "status" is the report's CURRENT status from the reports
//   table, so a notification written while the report was Pending
//   shows In Progress / Resolved once the barangay updates it.
// - "timestamp" includes the database's UTC offset (see
//   time_helpers.php), so the app shows the correct "x minutes ago".
// ============================================================

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Accept, X-Auth-Token");

if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") {
    http_response_code(200);
    exit;
}

require_once __DIR__ . "/config.php";
require_once __DIR__ . "/auth.php";
require_once __DIR__ . "/time_helpers.php";

$userID = trim((string) ($_GET["userID"] ?? ""));
$barangayID = trim((string) ($_GET["barangayID"] ?? ""));

if ($userID === "" || $barangayID === "") {
    echo json_encode([
        "success" => false,
        "message" => "Please choose your barangay first."
    ]);
    exit;
}

try {
    citisense_require_user($conn, $userID);

    $notifications = [];

    // --------------------------------------------------------
    // Status names (Pending, In Progress, Resolved, Overdue, ...)
    // --------------------------------------------------------
    $statusNameByID = [];
    $statsResult = $conn->query("SELECT statusID, statusName FROM stats");
    if ($statsResult) {
        while ($statRow = $statsResult->fetch_assoc()) {
            $statusNameByID[(string) $statRow["statusID"]] = trim((string) $statRow["statusName"]);
        }
    }

    // Longest first so "In Progress" wins over shorter names it contains.
    $statusNames = array_values(array_filter($statusNameByID, "strlen"));
    usort($statusNames, fn($a, $b) => mb_strlen($b) <=> mb_strlen($a));

    /** Current status of each report, looked up once per report. */
    $currentStatusCache = [];
    $stmtStatus = $conn->prepare("SELECT statusID FROM reports WHERE reportID = ? LIMIT 1");
    $currentStatus = function (?string $reportID) use (&$currentStatusCache, $stmtStatus, $statusNameByID): ?string {
        $reportID = trim((string) $reportID);
        if ($reportID === "") {
            return null;
        }
        if (!array_key_exists($reportID, $currentStatusCache)) {
            $stmtStatus->bind_param("s", $reportID);
            $stmtStatus->execute();
            $row = $stmtStatus->get_result()->fetch_assoc();
            $currentStatusCache[$reportID] = $row
                ? ($statusNameByID[(string) $row["statusID"]] ?? null)
                : null;
        }
        return $currentStatusCache[$reportID];
    };

    /** Used only when the report no longer exists: read the status from the text. */
    $statusFromMessage = function (string $message) use ($statusNames): string {
        $lower = mb_strtolower($message);

        if (str_contains($lower, "was not accepted")) {
            return "Rejected";
        }
        if (str_contains($lower, "back to pending")) {
            return "Pending";
        }
        foreach ($statusNames as $name) {
            if (str_contains($lower, "is now " . mb_strtolower($name))) {
                return $name;
            }
        }
        return "Update";
    };

    // --------------------------------------------------------
    // 1. Report notifications for this user
    // --------------------------------------------------------
    $stmtReports = $conn->prepare(
        "SELECT notifID, reportID, message, isRead, dateSent
         FROM notification
         WHERE userID = ?
         ORDER BY dateSent DESC"
    );
    $stmtReports->bind_param("s", $userID);
    $stmtReports->execute();
    $resultReports = $stmtReports->get_result();

    while ($row = $resultReports->fetch_assoc()) {
        $message = (string) $row["message"];
        $lower = mb_strtolower($message);
        $reportID = $row["reportID"] !== null ? (string) $row["reportID"] : null;

        $isMessage = str_contains($lower, "new reply from your barangay")
            || str_contains($lower, "replied about your report")
            || str_contains($lower, "new message from the barangay");

        if ($isMessage) {
            $status = "New Message";
        } else {
            $status = $currentStatus($reportID) ?? $statusFromMessage($message);
        }

        $notifications[] = [
            "id" => (string) $row["notifID"],
            "type" => "report",
            "kind" => $isMessage
                ? ($reportID === null || $reportID === "" ? "message" : "report_message")
                : "status",
            "reportID" => $reportID,
            "title" => $isMessage ? "Message from your barangay" : "Report Update",
            "status" => $status,
            "message" => $message,
            "timestamp" => citisense_iso_time($conn, $row["dateSent"]),
            "isRead" => (bool) $row["isRead"]
        ];
    }

    $stmtReports->close();
    $stmtStatus->close();

    // --------------------------------------------------------
    // 2. Announcements for the user's barangay (+ read status)
    // --------------------------------------------------------
    $barangayName = null;
    $stmt = $conn->prepare("SELECT barangayName FROM barangay WHERE barangayID = ? LIMIT 1");
    $stmt->bind_param("s", $barangayID);
    $stmt->execute();
    $barangayRow = $stmt->get_result()->fetch_assoc();
    $stmt->close();
    if ($barangayRow) {
        $barangayName = $barangayRow["barangayName"];
    }

    $readAnnouncements = [];
    try {
        $stmt = $conn->prepare("SELECT announceID, isRead FROM announcement_reads WHERE userID = ?");
        $stmt->bind_param("s", $userID);
        $stmt->execute();
        foreach ($stmt->get_result()->fetch_all(MYSQLI_ASSOC) as $readRow) {
            $readAnnouncements[(string) $readRow["announceID"]] = (int) $readRow["isRead"] === 1;
        }
        $stmt->close();
    } catch (Throwable $readError) {
        // No read-status table yet: every announcement shows as unread.
        error_log("CitiSense announcement_reads unavailable: " . $readError->getMessage());
    }

    $stmtAnnouncements = $conn->prepare(
        "SELECT announceID, title, content, datePosted
         FROM announcements
         WHERE barangayID = ?
         ORDER BY datePosted DESC"
    );
    $stmtAnnouncements->bind_param("s", $barangayID);
    $stmtAnnouncements->execute();
    $resultAnnouncements = $stmtAnnouncements->get_result();

    while ($row = $resultAnnouncements->fetch_assoc()) {
        $notifications[] = [
            "id" => (string) $row["announceID"],
            "type" => "announcement",
            "kind" => "announcement",
            "reportID" => null,
            "title" => $row["title"],
            "message" => $row["content"],
            "barangayName" => $barangayName,
            "timestamp" => citisense_iso_time($conn, $row["datePosted"]),
            "isRead" => $readAnnouncements[(string) $row["announceID"]] ?? false
        ];
    }

    $stmtAnnouncements->close();

    // --------------------------------------------------------
    // 3. Newest first
    // --------------------------------------------------------
    usort($notifications, function ($a, $b) {
        return strtotime((string) $b["timestamp"]) <=> strtotime((string) $a["timestamp"]);
    });

    echo json_encode([
        "success" => true,
        "message" => "Notifications retrieved successfully.",
        "serverTime" => citisense_server_time($conn),
        "data" => $notifications
    ]);
} catch (Throwable $e) {
    error_log("CitiSense notifications error: " . $e->getMessage());
    http_response_code(500);

    echo json_encode([
        "success" => false,
        "message" => "We could not load your notifications. Please try again."
    ]);
}

$conn->close();
